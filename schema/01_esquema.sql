-- =============================================================================
-- Esquema: métricas de tráfego pago
--
-- Modelagem em estrela enxuta. As dimensões (cliente, canal, campanha) mudam
-- devagar; os fatos (metrica_diaria, lead, venda) crescem todo dia. Separar os
-- dois é o que permite responder "quanto custou cada lead em agosto" sem varrer
-- a base inteira.
--
-- **Dinheiro em centavos, sempre inteiro.** `float` erra por arredondamento
-- binário, e relatório de investimento que fecha com um centavo de diferença é
-- relatório em que ninguém confia. `numeric` resolveria o arredondamento, mas
-- custa mais em agregação — e como nenhum valor aqui tem fração de centavo,
-- inteiro é a escolha certa e mais rápida.
-- =============================================================================

DROP SCHEMA IF EXISTS trafego CASCADE;
CREATE SCHEMA trafego;
SET search_path TO trafego;

-- --- dimensões ---------------------------------------------------------------

CREATE TABLE cliente (
    id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome          text        NOT NULL UNIQUE,
    segmento      text        NOT NULL,
    -- Quanto o cliente autoriza gastar por mês. É contra isto que o alerta de
    -- estouro de verba compara.
    verba_mensal_centavos integer NOT NULL CHECK (verba_mensal_centavos >= 0),
    entrou_em     date        NOT NULL,
    ativo         boolean     NOT NULL DEFAULT true
);

CREATE TABLE canal (
    id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome    text NOT NULL UNIQUE,
    -- 'busca' e 'social' se comportam de forma diferente: busca capta demanda
    -- que já existe, social cria demanda. Misturar os dois num CPL médio
    -- esconde exatamente a informação que decide onde pôr verba.
    tipo    text NOT NULL CHECK (tipo IN ('busca', 'social', 'video'))
);

CREATE TABLE campanha (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id  integer NOT NULL REFERENCES cliente(id) ON DELETE CASCADE,
    canal_id    integer NOT NULL REFERENCES canal(id),
    nome        text    NOT NULL,
    objetivo    text    NOT NULL CHECK (objetivo IN ('leads', 'vendas', 'trafego', 'reconhecimento')),
    inicio      date    NOT NULL,
    fim         date,
    -- Uma campanha não pode terminar antes de começar. Regra no banco e não na
    -- aplicação: quem garante invariante de dado é quem guarda o dado.
    CONSTRAINT periodo_valido CHECK (fim IS NULL OR fim >= inicio),
    CONSTRAINT nome_unico_por_cliente UNIQUE (cliente_id, nome)
);

-- --- fatos -------------------------------------------------------------------

-- Grão: uma linha por campanha por dia. É o grão em que as plataformas
-- entregam o dado, e escolher um grão mais fino do que a fonte oferece só
-- inventa precisão que não existe.
CREATE TABLE metrica_diaria (
    campanha_id   integer NOT NULL REFERENCES campanha(id) ON DELETE CASCADE,
    dia           date    NOT NULL,
    impressoes    integer NOT NULL CHECK (impressoes >= 0),
    cliques       integer NOT NULL CHECK (cliques >= 0),
    custo_centavos integer NOT NULL CHECK (custo_centavos >= 0),
    -- Chave composta e não uma coluna `id`: a linha JÁ é identificada por
    -- campanha e dia, e uma chave sintética aqui só abriria espaço para a
    -- mesma campanha ter dois registros do mesmo dia.
    PRIMARY KEY (campanha_id, dia),
    -- Clique é subconjunto de impressão. Sem esta trava, um erro de importação
    -- produz CTR acima de 100% e ninguém percebe até o relatório sair.
    CONSTRAINT cliques_nao_passam_de_impressoes CHECK (cliques <= impressoes)
);

CREATE TABLE lead (
    id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campanha_id  integer NOT NULL REFERENCES campanha(id) ON DELETE CASCADE,
    criado_em    date    NOT NULL,
    status       text    NOT NULL DEFAULT 'novo'
                 CHECK (status IN ('novo', 'contatado', 'qualificado', 'ganho', 'perdido'))
);

CREATE TABLE venda (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Um lead vira no máximo uma venda: a unicidade impede que a receita seja
    -- contada duas vezes num join, que é o erro mais caro deste modelo.
    lead_id    integer NOT NULL UNIQUE REFERENCES lead(id) ON DELETE CASCADE,
    fechada_em date    NOT NULL,
    valor_centavos integer NOT NULL CHECK (valor_centavos > 0)
);
