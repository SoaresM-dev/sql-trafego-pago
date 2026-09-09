-- PERGUNTA: quais campanhas devolvem mais do que custam?
--
-- Porte para MySQL 8. ROAS = receita / investimento; abaixo de 1, a campanha
-- queima dinheiro.
--
-- A unicidade de `venda.lead_id` continua sendo o que torna a conta confiável:
-- sem ela, um lead com duas vendas contaria a receita duas vezes e o ROAS
-- ficaria inflado exatamente nas campanhas que mais vendem — o erro mais caro
-- possível neste modelo.
--
-- Dialeto: `NULLS LAST` não existe. E note que aqui ele seria quase
-- desnecessário — o MySQL já põe NULL por último em `ORDER BY ... DESC` —, mas
-- "quase" é a palavra que produz bug: a mesma cláusula em ASC inverteria. O
-- `(x IS NULL)` explícito diz a intenção nos dois sentidos.

USE trafego_mysql;

WITH investimento AS (
    SELECT campanha_id, SUM(custo_centavos) AS custo
    FROM metrica_diaria
    GROUP BY campanha_id
),
receita AS (
    SELECT l.campanha_id, SUM(v.valor_centavos) AS receita, COUNT(*) AS vendas
    FROM venda v
    JOIN `lead` l ON l.id = v.lead_id
    GROUP BY l.campanha_id
)
SELECT
    c.nome                 AS cliente,
    ca.nome                AS campanha,
    cn.nome                AS canal,
    i.custo                AS investimento_centavos,
    COALESCE(r.receita, 0) AS receita_centavos,
    COALESCE(r.vendas, 0)  AS vendas,
    ROUND(COALESCE(r.receita, 0) / NULLIF(i.custo, 0), 2) AS roas,
    CASE
        WHEN COALESCE(r.receita, 0) >= i.custo * 3 THEN 'escalar'
        WHEN COALESCE(r.receita, 0) >= i.custo     THEN 'manter'
        ELSE                                            'revisar'
    END                    AS recomendacao
FROM campanha ca
JOIN cliente c      ON c.id = ca.cliente_id
JOIN canal cn       ON cn.id = ca.canal_id
JOIN investimento i ON i.campanha_id = ca.id
LEFT JOIN receita r ON r.campanha_id = ca.id
ORDER BY (roas IS NULL), roas DESC, ca.nome
LIMIT 10;
