-- PERGUNTA: quanto me custou cada lead, por cliente, nos últimos 30 dias?
--
-- Porte para MySQL 8. As duas armadilhas do original continuam valendo:
--
-- 1. **Investimento e leads não podem entrar no mesmo join.** Juntar
--    metrica_diaria com lead multiplica o custo de cada dia pelo número de
--    leads daquele dia. Cada um é agregado no seu próprio CTE.
-- 2. **Cliente sem lead tem CPL desconhecido, não zero.** NULL diz "ainda não
--    dá para saber"; R$ 0,00 leria como "leads de graça".
--
-- Dialeto: `data - 29` não subtrai dias no MySQL (soma ao número serial), e
-- `NULLS LAST` não existe — vira `(x IS NULL), x`, que é como se escreve a
-- mesma intenção sem a cláusula.

USE trafego_mysql;

WITH janela AS (
    SELECT DATE_SUB(data, INTERVAL 29 DAY) AS de, data AS ate FROM hoje
),
investimento AS (
    SELECT ca.cliente_id, SUM(m.custo_centavos) AS custo
    FROM metrica_diaria m
    JOIN campanha ca ON ca.id = m.campanha_id
    CROSS JOIN janela j
    WHERE m.dia BETWEEN j.de AND j.ate
    GROUP BY ca.cliente_id
),
leads AS (
    SELECT ca.cliente_id, COUNT(*) AS total
    FROM `lead` l
    JOIN campanha ca ON ca.id = l.campanha_id
    CROSS JOIN janela j
    WHERE l.criado_em BETWEEN j.de AND j.ate
    GROUP BY ca.cliente_id
)
SELECT
    c.nome                AS cliente,
    COALESCE(i.custo, 0)  AS investimento_centavos,
    COALESCE(le.total, 0) AS leads,
    CASE WHEN COALESCE(le.total, 0) > 0
         THEN CAST(ROUND(i.custo / le.total) AS SIGNED)
    END                   AS custo_por_lead_centavos
FROM cliente c
LEFT JOIN investimento i  ON i.cliente_id = c.id
LEFT JOIN leads        le ON le.cliente_id = c.id
ORDER BY (custo_por_lead_centavos IS NULL), custo_por_lead_centavos, c.nome;
