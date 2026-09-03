-- PERGUNTA: em que etapa cada campanha perde gente?
--
-- Impressão -> clique -> lead -> venda. A etapa com a maior queda é onde o
-- trabalho rende: CTR baixo é problema de criativo, taxa de lead baixa é
-- problema de página, e taxa de venda baixa não é problema de mídia nenhum —
-- é do time comercial. Sem o funil separado, tudo isso vira "a campanha não
-- está performando".

SET search_path TO trafego;

WITH midia AS (
    SELECT campanha_id, SUM(impressoes) AS impressoes, SUM(cliques) AS cliques
    FROM metrica_diaria
    GROUP BY campanha_id
),
leads AS (
    SELECT campanha_id, COUNT(*) AS leads
    FROM lead
    GROUP BY campanha_id
),
vendas AS (
    SELECT l.campanha_id, COUNT(*) AS vendas
    FROM venda v JOIN lead l ON l.id = v.lead_id
    GROUP BY l.campanha_id
)
SELECT
    c.nome                     AS cliente,
    ca.nome                    AS campanha,
    m.impressoes,
    m.cliques,
    COALESCE(le.leads, 0)      AS leads,
    COALESCE(ve.vendas, 0)     AS vendas,
    ROUND(100.0 * m.cliques / NULLIF(m.impressoes, 0), 2)          AS ctr_pct,
    ROUND(100.0 * COALESCE(le.leads, 0) / NULLIF(m.cliques, 0), 2) AS clique_para_lead_pct,
    ROUND(100.0 * COALESCE(ve.vendas, 0) / NULLIF(le.leads, 0), 2) AS lead_para_venda_pct
FROM campanha ca
JOIN cliente c ON c.id = ca.cliente_id
JOIN midia m   ON m.campanha_id = ca.id
LEFT JOIN leads  le ON le.campanha_id = ca.id
LEFT JOIN vendas ve ON ve.campanha_id = ca.id
ORDER BY c.nome, ca.nome
LIMIT 15;
