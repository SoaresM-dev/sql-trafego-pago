-- PERGUNTA: em que dia da semana o lead sai mais barato?
--
-- Porte para MySQL 8. Responde a uma decisão concreta: se segunda custa 40%
-- menos que domingo, a verba do fim de semana vai para o começo da semana.
--
-- Dialeto: `EXTRACT(isodow FROM x)` não existe no MySQL, e a substituição é
-- onde se erra por um dia sem perceber. As opções:
--
--   `DAYOFWEEK(x)`  — domingo = 1 … sábado = 7   (não é ISO)
--   `WEEKDAY(x)`    — segunda = 0 … domingo = 6  (ISO deslocado de 1)
--
-- Vai `WEEKDAY(x) + 1`, que dá segunda = 1 … domingo = 7, igual ao `isodow`.
-- Escolher `DAYOFWEEK` porque o nome parece mais óbvio publicaria o relatório
-- inteiro com os rótulos deslocados — e o número continuaria certo, o que é
-- pior: só a etiqueta estaria errada, e ninguém confere etiqueta.

USE trafego_mysql;

WITH custo_por_dia AS (
    SELECT dia, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY dia
),
leads_por_dia AS (
    SELECT criado_em AS dia, COUNT(*) AS leads
    FROM `lead`
    GROUP BY criado_em
)
SELECT
    WEEKDAY(c.dia) + 1 AS dia_iso,
    CASE WEEKDAY(c.dia) + 1
        WHEN 1 THEN 'segunda' WHEN 2 THEN 'terça'  WHEN 3 THEN 'quarta'
        WHEN 4 THEN 'quinta'  WHEN 5 THEN 'sexta'  WHEN 6 THEN 'sábado'
        ELSE 'domingo'
    END                       AS dia_da_semana,
    SUM(c.custo)              AS investimento_centavos,
    COALESCE(SUM(l.leads), 0) AS leads,
    CASE WHEN COALESCE(SUM(l.leads), 0) > 0
         THEN CAST(ROUND(SUM(c.custo) / SUM(l.leads)) AS SIGNED)
    END                       AS custo_por_lead_centavos
FROM custo_por_dia c
LEFT JOIN leads_por_dia l ON l.dia = c.dia
GROUP BY dia_iso, dia_da_semana
ORDER BY (custo_por_lead_centavos IS NULL), custo_por_lead_centavos;
