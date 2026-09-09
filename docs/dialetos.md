# O mesmo modelo em Postgres e em MySQL

As dez consultas de `consultas/` existem também em `mysql/consultas/`, e a CI
roda as duas versões contra um servidor de verdade a cada push.

Este documento é o motivo de o porte existir: **quase nada disso é "sintaxe
diferente".** Cada linha abaixo é uma decisão de projeto que o dialeto obrigou,
e três delas mudariam o número no relatório sem dar erro nenhum.

## As três que não dão erro — e por isso são as caras

### 1. `/` entre inteiros não trunca no MySQL

```sql
-- Postgres: divisão inteira, resultado 3
SELECT 7 / 2;        -- 3

-- MySQL: resultado 3.5000
SELECT 7 / 2;        -- 3.5000
SELECT 7 DIV 2;      -- 3
```

A semente calcula cliques como `impressoes * ctr / 1000`. Traduzida com `/`, a
base inteira muda de volume — mais cliques, mais leads, todo CPL diferente — e
**nada reprova**: os números continuam plausíveis. `DIV` é a tradução correta, e
é preciso saber que ela existe antes de precisar dela.

### 2. `data - data` não devolve dias

```sql
-- Postgres: 31 (dias)
SELECT DATE '2026-08-31' - DATE '2026-07-31';

-- MySQL: 100 (subtração de 20260831 - 20260731)
SELECT DATE '2026-08-31' - DATE '2026-07-31';
SELECT DATEDIFF('2026-08-31', '2026-07-31');   -- 31
```

Cem em vez de trinta e um. A consulta 08 mede dias até a venda fechar: sem
`DATEDIFF`, ela devolveria um número que parece dia e não é — e um relatório
dizendo "o lead fecha em 100 dias" é aceito sem espanto.

### 3. `EXTRACT(isodow)` não existe, e o substituto óbvio é o errado

| | segunda | … | domingo |
|---|---|---|---|
| `EXTRACT(isodow)` (Postgres) | 1 | … | 7 |
| `DAYOFWEEK()` (MySQL) | 2 | … | 1 |
| `WEEKDAY()` (MySQL) | 0 | … | 6 |

`DAYOFWEEK` é o nome que a mão escreve sozinha, e ele começa no domingo. A
tradução certa é `WEEKDAY(x) + 1`. Com a errada, a consulta 07 publica o
relatório com **os rótulos deslocados em um dia** — os números certos, embaixo
dos nomes errados. Ninguém confere etiqueta.

## As que dão erro, e por isso são baratas

| Postgres | MySQL 8 | Nota |
|---|---|---|
| `SET search_path TO trafego` | `USE trafego_mysql` | MySQL não tem esquema dentro de banco; `SCHEMA` é sinônimo de `DATABASE` |
| `GENERATED ALWAYS AS IDENTITY` | `AUTO_INCREMENT` | perde a garantia de que ninguém escreve na coluna |
| `text` com `UNIQUE` | `VARCHAR(n)` | índice de TEXT exige prefixo |
| `a \|\| b` | `CONCAT(a, b)` | `\|\|` é OR no MySQL |
| `data + 30` | `DATE_ADD(data, INTERVAL 30 DAY)` | |
| `date_trunc('month', x)` | `DATE(DATE_FORMAT(x, '%Y-%m-01'))` | o `DATE()` externo evita ordenar texto |
| `to_char(x, 'YYYY-MM')` | `DATE_FORMAT(x, '%Y-%m')` | |
| `generate_series(...)` | CTE recursiva | com `cte_max_recursion_depth` elevado |
| `x::numeric`, `x::bigint` | `CAST(x AS DECIMAL)`, `CAST(x AS SIGNED)` | |
| `ORDER BY x NULLS LAST` | `ORDER BY (x IS NULL), x` | ver abaixo |
| `agg(...) FILTER (WHERE c)` | `agg(CASE WHEN c THEN ... END)` | funciona porque agregado ignora NULL |
| `lead` | `` `lead` `` | palavra reservada no MySQL 8: é a função de janela `LEAD()` |

