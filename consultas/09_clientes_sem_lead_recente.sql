-- PERGUNTA: que cliente ativo parou de receber lead?
--
-- É o alerta operacional do dia a dia: campanha pausada por cartão recusado,
-- formulário quebrado depois de um deploy, verba que acabou. Descobrir isso
-- pelo cliente reclamando é caro.
--
-- `NOT EXISTS` e não `NOT IN`: se a subconsulta devolver um único NULL, o
-- `NOT IN` devolve zero linhas — silenciosamente, sem erro. É o defeito mais
-- traiçoeiro do SQL, e `NOT EXISTS` simplesmente não tem esse comportamento.
-- Como bônus, o Postgres o transforma em anti-join, que costuma ser mais
-- rápido.

SET search_path TO trafego;

SELECT
    c.nome                        AS cliente,
    c.segmento,
    c.verba_mensal_centavos,
    (SELECT MAX(l.criado_em)
       FROM lead l JOIN campanha ca ON ca.id = l.campanha_id
      WHERE ca.cliente_id = c.id) AS ultimo_lead,
    (SELECT h.data FROM hoje h)
      - (SELECT MAX(l.criado_em)
           FROM lead l JOIN campanha ca ON ca.id = l.campanha_id
          WHERE ca.cliente_id = c.id) AS dias_sem_lead
FROM cliente c
WHERE c.ativo
  AND NOT EXISTS (
      SELECT 1
      FROM lead l
      JOIN campanha ca ON ca.id = l.campanha_id
      CROSS JOIN hoje h
      WHERE ca.cliente_id = c.id
        AND l.criado_em > h.data - 14
  )
ORDER BY dias_sem_lead DESC NULLS FIRST, c.nome;
