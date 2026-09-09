-- =============================================================================
-- Semente determinística — porte para MySQL 8.
--
-- Mesmo princípio do Postgres: **nada de `RAND()`**. Os números vêm do MD5 da
-- chave, então a mesma semente dá a mesma base em qualquer máquina, e é isso
-- que permite a CI comparar a saída de cada consulta com um arquivo esperado.
--
-- Cinco diferenças de dialeto moram aqui, e são as que mais custaram:
--
--   (a) `generate_series` não existe. Sequência de inteiros e de datas sai de
--       CTE recursiva, com `cte_max_recursion_depth` elevado.
--   (b) `/` entre inteiros **não trunca no MySQL** — devolve decimal. Onde o
--       Postgres fazia divisão inteira, aqui vai `DIV`. Trocar `/` por `/` sem
--       pensar mudaria silenciosamente todos os volumes da semente.
--   (c) `||` é OR, não concatenação. Vai `CONCAT()`.
--   (d) `data + inteiro` não soma dias. Vai `DATE_ADD(..., INTERVAL n DAY)`.
--   (e) O sorteio do Postgres passa por `::bit(32)::bigint`, que interpreta o
--       hash como **inteiro com sinal**. `CONV(...,16,10)` do MySQL devolve
--       sem sinal. Mantive o sem sinal de propósito — negativo ali só produz
--       id inválido —, e a consequência está registrada em `docs/dialetos.md`:
--       **as duas bases não têm os mesmos dados**, e por isso cada dialeto tem
--       seu próprio diretório de saída esperada.
-- =============================================================================

USE trafego_mysql;

SET SESSION cte_max_recursion_depth = 100000;

DROP FUNCTION IF EXISTS sorteio;
DELIMITER $$
CREATE FUNCTION sorteio(chave VARCHAR(255), teto INT)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    RETURN CONV(SUBSTR(MD5(chave), 1, 8), 16, 10) % teto;
END$$
DELIMITER ;

-- --- dimensões ---------------------------------------------------------------

INSERT INTO canal (nome, tipo) VALUES
    ('Google Ads',  'busca'),
    ('Meta Ads',    'social'),
    ('YouTube Ads', 'video');

INSERT INTO cliente (nome, segmento, verba_mensal_centavos, entrou_em, ativo) VALUES
    ('Padaria do Zé',        'alimentação', 2000000, DATE '2025-11-03', TRUE),
    ('Ótica Vista Clara',    'varejo',      2500000, DATE '2025-08-18', TRUE),
    ('Studio Pilates Norte', 'saúde',       1200000, DATE '2026-01-12', TRUE),
    ('Advocacia Ramos',      'serviços',    3000000, DATE '2025-06-02', TRUE),
    ('Marcenaria Bonfim',    'indústria',   1200000, DATE '2026-02-24', TRUE),
    ('Escola Mundo Novo',    'educação',    2500000, DATE '2025-09-15', TRUE),
    ('Pet Shop Lupi',        'varejo',       900000, DATE '2026-04-06', TRUE),
    ('Clínica Odonto Sul',   'saúde',       1800000, DATE '2025-07-21', FALSE);

-- (a) O `generate_series(1, 5)` do original vira esta lista fixa. Cinco valores
--     escritos à mão são mais legíveis que uma CTE recursiva, e o teto é
--     conhecido.
INSERT INTO campanha (cliente_id, canal_id, nome, objetivo, inicio, fim)
SELECT
    c.id,
    1 + sorteio(CONCAT('canal', c.id, '-', n.n), 3),
    CONCAT(
        CASE sorteio(CONCAT('nome', c.id, '-', n.n), 6)
            WHEN 0 THEN 'Institucional'
            WHEN 1 THEN 'Promoção sazonal'
            WHEN 2 THEN 'Remarketing'
            WHEN 3 THEN 'Captação — bairro'
            WHEN 4 THEN 'Black Friday'
            ELSE        'Marca'
        END,
        ' ', n.n
    ),
    CASE sorteio(CONCAT('obj', c.id, '-', n.n), 4)
        WHEN 0 THEN 'leads' WHEN 1 THEN 'vendas' WHEN 2 THEN 'trafego'
        ELSE 'reconhecimento'
    END,
    DATE_ADD(DATE '2026-03-01', INTERVAL sorteio(CONCAT('ini', c.id, '-', n.n), 90) DAY),
    -- As campanhas do Pet Shop Lupi terminam em 05/08: é o cenário que a
    -- consulta 09 existe para pegar. Sem ele, aquela consulta devolveria zero
    -- linhas para sempre — provando nada.
    CASE WHEN c.nome = 'Pet Shop Lupi' THEN DATE '2026-08-05' END