### Sobre `NULLS LAST`

O MySQL põe NULL por último em `DESC` e primeiro em `ASC`, então metade das
traduções "funciona sem fazer nada". É armadilha: a mesma cláusula copiada para
o outro sentido inverte em silêncio. `(x IS NULL)` como primeira chave de
ordenação diz a intenção nos dois casos, e custa nada.

Na consulta 09 isso não é estética. Cliente que **nunca** recebeu lead tem
`dias_sem_lead` NULL e é o caso mais urgente da lista — mandá-lo para o fim
esconderia justamente a pior linha do relatório.

## A que o MySQL não sabe escrever

**`PERCENTILE_CONT` não existe no MySQL 8**, em nenhuma forma. Não é sintaxe
diferente: a função de percentil ordenado não foi implementada.

A consulta 08 usa mediana e não média de propósito — uma única venda que
demorou seis meses puxa a média inteira e some com a informação. Trocar por
`AVG` no porte seria o caminho fácil e destruiria o argumento da consulta.

A reconstrução, em `mysql/consultas/08_coorte_tempo_ate_venda.sql`, usa funções
de janela: numera as vendas de cada coorte por duração, conta quantas são, e
fica com a do meio — ou com a **média das duas do meio** quando a contagem é
par.

```sql
ROW_NUMBER() OVER (PARTITION BY coorte ORDER BY dias) AS posicao,
COUNT(*)     OVER (PARTITION BY coorte)              AS quantas
...
WHERE posicao IN (FLOOR((quantas + 1) / 2), CEILING((quantas + 1) / 2))
```

Essa média não é aproximação: é o que `PERCENTILE_CONT(0.5)` faz por definição,
porque interpolar linearmente na posição 0,5 entre os dois valores centrais dá
exatamente a média deles.

E um detalhe que muda o número: **`PERCENTILE_CONT` ignora NULL.** O `LEFT JOIN`
traz lead sem venda, e esses não podem entrar na mediana — daí o
`WHERE venda_id IS NOT NULL`. Esquecê-lo faria a mediana de "dias até fechar"
incluir quem nunca fechou.

## Por que as saídas esperadas são separadas

`esperado/` é do Postgres; `esperado-mysql/` é do MySQL. Elas **não são iguais**,
e isso é decisão, não desleixo:

**A ordenação de texto difere.** A collation `utf8mb4_0900_ai_ci` do MySQL é
acento-insensível; a do Postgres depende do locale do servidor. "Ótica Vista
Clara" cai em posições diferentes. Forçar identidade exigiria ordenar por uma
coluna artificial nos dois lados — mutilar as duas consultas para esconder uma
diferença real.

**As duas sementes não geram a mesma base.** O sorteio determinístico converte
o MD5 da chave em inteiro. O Postgres passa por `::bit(32)::bigint`, que
interpreta o hash como **inteiro com sinal**; `CONV(...,16,10)` do MySQL devolve
sem sinal. Mantive o sem sinal no porte — negativo ali só produziria id inválido
—, e a consequência é que os volumes das duas bases divergem.

O que a CI garante, então, não é "os dois bancos dão a mesma resposta". É:
**cada dialeto roda, e é reprodutível.** Uma consulta que mudar de resultado sem
que alguém tenha mudado de ideia reprova no seu próprio job.

## Uma diferença a favor do MySQL

O InnoDB **cria índice de chave estrangeira sozinho** — ele exige um índice na
coluna que referencia e o cria se não existir. No Postgres só a chave primária
ganha índice automático, e esquecer a estrangeira é a causa mais comum de join
lento.

Por isso `mysql/02_indices.sql` tem dois dos cinco índices comentados em vez de
criados: eles seriam redundantes. Ficaram comentados, e não apagados, para a
lista continuar legível ao lado da do Postgres.
