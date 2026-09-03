-- PERGUNTA: em que dia da semana o lead sai mais barato?
--
-- Responde a uma decisão concreta: se segunda custa 40% menos que domingo, a
-- verba do fim de semana vai para o começo da semana.
--
-- `EXTRACT(isodow)` e não `dow`: o ISO começa a semana na segunda (1) e termina
-- no domingo (7), que é como as pessoas leem um relatório no Brasil. O `dow`
-- do Postgres começa no domingo com zero, e é fácil publicar o gráfico com os
-- rótulos deslocados em um dia sem ninguém notar.

SET search_path TO trafego;

WITH custo_por_dia AS (
    SELECT dia, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY dia
),
leads_por_dia AS (
    SELECT criado_em AS dia, COUNT(*) AS leads
    FROM lead
    GROUP BY criado_em
)
SELECT
    EXTRACT(isodow FROM c.dia)::int AS dia_iso,
    CASE EXTRACT(isodow FROM c.dia)::int
        WHEN 1 THEN 'segunda' WHEN 2 THEN 'terça'  WHEN 3 THEN 'quarta'
        WHEN 4 THEN 'quinta'  WHEN 5 THEN 'sexta'  WHEN 6 THEN 'sábado'
        ELSE 'domingo'
    END                              AS dia_da_semana,
    SUM(c.custo)                     AS investimento_centavos,
    COALESCE(SUM(l.leads), 0)        AS leads,
    CASE WHEN COALESCE(SUM(l.leads), 0) > 0
         THEN ROUND(SUM(c.custo)::numeric / SUM(l.leads))::bigint
    END                              AS custo_por_lead_centavos
FROM custo_por_dia c
LEFT JOIN leads_por_dia l ON l.dia = c.dia
GROUP BY 1, 2
ORDER BY custo_por_lead_centavos NULLS LAST;
