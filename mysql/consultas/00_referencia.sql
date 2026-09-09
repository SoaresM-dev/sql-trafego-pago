-- =============================================================================
-- A data de referência de todas as consultas — porte para MySQL 8.
--
-- **`CURRENT_DATE` não aparece em lugar nenhum deste repositório.** Consulta que
-- depende do dia de hoje devolve resultado diferente amanhã, e aí nenhuma saída
-- pode ser comparada com um arquivo esperado. Aqui a "hoje" é fixa: 31/08/2026,
-- o último dia semeado.
-- =============================================================================

USE trafego_mysql;

CREATE OR REPLACE VIEW hoje AS SELECT DATE '2026-08-31' AS data;