FROM cliente c
CROSS JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3
            UNION ALL SELECT 4 UNION ALL SELECT 5) n
WHERE n.n <= 2 + sorteio(CONCAT('qtd', c.id), 4);

-- --- métricas diárias --------------------------------------------------------
-- Uma linha por campanha por dia, do início da campanha até 31/08/2026.
--
-- (a) Aqui a CTE recursiva é inevitável: são ~5.500 dias e não dá para
--     escrevê-los à mão. Ela gera o calendário de cada campanha subindo dia a
--     dia até o fim (ou até 31/08, o que vier antes).

INSERT INTO metrica_diaria (campanha_id, dia, impressoes, cliques, custo_centavos)
WITH RECURSIVE calendario (campanha_id, dia, ultimo) AS (
    SELECT ca.id, ca.inicio, LEAST(COALESCE(ca.fim, DATE '2026-08-31'), DATE '2026-08-31')
    FROM campanha ca
    WHERE ca.inicio <= LEAST(COALESCE(ca.fim, DATE '2026-08-31'), DATE '2026-08-31')
    UNION ALL
    SELECT c.campanha_id, DATE_ADD(c.dia, INTERVAL 1 DAY), c.ultimo
    FROM calendario c
    WHERE c.dia < c.ultimo
)
SELECT
    d.campanha_id,
    d.dia,
    m.impressoes,
    k.cliques,
    -- CPC entre R$ 0,40 e R$ 3,40, aplicado sobre os cliques.
    k.cliques * (40 + sorteio(CONCAT('cpc', d.campanha_id, d.dia), 300))
FROM calendario d
-- (b) `DIV`, não `/`: o original faz divisão inteira, e no MySQL `/` devolveria
--     decimal — mudando silenciosamente o número de cliques de toda a base.
JOIN LATERAL (
    SELECT 400 + sorteio(CONCAT('imp', d.campanha_id, d.dia), 3600) AS impressoes
) m ON TRUE
JOIN LATERAL (
    -- CTR entre 1% e 6%, estável por campanha e dia.
    SELECT GREATEST(1, m.impressoes * (10 + sorteio(CONCAT('ctr', d.campanha_id, d.dia), 50)) DIV 1000)
           AS cliques
) k ON TRUE;

-- --- leads -------------------------------------------------------------------
-- Nasce de um clique: a data do lead é sempre um dia em que a campanha rodou.

INSERT INTO `lead` (campanha_id, criado_em, status)
SELECT
    m.campanha_id,
    m.dia,
    CASE sorteio(CONCAT('st', m.campanha_id, m.dia, g.g), 10)
        WHEN 0 THEN 'novo'      WHEN 1 THEN 'novo'
        WHEN 2 THEN 'contatado' WHEN 3 THEN 'contatado'
        WHEN 4 THEN 'qualificado'
        WHEN 5 THEN 'perdido'   WHEN 6 THEN 'perdido'
        ELSE 'ganho'
    END
FROM metrica_diaria m
JOIN campanha ca ON ca.id = m.campanha_id
CROSS JOIN (SELECT 1 AS g UNION ALL SELECT 2 UNION ALL SELECT 3) g
-- Campanha de reconhecimento gasta igual e quase não converte — é a linha que
-- a consulta 06 precisa encontrar. Sem esse caso na semente, aquela consulta
-- nunca devolveria nada e ninguém saberia se ela funciona.
WHERE g.g <= sorteio(CONCAT('lead', m.campanha_id, m.dia), 100) * m.cliques
             DIV CASE WHEN ca.objetivo = 'reconhecimento' THEN 90000 ELSE 1800 END;

-- --- vendas ------------------------------------------------------------------
-- Só lead 'ganho' vira venda, entre 1 e 30 dias depois de entrar.

INSERT INTO venda (lead_id, fechada_em, valor_centavos)
SELECT
    l.id,
    DATE_ADD(l.criado_em, INTERVAL (sorteio(CONCAT('dias', l.id), 30) + 1) DAY),
    25000 + sorteio(CONCAT('valor', l.id), 475000)
FROM `lead` l
WHERE l.status = 'ganho';

DROP FUNCTION sorteio;
