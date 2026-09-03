-- PERGUNTA: algum cliente vai estourar a verba do mês, e em que dia?
--
-- O gasto acumulado dia a dia contra o teto contratado. Responder isso no fim
-- do mês não serve para nada — o valor está em ver a linha cruzar o teto no
-- dia 19 e ainda dar tempo de agir.
--
-- `SUM(...) OVER (PARTITION BY ... ORDER BY ...)` calcula o acumulado numa
-- passada só. A alternativa sem janela é uma subconsulta correlacionada que
-- resoma tudo a cada linha: O(n²) contra O(n log n), e a diferença aparece
-- assim que a base cresce.

SET search_path TO trafego;

WITH agosto AS (
    SELECT
        ca.cliente_id,
        m.dia,
        SUM(m.custo_centavos) AS custo_do_dia
    FROM metrica_diaria m
    JOIN campanha ca ON ca.id = m.campanha_id
    CROSS JOIN hoje h
    WHERE m.dia >= date_trunc('month', h.data)::date
      AND m.dia <= h.data
    GROUP BY ca.cliente_id, m.dia
),
acumulado AS (
    SELECT
        a.*,
        SUM(a.custo_do_dia) OVER (
            PARTITION BY a.cliente_id ORDER BY a.dia
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS acumulado_centavos
    FROM agosto a
)
SELECT
    c.nome                                   AS cliente,
    c.verba_mensal_centavos,
    MAX(ac.acumulado_centavos)               AS gasto_no_mes_centavos,
    ROUND(100.0 * MAX(ac.acumulado_centavos) / c.verba_mensal_centavos, 1) AS pct_da_verba,
    -- O primeiro dia em que o acumulado passou do teto, ou NULL se não passou.
    MIN(ac.dia) FILTER (WHERE ac.acumulado_centavos > c.verba_mensal_centavos)
                                             AS estourou_em
FROM acumulado ac
JOIN cliente c ON c.id = ac.cliente_id
GROUP BY c.id, c.nome, c.verba_mensal_centavos
ORDER BY pct_da_verba DESC;
