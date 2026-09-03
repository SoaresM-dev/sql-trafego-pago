# Os índices valem a pena? A medição

**Regra deste repositório: meça antes de otimizar.** Índice sem medição é
palpite — ocupa disco e torna todo `INSERT` mais lento em troca de uma
suposição. O que está abaixo foi medido, não estimado.

Reproduza com:

```bash
psql -f scripts/bancada_indice.sql
```

## O que eu esperava, e o que a medição disse

Minha aposta era que, com 4.117 linhas em `metrica_diaria`, o planejador
ignoraria `ix_metrica_dia` e faria varredura sequencial — tabela pequena cabe
em poucas páginas, e ler tudo de uma vez costuma ganhar do salto pelo índice.

**Errei.** O plano padrão já usa o índice:

```
Bitmap Heap Scan on metrica_diaria  (actual time=0.036..0.132 rows=769)
  ->  Bitmap Index Scan on ix_metrica_dia  (actual time=0.029..0.030 rows=769)
Buffers: shared hit=29
```

Forçando a varredura sequencial com `enable_bitmapscan = off`, para comparar:

```
Seq Scan on metrica_diaria  (actual time=0.009..0.216 rows=769)
Buffers: shared hit=26
```

Ou seja: nesse tamanho os dois caminhos empatam na prática — 0,13 ms contra
0,22 ms, com 29 blocos contra 26. O índice ganha por pouco, e o planejador
escolhe certo. Deixo o erro registrado de propósito: é a diferença entre
"acho que o índice ajuda" e olhar o plano.

## O caso em que a diferença aparece de verdade

`scripts/bancada_indice.sql` monta a mesma tabela com **um milhão de linhas** e
roda a mesma agregação por intervalo de datas, antes e depois de criar o índice.
Postgres 16, mesma máquina, mesma sessão:

| | sem índice | com índice |
|---|---|---|
| Plano | Parallel Seq Scan | Bitmap Index Scan → Bitmap Heap Scan |
| Blocos lidos (`shared hit + read`) | 6.414 | 1.348 |
| **Tempo de execução** | **50,5 ms** | **14,0 ms** |

**3,6× mais rápido, com 4,8× menos leitura de disco.** E note que a economia
vem de onde importa: o índice não deixou o processador mais rápido, deixou o
banco tocar menos página.

## Por que os quatro índices existem

Cada um de `schema/02_indices.sql` é percorrido por alguma das dez consultas —
o arquivo diz qual, linha a linha. O que merece destaque é o
`ix_lead_campanha`: **o Postgres não cria índice para chave estrangeira
automaticamente.** Só a chave primária ganha um. Esquecer isso é a causa mais
comum de `JOIN` lento em banco relacional, e é invisível até a tabela crescer.

## O que esta bancada não reproduz

- **Cache quente.** Todos os números foram medidos com o dado já no
  `shared_buffers` do Postgres. Em produção, com disco frio, a diferença tende
  a ser maior — o índice lê menos página, e é justamente a leitura de página
  que custa caro quando ela vem do disco.
- **Concorrência.** Uma sessão só. Sob carga, o índice ajuda mais ainda,
  porque varredura sequencial disputa banda de I/O com todo mundo.
- **Escrita.** Não medi o custo do índice no `INSERT`. Numa tabela que recebe
  uma carga diária, ele é pequeno; numa que recebe escrita o tempo todo,
  precisaria entrar na conta.
