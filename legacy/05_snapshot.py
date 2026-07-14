"""Motor de SNAPSHOT (Paso 1) - foto inmutable append-only, separada por dominio.

- Crea la tabla GD_SNAPSHOT_MATERIALES si no existe (tipos heredados de la
  vista V_GD_MATERIALES_DEP via CTAS WHERE 1=0).
- Corre una foto por dominio (RUN_ID tipo 'RUN_ST_<fecha-hora>').
- La tabla SOLO crece: cada corrida es un RUN_ID nuevo, nunca se sobrescribe.

Uso:
    python 05_snapshot.py            # corre foto de ST y de RSS
    python 05_snapshot.py ST         # solo ST
    python 05_snapshot.py RSS        # solo RSS
"""

from __future__ import annotations

import datetime as dt
import sys

from connection import get_connection

TABLA = "GD_SNAPSHOT_MATERIALES"
VISTA = "V_GD_MATERIALES_DEP"
DOMINIOS = ("ST", "RSS")

DDL = [
    f"""
    CREATE TABLE {TABLA} AS
    SELECT CAST(NULL AS VARCHAR2(40)) AS RUN_ID,
           CAST(NULL AS TIMESTAMP)    AS RUN_TS,
           v.*
      FROM {VISTA} v
     WHERE 1 = 0
    """,
    f"""
    ALTER TABLE {TABLA}
       ADD CONSTRAINT PK_GD_SNAPSHOT_MAT
       PRIMARY KEY (RUN_ID, PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO)
    """,
    f"CREATE INDEX IX_GD_SNAP_PART ON {TABLA} (NUMERO_PRODUCTO_ANTIGUO)",
    f"CREATE INDEX IX_GD_SNAP_DOM  ON {TABLA} (PT_DOMAIN)",
    f"CREATE INDEX IX_GD_SNAP_RUN  ON {TABLA} (RUN_ID)",
]


def tabla_existe(cur) -> bool:
    cur.execute(
        "SELECT COUNT(*) FROM user_tables WHERE table_name = :n", n=TABLA
    )
    return cur.fetchone()[0] > 0


def crear_tabla(con) -> None:
    cur = con.cursor()
    if tabla_existe(cur):
        print(f"Tabla {TABLA} ya existe. Se reutiliza (append-only).")
        return
    print(f"Creando tabla {TABLA} ...")
    for sql in DDL:
        cur.execute(sql)
    con.commit()
    print("Tabla e indices creados.")


def correr_snapshot(con, dominio: str) -> str:
    marca = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_id = f"RUN_{dominio}_{marca}"
    cur = con.cursor()
    cur.execute(
        f"""
        INSERT INTO {TABLA}
        SELECT :run_id, SYSTIMESTAMP, v.*
          FROM {VISTA} v
         WHERE v.PT_DOMAIN = :dom
        """,
        run_id=run_id,
        dom=dominio,
    )
    n = cur.rowcount
    con.commit()
    print(f"  {dominio:4} -> RUN_ID={run_id}  ({n:,} materiales)")
    return run_id


def verificar(con) -> None:
    cur = con.cursor()
    print("\n=== Verificacion: filas por corrida ===")
    cur.execute(
        f"""
        SELECT RUN_ID, PT_DOMAIN, COUNT(*), MIN(RUN_TS)
          FROM {TABLA}
         GROUP BY RUN_ID, PT_DOMAIN
         ORDER BY MIN(RUN_TS)
        """
    )
    for run_id, dom, n, ts in cur.fetchall():
        print(f"  {run_id:28} {dom:4} {n:>8,}  {ts}")

    print("\n=== Salud: unicidad de la clave (debe dar 0) ===")
    cur.execute(
        f"""
        SELECT COUNT(*) FROM (
            SELECT RUN_ID, PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO, COUNT(*) c
              FROM {TABLA}
             GROUP BY RUN_ID, PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO
            HAVING COUNT(*) > 1)
        """
    )
    print(f"  claves duplicadas: {cur.fetchone()[0]}")

    print("\n=== Salud: integridad del hash (largo <> 8, debe dar 0) ===")
    cur.execute(
        f"SELECT COUNT(*) FROM {TABLA} WHERE LENGTH(BANDERAS_HASH) <> 8"
    )
    print(f"  hashes con largo != 8: {cur.fetchone()[0]}")


if __name__ == "__main__":
    args = [a.upper() for a in sys.argv[1:]]
    objetivo = args if args else list(DOMINIOS)
    invalidos = [d for d in objetivo if d not in DOMINIOS]
    if invalidos:
        sys.exit(f"Dominio(s) no valido(s): {invalidos}. Use: {DOMINIOS}")

    with get_connection() as con:
        crear_tabla(con)
        print("\nCorriendo snapshot(s):")
        for dom in objetivo:
            correr_snapshot(con, dom)
        verificar(con)
