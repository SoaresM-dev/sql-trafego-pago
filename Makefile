PSQL ?= psql
export PGDATABASE ?= trafego_pago

.PHONY: banco carregar rodar conferir gravar bancada limpar

## banco: sobe um Postgres 16 local no Docker
banco:
	docker run -d --name pg-trafego -e POSTGRES_PASSWORD=postgres \
	  -e POSTGRES_USER=postgres -e POSTGRES_DB=$(PGDATABASE) \
	  -p 5432:5432 postgres:16-alpine

## carregar: esquema, índices e semente
carregar:
	./scripts/rodar.sh --gravar >/dev/null && echo "carregado"

## rodar: mostra a saída das dez consultas
rodar:
	./scripts/rodar.sh

## conferir: compara com esperado/ (é o que a CI roda)
conferir:
	./scripts/rodar.sh --conferir

## gravar: regrava esperado/ depois de uma mudança intencional
gravar:
	./scripts/rodar.sh --gravar

## bancada: EXPLAIN ANALYZE com e sem índice, em 1 milhão de linhas
bancada:
	$(PSQL) -v ON_ERROR_STOP=1 -f scripts/bancada_indice.sql

## limpar: derruba o container
limpar:
	docker rm -f pg-trafego
