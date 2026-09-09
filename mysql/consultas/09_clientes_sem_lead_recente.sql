-- PERGUNTA: que cliente ativo parou de receber lead?
--
-- Porte para MySQL 8. É o alerta operacional do dia a dia: campanha pausada por
-- cartão recusado, formulário quebrado depois de um deploy, verba que acabou.
-- Descobrir isso pelo cliente reclamando é caro.
--
-- `NOT EXISTS` e não `NOT IN`: se a subconsulta devolver um único NULL, o
-- `NOT IN` devolve zero linhas — silenciosamente, sem erro. É o defeito mais
-- traiçoeiro do SQL, e vale igual nos dois bancos. Como bônus, os dois
-- transformam `NOT EXISTS` em anti-join.
--
-- Dialeto: `h.data - 14` e `data - data` não fazem aritmética de dia no MySQL.
-- E `NULLS FIRST` não existe — aqui ele importa de verdade, porque cliente que
-- **nunca** recebeu lead tem `dias_sem_lead` NULL e é o caso mais urgente da
-- lista. Deixá-lo cair para o fim esconderia justamente a pior linha.

USE trafego_mysql;

SELECT
    c.nome                 AS cliente,
    c.segmento,
    c.verba_mensal_centavos,
    (SELECT MAX(l.criado_em)
       FROM `lead` l JOIN campanha ca ON ca.id = l.campanha_id
      WHERE ca.cliente_id = c.id) AS ultimo_lead,
    DATEDIFF(
        (SELECT h.data FROM hoje h),
        (SELECT MAX(l.criado_em)
           FROM `lead` l JOIN campanha ca ON ca.id = l.campanha_id
          WHERE ca.cliente_id = c.id)
    )                      AS dias_sem_lead
FROM cliente c
WHERE c.ativo = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM `lead` l
      JOIN campanha ca ON ca.id = l.campanha_id
      CROSS JOIN hoje h
      WHERE ca.cliente_id = c.id
        AND l.criado_em > DATE_SUB(h.data, INTERVAL 14 DAY)
  )
ORDER BY (dias_sem_lead IS NOT NULL), dias_sem_lead DESC, c.nome;
