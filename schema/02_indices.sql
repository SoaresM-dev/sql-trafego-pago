-- =============================================================================
-- Índices — cada um com a consulta que o justifica.
--
-- Índice sem consulta que o use é custo puro: ocupa disco e torna todo INSERT
-- mais lento em troca de nada. Os quatro abaixo existem porque alguma das dez
-- consultas de `consultas/` os percorre, e `docs/desempenho.md` traz o EXPLAIN
-- de antes e depois.
-- =============================================================================

SET search_path TO trafego;

-- Consultas 01, 03, 07 e 10 filtram métricas por intervalo de datas antes de
-- agregar. Sem isto é sequential scan na maior tabela do banco.
CREATE INDEX ix_metrica_dia ON metrica_diaria (dia);

-- Consultas 01, 02, 04 e 08 partem do lead e sobem para a campanha. O índice
-- da chave estrangeira não vem de graça no Postgres — só a chave PRIMÁRIA
-- ganha índice automático, e esquecer isso é a causa mais comum de join lento.
CREATE INDEX ix_lead_campanha ON lead (campanha_id);

-- Consulta 09 (clientes sem lead recente) e a 08 (coorte) filtram por data de
-- criação do lead.
CREATE INDEX ix_lead_criado_em ON lead (criado_em);

-- Consulta 02 (ROAS) junta venda a lead. `lead_id` já é UNIQUE, o que cria o
-- índice — mas a data de fechamento não, e a 08 filtra por ela.
CREATE INDEX ix_venda_fechada_em ON venda (fechada_em);

-- Consultas 05 e 06 agrupam campanhas por cliente.
CREATE INDEX ix_campanha_cliente ON campanha (cliente_id);
