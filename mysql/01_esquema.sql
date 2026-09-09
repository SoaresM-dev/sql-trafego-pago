-- =============================================================================
-- Esquema — porte para MySQL 8.
--
-- Mesma modelagem em estrela de `schema/01_esquema.sql`, mesmas invariantes.
-- O que muda é dialeto, e cada mudança está anotada aqui e resumida em
-- `docs/dialetos.md`. Regra do porte: **nenhuma garantia é abandonada por
-- conveniência.** Se o MySQL não tem a construção, o porte encontra outra que
-- garanta a mesma coisa — ou o comentário diz explicitamente o que se perdeu.
-- =============================================================================

-- (1) MySQL não tem esquema dentro de banco: `SCHEMA` é sinônimo de `DATABASE`.
--     Então o que no Postgres é o esquema `trafego` aqui é o próprio banco.
DROP DATABASE IF EXISTS trafego_mysql;
CREATE DATABASE trafego_mysql
    -- (2) Collation fixada no banco, não herdada do servidor. Sem isto a
    --     ordenação de nome de cliente depende da configuração da máquina, e a
    --     saída das consultas deixa de ser reprodutível — que é a única coisa
    --     que este repositório promete.
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE trafego_mysql;

-- --- dimensões ---------------------------------------------------------------

CREATE TABLE cliente (
    -- (3) `GENERATED ALWAYS AS IDENTITY` é SQL padrão e o MySQL não tem.
    --     `AUTO_INCREMENT` é o equivalente, com uma diferença que importa: ele
    --     não impede a inserção explícita de um id, então a garantia "ninguém
    --     escreve nesta coluna" some. Aqui não faz diferença — só a semente
    --     escreve —, mas some.
    id            INT AUTO_INCREMENT PRIMARY KEY,
    -- (4) `text` do Postgres não pode ser UNIQUE sem prefixo no MySQL, porque
    --     índice de BLOB/TEXT exige comprimento. VARCHAR com teto explícito é
    --     mais honesto do que TEXT com prefixo arbitrário.
    nome          VARCHAR(120) NOT NULL UNIQUE,
    segmento      VARCHAR(60)  NOT NULL,
    verba_mensal_centavos INT  NOT NULL CHECK (verba_mensal_centavos >= 0),
    entrou_em     DATE         NOT NULL,
    ativo         BOOLEAN      NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE canal (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    nome    VARCHAR(60) NOT NULL UNIQUE,
    tipo    VARCHAR(10) NOT NULL CHECK (tipo IN ('busca', 'social', 'video'))
) ENGINE=InnoDB;

CREATE TABLE campanha (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id  INT NOT NULL,
    canal_id    INT NOT NULL,
    nome        VARCHAR(160) NOT NULL,
    objetivo    VARCHAR(20)  NOT NULL
                CHECK (objetivo IN ('leads', 'vendas', 'trafego', 'reconhecimento')),
    inicio      DATE NOT NULL,
    fim         DATE,
    CONSTRAINT periodo_valido CHECK (fim IS NULL OR fim >= inicio),
    CONSTRAINT nome_unico_por_cliente UNIQUE (cliente_id, nome),
    FOREIGN KEY (cliente_id) REFERENCES cliente(id) ON DELETE CASCADE,
    FOREIGN KEY (canal_id)   REFERENCES canal(id)
) ENGINE=InnoDB;

-- --- fatos -------------------------------------------------------------------

CREATE TABLE metrica_diaria (
    campanha_id    INT  NOT NULL,
    dia            DATE NOT NULL,
    impressoes     INT  NOT NULL CHECK (impressoes >= 0),
    cliques        INT  NOT NULL CHECK (cliques >= 0),
    custo_centavos INT  NOT NULL CHECK (custo_centavos >= 0),
    PRIMARY KEY (campanha_id, dia),
    CONSTRAINT cliques_nao_passam_de_impressoes CHECK (cliques <= impressoes),
    FOREIGN KEY (campanha_id) REFERENCES campanha(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- (5) `lead` é **palavra reservada no MySQL 8** — é a função de janela LEAD().
--     No Postgres não é, e por isso o nome passou despercebido no original.
--     Duas saídas: renomear a tabela, ou citá-la com crase em toda referência.
--     Renomear divergiria o modelo entre os dois dialetos, que é pior: o
--     mesmo diagrama deixaria de descrever os dois bancos. Fica a crase.
CREATE TABLE `lead` (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    campanha_id INT  NOT NULL,
    criado_em   DATE NOT NULL,
    status      VARCHAR(12) NOT NULL DEFAULT 'novo'
                CHECK (status IN ('novo', 'contatado', 'qualificado', 'ganho', 'perdido')),
    FOREIGN KEY (campanha_id) REFERENCES campanha(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE venda (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    lead_id        INT  NOT NULL UNIQUE,
    fechada_em     DATE NOT NULL,
    valor_centavos INT  NOT NULL CHECK (valor_centavos > 0),
    FOREIGN KEY (lead_id) REFERENCES `lead`(id) ON DELETE CASCADE
) ENGINE=InnoDB;
