#!/usr/bin/env bash
# Aplica o esquema, semeia e roda as dez consultas — no MySQL 8.
#
#   ./scripts/rodar-mysql.sh            mostra as saídas
#   ./scripts/rodar-mysql.sh --gravar   regrava os arquivos de esperado-mysql/
#   ./scripts/rodar-mysql.sh --conferir compara e falha na diferença
#
# Gêmeo de `rodar.sh`, com três diferenças que o dialeto obriga:
#
#   1. O cliente do MySQL não tem `--csv`. A saída sai separada por TAB e é
#      convertida aqui, o que também normaliza o `NULL` do MySQL para o campo
#      vazio que o Postgres emite — sem isso, comparar as duas saídas seria
#      comparar formatação, não dado.
#   2. Não existe `ON_ERROR_STOP`: o erro tem de vir do código de saída, e por
#      isso cada arquivo é uma invocação própria com `set -e`.
#   3. `ANALYZE` no MySQL é por tabela, não global.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${MYSQL_HOST:=127.0.0.1}"
: "${MYSQL_PORT:=3307}"
: "${MYSQL_USER:=root}"
: "${MYSQL_PASSWORD:=root}"

MYSQL=(mysql --host="$MYSQL_HOST" --port="$MYSQL_PORT" --user="$MYSQL_USER"
       "--password=$MYSQL_PASSWORD" --batch --raw --default-character-set=utf8mb4)

# TAB -> vírgula, e o NULL do MySQL -> campo vazio, como o CSV do psql.
para_csv() {
    python3 -c '
import csv, sys
saida = csv.writer(sys.stdout, lineterminator="\n")
for linha in sys.stdin.read().splitlines():
    saida.writerow(["" if c == "NULL" else c for c in linha.split("\t")])
'
}

modo="${1:-mostrar}"

echo "==> esquema, índices e semente (MySQL)"
for arquivo in mysql/01_esquema.sql mysql/02_indices.sql mysql/03_semente.sql \
               mysql/consultas/00_referencia.sql; do
    "${MYSQL[@]}" < "$arquivo"
done

# Sem estatísticas o planejador escolhe mal — e no MySQL isso é por tabela.
"${MYSQL[@]}" trafego_mysql -e "
    ANALYZE TABLE cliente, canal, campanha, metrica_diaria, \`lead\`, venda;" > /dev/null

falhas=0
for consulta in mysql/consultas/[0-9][0-9]_*.sql; do
    nome=$(basename "$consulta" .sql)
    [ "$nome" = "00_referencia" ] && continue

    case "$modo" in
        --gravar)
            "${MYSQL[@]}" < "$consulta" | para_csv > "esperado-mysql/$nome.csv"
            echo "gravado  esperado-mysql/$nome.csv"
            ;;
        --conferir)
            obtido=$(mktemp)
            "${MYSQL[@]}" < "$consulta" | para_csv > "$obtido"
            if diff -u "esperado-mysql/$nome.csv" "$obtido" > /dev/null; then
                echo "ok       $nome"
            else
                echo "DIFERE   $nome"
                diff -u "esperado-mysql/$nome.csv" "$obtido" | head -20
                falhas=$((falhas + 1))
            fi
            rm -f "$obtido"
            ;;
        *)
            echo
            echo "=== $nome ==="
            "${MYSQL[@]}" < "$consulta"
            ;;
    esac
done

if [ "$falhas" -gt 0 ]; then
    echo
    echo "$falhas consulta(s) mudaram de resultado."
    exit 1
fi
