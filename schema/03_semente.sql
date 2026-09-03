-- =============================================================================
-- Semente determinística.
--
-- **Nada de `random()`.** Os números vêm de `md5(chave)` convertido para
-- inteiro: parece aleatório, mas dá exatamente o mesmo resultado em qualquer
-- máquina e em qualquer versão do Postgres. É o que permite a CI comparar a
-- saída de cada consulta com um arquivo esperado — com `random()` nada disso
-- seria verificável, e o repositório inteiro viraria "confia em mim".
--
-- Volume: 8 clientes, 3 canais, ~30 campanhas, ~5.500 dias de métrica,
-- ~2.400 leads e ~600 vendas. Grande o bastante para os planos de execução
-- fazerem sentido, pequeno o bastante para semear em menos de um segundo.
-- =============================================================================

SET search_path TO trafego;

TRUNCATE venda, lead, metrica_diaria, campanha, canal, cliente RESTART IDENTITY CASCADE;

-- Pseudoaleatório estável: devolve um inteiro em [0, teto) a partir de um texto.
CREATE OR REPLACE FUNCTION sorteio(chave text, teto integer)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT ('x' || substr(md5(chave), 1, 8))::bit(32)::bigint % teto;
$$;

-- --- dimensões ---------------------------------------------------------------

INSERT INTO canal (nome, tipo) VALUES
    ('Google Ads', 'busca'),
    ('Meta Ads',   'social'),
    ('YouTube Ads','video');

-- Verbas calibradas contra o gasto real da semente: alguns clientes estouram
-- o teto em agosto e outros não. Um cenário em que ninguém estoura tornaria a
-- consulta 10 uma tabela de zeros.
INSERT INTO cliente (nome, segmento, verba_mensal_centavos, entrou_em, ativo) VALUES
    ('Padaria do Zé',        'alimentação', 2000000, DATE '2025-11-03', true),
    ('Ótica Vista Clara',    'varejo',      2500000, DATE '2025-08-18', true),
    ('Studio Pilates Norte', 'saúde',       1200000, DATE '2026-01-12', true),
    ('Advocacia Ramos',      'serviços',    3000000, DATE '2025-06-02', true),
    ('Marcenaria Bonfim',    'indústria',   1200000, DATE '2026-02-24', true),
    ('Escola Mundo Novo',    'educação',    2500000, DATE '2025-09-15', true),
    ('Pet Shop Lupi',        'varejo',       900000, DATE '2026-04-06', true),
    ('Clínica Odonto Sul',   'saúde',       1800000, DATE '2025-07-21', false);

-- Cada cliente ganha de 2 a 5 campanhas, distribuídas entre os canais.
INSERT INTO campanha (cliente_id, canal_id, nome, objetivo, inicio, fim)
SELECT
    c.id,
    1 + sorteio('canal' || c.id || '-' || n, 3),
    CASE sorteio('nome' || c.id || '-' || n, 6)
        WHEN 0 THEN 'Institucional'
        WHEN 1 THEN 'Promoção sazonal'
        WHEN 2 THEN 'Remarketing'
        WHEN 3 THEN 'Captação — bairro'
        WHEN 4 THEN 'Black Friday'
        ELSE        'Marca'
    END || ' ' || n,
    CASE sorteio('obj' || c.id || '-' || n, 4)
        WHEN 0 THEN 'leads' WHEN 1 THEN 'vendas' WHEN 2 THEN 'trafego' ELSE 'reconhecimento'
    END,
    DATE '2026-03-01' + sorteio('ini' || c.id || '-' || n, 90),
    -- Uma agência de verdade tem campanha pausada. As do Pet Shop Lupi
    -- terminam em 05/08: é o cenário que a consulta 09 (cliente que parou de
    -- receber lead) existe para pegar, e sem ele aquela consulta devolveria
    -- zero linhas para sempre — provando nada.
    CASE WHEN c.nome = 'Pet Shop Lupi' THEN DATE '2026-08-05' END
FROM cliente c
CROSS JOIN generate_series(1, 5) AS n
WHERE n <= 2 + sorteio('qtd' || c.id, 4);

-- --- métricas diárias --------------------------------------------------------
-- Uma linha por campanha por dia, do início da campanha até 31/08/2026.

INSERT INTO metrica_diaria (campanha_id, dia, impressoes, cliques, custo_centavos)
SELECT
    ca.id,
    d.dia,
    impressoes,
    -- CTR entre 1% e 6%, estável por campanha e dia.
    GREATEST(1, (impressoes * (10 + sorteio('ctr' || ca.id || d.dia, 50)) / 1000)),
    -- CPC entre R$ 0,40 e R$ 3,40, aplicado sobre os cliques.
    GREATEST(1, (impressoes * (10 + sorteio('ctr' || ca.id || d.dia, 50)) / 1000))
        * (40 + sorteio('cpc' || ca.id || d.dia, 300))
FROM campanha ca
CROSS JOIN LATERAL (
    SELECT generate_series(
               ca.inicio,
               LEAST(COALESCE(ca.fim, DATE '2026-08-31'), DATE '2026-08-31'),
               INTERVAL '1 day'
           )::date AS dia
) d
CROSS JOIN LATERAL (
    SELECT 400 + sorteio('imp' || ca.id || d.dia, 3600) AS impressoes
) m;

-- --- leads -------------------------------------------------------------------
-- Nasce de um clique: a data do lead é sempre um dia em que a campanha rodou.

INSERT INTO lead (campanha_id, criado_em, status)
SELECT
    m.campanha_id,
    m.dia,
    CASE sorteio('st' || m.campanha_id || m.dia || g, 10)
        WHEN 0 THEN 'novo'      WHEN 1 THEN 'novo'
        WHEN 2 THEN 'contatado' WHEN 3 THEN 'contatado'
        WHEN 4 THEN 'qualificado'
        WHEN 5 THEN 'perdido'   WHEN 6 THEN 'perdido'
        ELSE 'ganho'
    END
FROM metrica_diaria m
JOIN campanha ca ON ca.id = m.campanha_id
CROSS JOIN generate_series(1, 3) AS g
-- Nem todo dia gera lead: a taxa de conversão do clique fica em torno de 5%.
--
-- Campanha de reconhecimento é a exceção, e de propósito: ela existe para ser
-- vista, não para captar. Gasta igual e quase não converte — que é exatamente
-- a linha que a consulta 06 (onde estou gastando sem retorno) precisa
-- encontrar. Se a semente não tivesse esse caso, aquela consulta nunca
-- devolveria nada e ninguém saberia se ela funciona.
WHERE g <= sorteio('lead' || m.campanha_id || m.dia, 100) * m.cliques
           / CASE WHEN ca.objetivo = 'reconhecimento' THEN 90000 ELSE 1800 END;

-- --- vendas ------------------------------------------------------------------
-- Só lead 'ganho' vira venda, entre 1 e 30 dias depois de entrar.

INSERT INTO venda (lead_id, fechada_em, valor_centavos)
SELECT
    l.id,
    l.criado_em + sorteio('dias' || l.id, 30) + 1,
    25000 + sorteio('valor' || l.id, 475000)
FROM lead l
WHERE l.status = 'ganho';

DROP FUNCTION sorteio(text, integer);
