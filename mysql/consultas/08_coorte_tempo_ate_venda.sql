-- PERGUNTA: quanto tempo um lead demora para virar venda, e isso está
-- melhorando?
--
-- Porte para MySQL 8 — **e esta é a consulta que o MySQL não sabe escrever.**
--
-- Coorte por mês de entrada. A leitura importa: um mês recente parece pior
-- porque os leads dele ainda não tiveram tempo de fechar — é viés de maturação,
-- não queda de desempenho. A mediana é o que separa as duas leituras.
--
-- ## As duas diferenças de dialeto, e a segunda é séria
--
-- **`data - data` não dá dias no MySQL.** No Postgres a subtração de datas
-- devolve inteiro de dias; no MySQL ela converte para número (`20260831`) e
-- subtrai — devolvendo um valor que parece um número de dias e não é. Não dá
-- erro. Vai `DATEDIFF`.
--
-- **`PERCENTILE_CONT` não existe no MySQL 8**, em nenhuma forma. Não é sintaxe
-- diferente: a função de percentil ordenado não foi implementada. Trocar por
-- `AVG` seria o caminho fácil e destruiria o argumento da consulta — uma única
-- venda que demorou seis meses puxa a média inteira, e é exatamente por isso
-- que aqui é mediana.
--
-- A reconstrução usa funções de janela: numera as vendas de cada coorte por
-- duração, conta quantas são, e fica com a do meio — ou com a **média das duas
-- do meio** quando a contagem é par. Essa média não é aproximação: é o que
-- `PERCENTILE_CONT(0.5)` faz por definição, porque interpolar linearmente na
-- posição 0,5 entre os dois valores centrais dá exatamente a média deles.
--
-- E um detalhe que muda o número: `PERCENTILE_CONT` **ignora NULL**. O LEFT
-- JOIN traz lead sem venda, e esses não podem entrar na mediana — daí o
-- `WHERE v.id IS NOT NULL` na CTE. Esquecê-lo faria a mediana de "dias até
-- fechar" incluir quem nunca fechou.

USE trafego_mysql;

WITH base AS (
    SELECT
        DATE_FORMAT(l.criado_em, '%Y-%m')        AS coorte,
        v.id                                     AS venda_id,
        DATEDIFF(v.fechada_em, l.criado_em)      AS dias,
        v.valor_centavos
    FROM `lead` l
    LEFT JOIN venda v ON v.lead_id = l.id
),
resumo AS (
    SELECT
        coorte,
        COUNT(*)                                  AS leads,
        COUNT(venda_id)                           AS viraram_venda,
        ROUND(100.0 * COUNT(venda_id) / COUNT(*), 1) AS conversao_pct,
        MAX(dias)                                 AS dias_ate_fechar_maximo,
        COALESCE(SUM(valor_centavos), 0)          AS receita_centavos
    FROM base
    GROUP BY coorte
),
ordenado AS (
    SELECT
        coorte,
        dias,
        ROW_NUMBER() OVER (PARTITION BY coorte ORDER BY dias) AS posicao,
        COUNT(*)     OVER (PARTITION BY coorte)               AS quantas
    FROM base
    WHERE venda_id IS NOT NULL
),
mediana AS (
    SELECT coorte, AVG(dias) AS dias_ate_fechar_mediana
    FROM ordenado
    -- As duas posições centrais. Quando `quantas` é ímpar as duas coincidem e
    -- a média é o próprio valor do meio.
    WHERE posicao IN (FLOOR((quantas + 1) / 2), CEILING((quantas + 1) / 2))
    GROUP BY coorte
)
SELECT
    r.coorte                    AS coorte_de_entrada,
    r.leads,
    r.viraram_venda,
    r.conversao_pct,
    md.dias_ate_fechar_mediana,
    r.dias_ate_fechar_maximo,
    r.receita_centavos
FROM resumo r
LEFT JOIN mediana md ON md.coorte = r.coorte
ORDER BY r.coorte;
