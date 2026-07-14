"""Paso 2 - crea la TABLA DE DECISIONES + catalogo de razones, y siembra el catalogo.

Idempotente: si las tablas ya existen, no las recrea. El catalogo solo inserta
las razones que falten.

Uso:
    python 07_decisiones.py
"""

from __future__ import annotations

from connection import get_connection

TABLA_DEC = "GD_DECISIONES_MATERIALES"
TABLA_CAT = "GD_CAT_RAZONES"

DDL_CAT = f"""
    CREATE TABLE {TABLA_CAT} (
       RAZON            VARCHAR2(200) NOT NULL,
       ESTADO_SUGERIDO  VARCHAR2(12),
       ACTIVO           CHAR(1) DEFAULT 'S' NOT NULL,
       CONSTRAINT PK_GD_CAT_RAZONES PRIMARY KEY (RAZON),
       CONSTRAINT CK_GD_CAT_ACTIVO  CHECK (ACTIVO IN ('S','N')),
       CONSTRAINT CK_GD_CAT_ESTADO  CHECK (ESTADO_SUGERIDO IS NULL OR
                    ESTADO_SUGERIDO IN ('MIGRAR','DESCARTAR','PENDIENTE'))
    )
"""

DDL_DEC = [
    f"""
    CREATE TABLE {TABLA_DEC} (
       NUMERO_PRODUCTO_ANTIGUO  VARCHAR2(30) NOT NULL,
       PT_DOMAIN                VARCHAR2(8)  NOT NULL,
       ESTADO                   VARCHAR2(12) DEFAULT 'PENDIENTE' NOT NULL,
       RAZON                    VARCHAR2(500),
       COMENTARIO               VARCHAR2(500),
       DECIDIDO_POR             VARCHAR2(60),
       ROL                      VARCHAR2(12),
       FECHA_DECISION           DATE,
       HASH_AL_DECIDIR          VARCHAR2(8),
       RUN_ID_AL_DECIDIR        VARCHAR2(40),
       FECHA_ALTA               TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
       FECHA_ACTUALIZACION      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
       CONSTRAINT PK_GD_DECISIONES PRIMARY KEY (NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN),
       CONSTRAINT CK_GD_DEC_ESTADO CHECK (ESTADO IN ('MIGRAR','DESCARTAR','PENDIENTE')),
       CONSTRAINT CK_GD_DEC_DOM    CHECK (PT_DOMAIN IN ('ST','RSS')),
       CONSTRAINT CK_GD_DEC_ROL    CHECK (ROL IS NULL OR ROL IN ('COMPRAS','INVENTARIOS','INGENIERIA')),
       CONSTRAINT CK_GD_DEC_RAZON  CHECK (ESTADO = 'PENDIENTE' OR RAZON IS NOT NULL)
    )
    """,
    f"CREATE INDEX IX_GD_DEC_ESTADO ON {TABLA_DEC} (ESTADO)",
    f"CREATE INDEX IX_GD_DEC_ROL    ON {TABLA_DEC} (ROL)",
    f"CREATE INDEX IX_GD_DEC_DOM    ON {TABLA_DEC} (PT_DOMAIN)",
    f"""
    CREATE OR REPLACE TRIGGER TRG_GD_DEC_UPD
       BEFORE UPDATE ON {TABLA_DEC}
       FOR EACH ROW
    BEGIN
       :NEW.FECHA_ACTUALIZACION := SYSTIMESTAMP;
    END;
    """,
]

# Razones comunes iniciales (ESTADO sugerido para el desplegable del piloto)
RAZONES = [
    ("Sin actividad - obsoleto",                                  "DESCARTAR"),
    ("Duplicado entre especialidades - se migra en el otro dominio", "DESCARTAR"),
    ("Material sin uso en los ultimos 180 dias",                  "DESCARTAR"),
    ("Material activo - se migra",                                "MIGRAR"),
    ("Con existencias en inventario",                             "MIGRAR"),
    ("Con orden abierta (compra / venta / trabajo)",             "MIGRAR"),
    ("Con inventario de seguridad",                               "MIGRAR"),
    ("Requiere completar datos maestros antes de migrar",         "MIGRAR"),
    ("Datos incompletos - pendiente de revision del area",        "PENDIENTE"),
]


def existe_tabla(cur, nombre: str) -> bool:
    cur.execute("SELECT COUNT(*) FROM user_tables WHERE table_name = :n", n=nombre)
    return cur.fetchone()[0] > 0


def crear(con) -> None:
    cur = con.cursor()

    if existe_tabla(cur, TABLA_CAT):
        print(f"Tabla {TABLA_CAT} ya existe.")
    else:
        print(f"Creando {TABLA_CAT} ...")
        cur.execute(DDL_CAT)
        con.commit()

    if existe_tabla(cur, TABLA_DEC):
        print(f"Tabla {TABLA_DEC} ya existe.")
    else:
        print(f"Creando {TABLA_DEC} (+ indices + trigger) ...")
        for sql in DDL_DEC:
            cur.execute(sql)
        con.commit()


def sembrar_catalogo(con) -> None:
    cur = con.cursor()
    insertadas = 0
    for razon, estado in RAZONES:
        cur.execute(
            f"SELECT COUNT(*) FROM {TABLA_CAT} WHERE RAZON = :r", r=razon
        )
        if cur.fetchone()[0] == 0:
            cur.execute(
                f"INSERT INTO {TABLA_CAT} (RAZON, ESTADO_SUGERIDO, ACTIVO) "
                f"VALUES (:r, :e, 'S')",
                r=razon, e=estado,
            )
            insertadas += 1
    con.commit()
    print(f"Catalogo de razones: {insertadas} nuevas insertadas.")


def verificar(con) -> None:
    cur = con.cursor()
    print("\n=== Catalogo de razones activas ===")
    cur.execute(
        f"SELECT ESTADO_SUGERIDO, RAZON FROM {TABLA_CAT} "
        f"WHERE ACTIVO='S' ORDER BY ESTADO_SUGERIDO, RAZON"
    )
    for estado, razon in cur.fetchall():
        print(f"  [{estado or '-':10}] {razon}")

    print(f"\n=== Filas en {TABLA_DEC} ===")
    cur.execute(f"SELECT COUNT(*) FROM {TABLA_DEC}")
    print(f"  decisiones registradas: {cur.fetchone()[0]}")

    print("\n=== Restricciones activas en la tabla de decisiones ===")
    cur.execute(
        "SELECT constraint_name, constraint_type "
        "FROM user_constraints WHERE table_name = :t "
        "ORDER BY constraint_type, constraint_name",
        t=TABLA_DEC,
    )
    tipo = {"P": "PK", "C": "CHECK/NOT NULL", "R": "FK", "U": "UNIQUE"}
    for nombre, t in cur.fetchall():
        print(f"  {tipo.get(t, t):15} {nombre}")


if __name__ == "__main__":
    with get_connection() as con:
        crear(con)
        sembrar_catalogo(con)
        verificar(con)
