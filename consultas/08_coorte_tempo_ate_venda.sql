-- PERGUNTA: quanto tempo um lead demora para virar venda, e isso está
-- melhorando?
--
-- Coorte por mês de entrada. A leitura importa: um mês recente parece pior
-- porque os leads dele ainda não tiveram tempo de fechar — é viés de
-- maturação, não queda de desempenho. A coluna `dias_ate_fechar_mediana` é o
-- que separa as duas leituras.
--
-- `PERCENTILE_CONT` e não `AVG`: uma única venda que demorou seis meses puxa a
-- média inteira e some com a informação. A mediana não se abala com isso.

SET search_path TO trafego;

SELECT
    to_char(date_trunc('month', l.criado_em), 'YYYY-MM')  AS coorte_de_entrada,
    COUNT(*)                                             AS leads,
    COUNT(v.id)                                          AS viraram_venda,
    ROUND(100.0 * COUNT(v.id) / COUNT(*), 1)             AS conversao_pct,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.fechada_em - l.criado_em)
                                                         AS dias_ate_fechar_mediana,
    MAX(v.fechada_em - l.criado_em)                      AS dias_ate_fechar_maximo,
    COALESCE(SUM(v.valor_centavos), 0)                   AS receita_centavos
FROM lead l
LEFT JOIN venda v ON v.lead_id = l.id
GROUP BY 1
ORDER BY 1;
