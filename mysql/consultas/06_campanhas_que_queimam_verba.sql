-- PERGUNTA: onde estou gastando sem retorno?
--
-- Porte para MySQL 8. O ranking invertido: entra na lista quem gastou mais de
-- R$ 500 E produziu menos de dez leads. O `HAVING` filtra DEPOIS do
-- agrupamento, que é a única forma de condicionar sobre um agregado.
--
-- O piso de R$ 500 existe para não acusar campanha que acabou de subir: sem
-- ele, toda campanha nova aparece no topo da lista de piores.
--
-- Dialeto — e aqui mora a diferença mais perigosa do porte inteiro, porque ela
-- **não dá erro**: o MySQL permite agregado no `WHERE`? Não. Mas ele permitia,
-- até o 5.7, aceitar `GROUP BY` incompleto e devolver uma linha arbitrária das
-- colunas de fora — o "loose GROUP BY", que o Postgres sempre reprovou. Desde
-- o 5.7 o `ONLY_FULL_GROUP_BY` vem ligado por padrão e os dois passaram a
-- concordar. Em servidor antigo, ou com o modo desligado à mão, esta mesma
-- consulta rodaria e devolveria número errado em silêncio.

USE trafego_mysql;

SELECT
    c.nome                AS cliente,
    ca.nome               AS campanha,
    cn.nome               AS canal,
    ca.objetivo,
    SUM(m.custo_centavos) AS investimento_centavos,
    COUNT(DISTINCT l.id)  AS leads,
    MIN(m.dia)            AS primeiro_dia,
    MAX(m.dia)            AS ultimo_dia
FROM campanha ca
JOIN cliente c        ON c.id = ca.cliente_id
JOIN canal cn         ON cn.id = ca.canal_id
JOIN metrica_diaria m ON m.campanha_id = ca.id
LEFT JOIN `lead` l    ON l.campanha_id = ca.id
GROUP BY c.nome, ca.nome, cn.nome, ca.objetivo
HAVING SUM(m.custo_centavos) > 50000
   AND COUNT(DISTINCT l.id) < 10
ORDER BY investimento_centavos DESC;
