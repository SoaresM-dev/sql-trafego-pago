-- PERGUNTA: o custo por lead está subindo ou caindo mês a mês?
--
-- Número solto não diz nada; a variação diz. `LAG` traz o mês anterior para a
-- mesma linha, e é o que transforma uma tabela de valores numa tabela de
-- tendência — sem precisar de subconsulta correlacionada, que faria uma
-- varredura por linha.

SET search_path TO trafego;

WITH investimento AS (
    SELECT date_trunc('month', dia)::date AS mes, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY 1
),
leads AS (
    SELECT date_trunc('month', criado_em)::date AS mes, COUNT(*) AS total
    FROM lead
    GROUP BY 1
),
mensal AS (
    SELECT
        i.mes,
        i.custo,
        COALESCE(l.total, 0) AS leads,
        CASE WHEN COALESCE(l.total, 0) > 0
             THEN ROUND(i.custo::numeric / l.total)::bigint
        END AS cpl
    FROM investimento i
    LEFT JOIN leads l ON l.mes = i.mes
)
SELECT
    to_char(mes, 'YYYY-MM')      AS mes,
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
