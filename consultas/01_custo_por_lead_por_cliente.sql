-- PERGUNTA: quanto me custou cada lead, por cliente, nos últimos 30 dias?
--
-- É a pergunta que o cliente faz toda reunião. Duas armadilhas moram aqui:
--
-- 1. **Investimento e leads não podem entrar no mesmo join.** Juntar
--    metrica_diaria com lead multiplica o custo de cada dia pelo número de
--    leads daquele dia. Por isso cada um é agregado no seu próprio CTE e só
--    depois os dois se encontram, já no grão de cliente.
-- 2. **Cliente sem lead tem CPL desconhecido, não zero.** NULL diz "ainda não
--    dá para saber"; R$ 0,00 leria como "leads de graça", que é exatamente a
--    leitura errada para quem decide onde pôr verba.

SET search_path TO trafego;

WITH janela AS (
    SELECT data - 29 AS de, data AS ate FROM hoje
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
    FROM lead l
    JOIN campanha ca ON ca.id = l.campanha_id
    CROSS JOIN janela j
    WHERE l.criado_em BETWEEN j.de AND j.ate
    GROUP BY ca.cliente_id
)
SELECT
    c.nome                                    AS cliente,
    COALESCE(i.custo, 0)                      AS investimento_centavos,
    COALESCE(le.total, 0)                     AS leads,
    CASE WHEN COALESCE(le.total, 0) > 0
         THEN ROUND(i.custo::numeric / le.total)::bigint
    END                                       AS custo_por_lead_centavos
FROM cliente c
LEFT JOIN investimento i  ON i.cliente_id = c.id
LEFT JOIN leads        le ON le.cliente_id = c.id
ORDER BY custo_por_lead_centavos NULLS LAST, c.nome;
