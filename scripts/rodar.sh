#!/usr/bin/env bash
# Aplica o esquema, semeia e roda as dez consultas.
#
#   ./scripts/rodar.sh            mostra as saídas
#   ./scripts/rodar.sh --gravar   regrava os arquivos de esperado/
#   ./scripts/rodar.sh --conferir compara com esperado/ e falha na diferença
#
# É o modo --conferir que a CI usa. Ele só é possível porque a semente é
# determinística: com `random()` nenhuma saída poderia ser comparada com nada.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${PGDATABASE:=trafego_pago}"
export PGDATABASE
PSQL=(psql -v ON_ERROR_STOP=1 -q)

modo="${1:-mostrar}"

echo "==> esquema, índices e semente"
"${PSQL[@]}" -f schema/01_esquema.sql
"${PSQL[@]}" -f schema/02_indices.sql
"${PSQL[@]}" -f schema/03_semente.sql
"${PSQL[@]}" -f consultas/00_referencia.sql
"${PSQL[@]}" -c "ANALYZE;"   # sem estatísticas o planejador escolhe mal

falhas=0
for consulta in consultas/[0-9][0-9]_*.sql; do
    nome=$(basename "$consulta" .sql)
    [ "$nome" = "00_referencia" ] && continue

    case "$modo" in
        --gravar)
            "${PSQL[@]}" --csv -f "$consulta" > "esperado/$nome.csv"
            echo "gravado  esperado/$nome.csv"
            ;;
        --conferir)
            obtido=$(mktemp)
            "${PSQL[@]}" --csv -f "$consulta" > "$obtido"
            if diff -u "esperado/$nome.csv" "$obtido" > /dev/null; then
                echo "ok       $nome"
            else
                echo "DIFERE   $nome"
                diff -u "esperado/$nome.csv" "$obtido" | head -20
                falhas=$((falhas + 1))
            fi
            rm -f "$obtido"
            ;;
        *)
            echo
            echo "=== $nome ==="
            "${PSQL[@]}" -f "$consulta"
            ;;
    esac
done

if [ "$falhas" -gt 0 ]; then
    echo
    echo "$falhas consulta(s) mudaram de resultado."
    exit 1
fi
