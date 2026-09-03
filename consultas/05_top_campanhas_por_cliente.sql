-- PERGUNTA: qual é a melhor campanha de CADA cliente?
--
-- "Melhor de cada grupo" é a consulta em que quase todo mundo escorrega: com
-- `GROUP BY` sai o valor máximo, mas não a linha que o produziu — e aí vem a
-- gambiarra de juntar a tabela consigo mesma pelo máximo, que devolve duas
-- linhas quando há empate.
--
-- `ROW_NUMBER() OVER (PARTITION BY ...)` numera as linhas dentro de cada
-- cliente e resolve o empate de forma determinística pelo desempate do
-- ORDER BY. Uma passada, sem self-join.

SET search_path TO trafego;

WITH desempenho AS (
    SELECT
        ca.cliente_id,
        ca.nome AS campanha,
        SUM(m.custo_centavos) AS custo,
        (SELECT COUNT(*) FROM lead l WHERE l.campanha_id = ca.id) AS leads
    FROM campanha ca
    JOIN metrica_diaria m ON m.campanha_id = ca.id
    GROUP BY ca.id, ca.cliente_id, ca.nome
),
classificado AS (
    SELECT
        d.*,
        CASE WHEN d.leads > 0 THEN ROUND(d.custo::numeric / d.leads)::bigint END AS cpl,
        ROW_NUMBER() OVER (
            PARTITION BY d.cliente_id
            -- Menor CPL primeiro; sem lead vai para o fim. O nome entra como
            -- desempate para o resultado não variar entre execuções.
            ORDER BY CASE WHEN d.leads > 0 THEN d.custo::numeric / d.leads END ASC NULLS LAST,
                     d.campanha
        ) AS posicao
    FROM desempenho d
)
SELECT c.nome AS cliente, cl.campanha, cl.custo AS investimento_centavos,
       cl.leads, cl.cpl AS custo_por_lead_centavos
FROM classificado cl
JOIN cliente c ON c.id = cl.cliente_id
WHERE cl.posicao = 1
ORDER BY c.nome;
