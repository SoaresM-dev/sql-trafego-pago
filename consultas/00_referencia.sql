-- =============================================================================
-- A data de referência de todas as consultas.
--
-- **`CURRENT_DATE` não aparece em lugar nenhum deste repositório.** Uma
-- consulta que depende do dia de hoje devolve resultado diferente amanhã, e aí
-- nenhuma saída pode ser comparada com um arquivo esperado — a CI não teria o
-- que verificar. Aqui a "hoje" é fixa: 31/08/2026, o último dia semeado.
--
-- Num sistema em produção, esta view viraria `CURRENT_DATE` e as consultas não
-- mudariam nem uma linha.
-- =============================================================================

SET search_path TO trafego;

CREATE OR REPLACE VIEW hoje AS SELECT DATE '2026-08-31' AS data;
