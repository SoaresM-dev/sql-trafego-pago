-- PERGUNTA: onde estou gastando sem retorno?
--
-- O ranking invertido. Uma campanha entra na lista se gastou mais de R$ 500
-- E produziu menos de dez leads — o `HAVING` filtra DEPOIS do agrupamento, que
-- é a única forma de condicionar sobre um agregado. Tentar isso no `WHERE`
-- é o erro clássico, e o Postgres reprova com "aggregate functions are not
-- allowed in WHERE".
--
-- O piso de R$ 500 existe para não acusar campanha que acabou de subir: sem
-- ele, toda campanha nova aparece no topo da lista de piores.

SET search_path TO trafego;

SELECT
    c.nome                     AS cliente,
    ca.nome                    AS campanha,
    cn.nome                    AS canal,
    ca.objetivo,
    SUM(m.custo_centavos)      AS investimento_centavos,
    COUNT(DISTINCT l.id)       AS leads,
    MIN(m.dia)                 AS primeiro_dia,
    MAX(m.dia)                 AS ultimo_dia
FROM campanha ca
JOIN cliente c        ON c.id = ca.cliente_id
JOIN canal cn         ON cn.id = ca.canal_id
JOIN metrica_diaria m ON m.campanha_id = ca.id
LEFT JOIN lead l      ON l.campanha_id = ca.id
GROUP BY c.nome, ca.nome, cn.nome, ca.objetivo
HAVING SUM(m.custo_centavos) > 50000
   AND COUNT(DISTINCT l.id) < 10
ORDER BY investimento_centavos DESC;
