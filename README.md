# Métricas de tráfego pago — modelagem e consultas em SQL

**Um modelo relacional para a pergunta que todo cliente de agência faz: quanto
me custa cada lead, e de onde ele veio?**

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)
[![PostgreSQL 16](https://img.shields.io/badge/postgres-16-336791)](https://www.postgresql.org/)
[![MySQL 8.4](https://img.shields.io/badge/mysql-8.4-4479a1)](https://www.mysql.com/)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-22d3ee)](LICENSE)

Rodo tráfego pago para pequenos negócios. As perguntas deste repositório não
são exercício de faculdade — são as que aparecem na reunião mensal, e as dez
consultas de `consultas/` respondem cada uma delas com uma consulta só.

**A semente é determinística e a CI compara a saída de cada consulta com um
arquivo esperado.** Não há `random()` em lugar nenhum: os números vêm de
`md5()` convertido para inteiro, o que dá o mesmo resultado em qualquer máquina
e em qualquer versão do Postgres. É o que transforma "confia em mim" em algo
verificável — se uma consulta mudar de resultado sem que alguém tenha mudado de
ideia, a CI reprova.

## Rodar

```bash
docker run -d --name pg-trafego -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres -e POSTGRES_DB=trafego_pago \
  -p 5432:5432 postgres:16-alpine

export PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres PGDATABASE=trafego_pago

./scripts/rodar.sh              # aplica tudo e mostra as dez saídas
./scripts/rodar.sh --conferir   # compara com esperado/ — é o que a CI roda
```

Ou `make banco && make rodar`.

## O modelo

Estrela enxuta: as dimensões mudam devagar, os fatos crescem todo dia. Separar
os dois é o que permite responder "quanto custou cada lead em agosto" sem
varrer a base inteira.

```mermaid
erDiagram
    CLIENTE  ||--o{ CAMPANHA : contrata
    CANAL    ||--o{ CAMPANHA : veicula
    CAMPANHA ||--o{ METRICA_DIARIA : "mede por dia"
    CAMPANHA ||--o{ LEAD : gera
    LEAD     |o--o| VENDA : "vira (no máximo uma)"

    CLIENTE {
        int  id PK
        text nome UK
        text segmento
        int  verba_mensal_centavos
        date entrou_em
        bool ativo
    }
    CANAL {
        int  id PK
        text nome UK
        text tipo "busca | social | video"
    }
    CAMPANHA {
        int  id PK
        int  cliente_id FK
        int  canal_id FK
        text nome
        text objetivo "leads | vendas | trafego | reconhecimento"
        date inicio
        date fim
    }
    METRICA_DIARIA {
        int  campanha_id PK_FK
        date dia PK
        int  impressoes
        int  cliques
        int  custo_centavos
    }
    LEAD {
        int  id PK
        int  campanha_id FK
        date criado_em
        text status "novo | contatado | qualificado | ganho | perdido"
    }
    VENDA {
        int  id PK
        int  lead_id FK_UK
        date fechada_em
        int  valor_centavos
    }
```

Volume da semente: 8 clientes, 3 canais, 29 campanhas, 3.987 dias de métrica,
4.150 leads e 1.268 vendas.

## As dez perguntas

| # | Pergunta | O que exercita |
|---|---|---|
| 01 | Quanto custou cada lead, por cliente, nos últimos 30 dias? | CTEs paralelos, `LEFT JOIN`, `NULL` com significado |
| 02 | Quais campanhas devolvem mais do que custam (ROAS)? | agregação em dois ramos, `NULLIF` contra divisão por zero, `CASE` de recomendação |
| 03 | O custo por lead está subindo ou caindo mês a mês? | `LAG()`, `date_trunc`, variação percentual |
| 04 | Em que etapa cada campanha perde gente? | funil de quatro estágios, três taxas de conversão |
| 05 | Qual é a melhor campanha de **cada** cliente? | `ROW_NUMBER() OVER (PARTITION BY ...)` |
| 06 | Onde estou gastando sem retorno? | `HAVING` sobre agregado, piso anti-falso-positivo |
| 07 | Em que dia da semana o lead sai mais barato? | `EXTRACT(isodow)`, agregação por derivada de data |
| 08 | Quanto tempo um lead demora para virar venda? | coorte por mês, `PERCENTILE_CONT`, aritmética de datas |
| 09 | Que cliente ativo parou de receber lead? | `NOT EXISTS` (anti-join), subconsulta correlacionada |
| 10 | Quem vai estourar a verba, e em que dia? | `SUM() OVER (PARTITION BY ... ORDER BY ...)`, `FILTER` |

Cada arquivo em `consultas/` começa pela pergunta de negócio e explica a
decisão técnica que ela obrigou. Alguns exemplos do que está lá:

**Sem lead, o custo por lead é `NULL`, não zero.** Dividir por zero não é
"custo zero"; é "ainda não dá para saber". R$ 0,00 leria como *conseguimos
leads de graça* — exatamente a leitura errada para quem decide onde pôr verba.

**Investimento e leads nunca entram no mesmo `JOIN`.** Juntar `metrica_diaria`
com `lead` multiplica o custo de cada dia pelo número de leads daquele dia. Por
isso cada um é agregado no seu próprio CTE e os dois só se encontram no grão
final. É o erro de fan-out, e o tipo que só aparece depois de o número já ter
sido mostrado ao cliente.

**`NOT EXISTS`, nunca `NOT IN`.** Se a subconsulta devolver um único `NULL`, o
`NOT IN` devolve zero linhas — sem erro, sem aviso. É o defeito mais traiçoeiro
do SQL.

**`PERCENTILE_CONT` em vez de `AVG` no tempo até fechar.** Uma venda que
demorou seis meses puxa a média inteira e some com a informação; a mediana não
se abala.

## A semente contém os casos difíceis de propósito

Consulta que nunca devolve linha não prova nada. A semente planta dois cenários
para que duas das dez consultas tenham o que encontrar:

- **Campanhas de reconhecimento quase não geram lead** — é o que elas são: existem
  para ser vistas, não para captar. Gastam igual e convertem quase nada. São as
  cinco linhas que a consulta 06 devolve.
- **As campanhas do Pet Shop Lupi terminam em 05/08.** Uma agência de verdade
  tem campanha pausada. É o cliente que a consulta 09 acusa, com 26 dias sem
  lead.

## Índices e desempenho

`schema/02_indices.sql` traz cinco índices, cada um com a consulta que o
justifica escrita ao lado. Índice sem consulta que o use é custo puro.

A medição está em [`docs/desempenho.md`](docs/desempenho.md), com o `EXPLAIN
ANALYZE` de antes e depois — inclusive uma previsão minha que a medição
desmentiu, deixada no documento de propósito. Em um milhão de linhas, a
agregação por intervalo de datas cai de **50,5 ms para 14,0 ms**, com 4,8×
menos leitura de página.

Vale registrar o que quase todo repositório de SQL erra: **o Postgres não cria
índice para chave estrangeira automaticamente.** Só a chave primária ganha um.
É a causa mais comum de `JOIN` lento, e é invisível até a tabela crescer.

## As mesmas dez perguntas em MySQL 8

`mysql/` traz o porte completo, e a CI roda os dois dialetos contra um servidor
de verdade a cada push. O porte existe pelo documento que ele produziu:
**[`docs/dialetos.md`](docs/dialetos.md)** — porque quase nada ali é "sintaxe
diferente".

Três das mudanças alterariam o número do relatório **sem dar erro nenhum**:

| | Postgres | MySQL |
|---|---|---|
| `SELECT 7 / 2` | `3` (divisão inteira) | `3.5000` — precisa de `DIV` |
| `DATE '2026-08-31' - DATE '2026-07-31'` | `31` (dias) | `100` — precisa de `DATEDIFF` |
| dia da semana ISO | `EXTRACT(isodow)` | `WEEKDAY(x)+1`, **não** `DAYOFWEEK` |

A terceira é a mais traiçoeira: `DAYOFWEEK` é o nome que a mão escreve sozinha,
começa no domingo, e publicaria o relatório com os números certos embaixo dos
rótulos errados.

E uma que o MySQL não tem: **`PERCENTILE_CONT` não existe**. A consulta 08 usa
mediana de propósito — uma venda que demorou seis meses puxa a média inteira —,
então trocar por `AVG` seria o caminho fácil e destruiria o argumento. Ela foi
reconstruída com funções de janela, ficando com o valor do meio ou com a média
dos dois centrais, que é o que o percentil contínuo faz por definição.

`esperado-mysql/` é separado de `esperado/` porque as duas saídas **não são
iguais**, e isso é decisão: a collation do MySQL ordena texto acentuado noutra
posição, e forçar identidade exigiria mutilar as consultas dos dois lados para
esconder uma diferença real. O que a CI garante é que cada dialeto roda e é
reprodutível.

## Estrutura

```
schema/
├── 01_esquema.sql     tabelas, chaves e CHECKs — com o porquê de cada trava
├── 02_indices.sql     cinco índices, cada um com a consulta que o justifica
└── 03_semente.sql     semente determinística, sem random()

consultas/
├── 00_referencia.sql  a view `hoje` — nenhuma consulta usa CURRENT_DATE
└── 01..10_*.sql       uma pergunta de negócio por arquivo

mysql/                 o mesmo, portado para MySQL 8 (esquema, semente e as dez)

esperado/              a saída correta de cada consulta, em CSV
esperado-mysql/        idem, para o dialeto do MySQL — e não é igual, ver docs/dialetos.md
scripts/rodar.sh       aplica, roda e confere (Postgres)
scripts/rodar-mysql.sh idem, no MySQL
scripts/bancada_indice.sql   EXPLAIN ANALYZE em 1 milhão de linhas
docs/desempenho.md     a medição
docs/dialetos.md       o que muda entre Postgres e MySQL, e o que muda em silêncio
```

## Licença

MIT.
