-- =============================================================================
-- Índices — porte para MySQL 8.
--
-- Mesmos cinco do Postgres, com uma diferença de fundo que vale saber e que
-- muda o raciocínio de quem otimiza:
--
-- **O MySQL cria índice de chave estrangeira sozinho.** O InnoDB exige um
-- índice na coluna que referencia, e o cria se ele não existir. No Postgres
-- só a chave primária ganha índice automático, e esquecer a estrangeira é a
-- causa mais comum de join lento.
--
-- Ou seja: `ix_lead_campanha` e `ix_campanha_cliente` seriam redundantes aqui —
-- o InnoDB já criou equivalentes ao aplicar as FKs de `01_esquema.sql`. Estão
-- comentados em vez de apagados, porque a lista precisa continuar legível ao
-- lado da do Postgres.
-- =============================================================================

USE trafego_mysql;

-- Consultas 01, 03, 07 e 10 filtram métricas por intervalo de datas.
CREATE INDEX ix_metrica_dia ON metrica_diaria (dia);

-- Consultas 01, 02, 04 e 08 partem do lead e sobem para a campanha.
-- Desnecessário no InnoDB: a FK de `lead.campanha_id` já criou o índice.
-- CREATE INDEX ix_lead_campanha ON `lead` (campanha_id);

-- Consultas 09 e 08 filtram por data de criação do lead.
CREATE INDEX ix_lead_criado_em ON `lead` (criado_em);

-- Consulta 08 filtra por data de fechamento da venda.
CREATE INDEX ix_venda_fechada_em ON venda (fechada_em);

-- Consultas 05 e 06 agrupam campanhas por cliente.
-- Desnecessário no InnoDB: a FK de `campanha.cliente_id` já criou o índice.
-- CREATE INDEX ix_campanha_cliente ON campanha (cliente_id);
