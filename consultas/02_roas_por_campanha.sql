-- PERGUNTA: quais campanhas devolvem mais do que custam?
--
-- ROAS = receita / investimento. Abaixo de 1, a campanha queima dinheiro.
--
-- A unicidade de `venda.lead_id` é o que torna esta conta confiável: sem ela,
-- um lead com duas vendas contaria a receita duas vezes e o ROAS ficaria
-- inflado exatamente nas campanhas que mais vendem — o erro mais caro possível
-- neste modelo, porque empurra verba para o lugar errado com um número que
-- parece ótimo.

SET search_path TO trafego;

WITH investimento AS (
    SELECT campanha_id, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY campanha_id
),
receita AS (
    SELECT l.campanha_id, SUM(v.valor_centavos) AS receita, COUNT(*) AS vendas
    FROM venda v
    JOIN lead l ON l.id = v.lead_id
    GROUP BY l.campanha_id
)
SELECT
    c.nome                                AS cliente,
    ca.nome                               AS campanha,
    cn.nome                               AS canal,
    i.custo                               AS investimento_centavos,
    COALESCE(r.receita, 0)                AS receita_centavos,
    COALESCE(r.vendas, 0)                 AS vendas,
    ROUND(COALESCE(r.receita, 0)::numeric / NULLIF(i.custo, 0), 2) AS roas,
    CASE
        WHEN COALESCE(r.receita, 0) >= i.custo * 3 THEN 'escalar'
        WHEN COALESCE(r.receita, 0) >= i.custo     THEN 'manter'
        ELSE                                            'revisar'
    END                                   AS recomendacao
FROM campanha ca
JOIN cliente c   ON c.id = ca.cliente_id
JOIN canal cn    ON cn.id = ca.canal_id
JOIN investimento i ON i.campanha_id = ca.id
LEFT JOIN receita r ON r.campanha_id = ca.id
ORDER BY roas DESC NULLS LAST, ca.nome
LIMIT 10;
