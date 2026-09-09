-- PERGUNTA: o custo por lead está subindo ou caindo mês a mês?
--
-- Porte para MySQL 8. Número solto não diz nada; a variação diz. `LAG` traz o
-- mês anterior para a mesma linha, sem subconsulta correlacionada — e o MySQL 8
-- tem funções de janela, então esta parte atravessa sem mudança.
--
-- Dialeto: `date_trunc('month', x)` não existe. `DATE_FORMAT(x, '%Y-%m-01')`
-- produz o primeiro dia do mês, mas devolve **texto** — e texto ordena como
-- texto. Aqui dá no mesmo porque 'YYYY-MM-DD' ordena igual à data, mas contar
-- com isso é a maneira clássica de errar em fevereiro. O `DATE(...)` externo
-- devolve o tipo certo e a ordenação deixa de ser coincidência.

USE trafego_mysql;

WITH investimento AS (
    SELECT DATE(DATE_FORMAT(dia, '%Y-%m-01')) AS mes, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY mes
),
leads AS (
    SELECT DATE(DATE_FORMAT(criado_em, '%Y-%m-01')) AS mes, COUNT(*) AS total
    FROM `lead`
    GROUP BY mes
),
mensal AS (
    SELECT
        i.mes,
        i.custo,
        COALESCE(l.total, 0) AS leads,
        CASE WHEN COALESCE(l.total, 0) > 0
             THEN CAST(ROUND(i.custo / l.total) AS SIGNED)
        END AS cpl
    FROM investimento i
    LEFT JOIN leads l ON l.mes = i.mes
)
SELECT
    DATE_FORMAT(mes, '%Y-%m')    AS mes,
    custo                        AS investimento_centavos,
    leads,
    cpl                          AS custo_por_lead_centavos,
    LAG(cpl) OVER (ORDER BY mes) AS cpl_mes_anterior,
    ROUND(
        100.0 * (cpl - LAG(cpl) OVER (ORDER BY mes))
        / NULLIF(LAG(cpl) OVER (ORDER BY mes), 0), 1
    )                            AS variacao_percentual
FROM mensal
ORDER BY mes;
