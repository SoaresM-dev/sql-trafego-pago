-- Bancada: o índice de data vale a pena?
--
-- Regra que este repositório segue: **meça antes de otimizar.** Índice sem
-- medição é palpite, e palpite custa disco e INSERT lento.
--
--     psql -f scripts/bancada_indice.sql
SET search_path TO trafego;

DROP TABLE IF EXISTS metrica_grande;
CREATE TABLE metrica_grande AS
SELECT
    (n % 29) + 1                                  AS campanha_id,
    DATE '2024-01-01' + (n % 900)                 AS dia,
    1000 + (n % 4000)                             AS impressoes,
    30 + (n % 200)                                AS cliques,
    5000 + (n % 90000)                            AS custo_centavos
FROM generate_series(1, 1000000) AS n;

ANALYZE metrica_grande;

\echo '=== SEM ÍNDICE ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON)
SELECT campanha_id, SUM(custo_centavos)
FROM metrica_grande
WHERE dia BETWEEN DATE '2025-06-01' AND DATE '2025-06-30'
GROUP BY campanha_id;

CREATE INDEX ix_grande_dia ON metrica_grande (dia);
ANALYZE metrica_grande;

\echo '=== COM ÍNDICE ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON)
SELECT campanha_id, SUM(custo_centavos)
FROM metrica_grande
WHERE dia BETWEEN DATE '2025-06-01' AND DATE '2025-06-30'
GROUP BY campanha_id;

DROP TABLE metrica_grande;
