"""Corrida del snapshot (foto) — portado de 05_snapshot.py a función importable."""

from __future__ import annotations

import datetime as dt

from gd.conexion import get_connection

TABLA = "GD_SNAPSHOT_MATERIALES"
VISTA = "V_GD_MATERIALES_DEP"

# Cache del universo maestro (Paso 7). La vista QAD.SAP_MAESTRO_MATERIALES_GENERAL
# es cara (~27s); se materializa aqui para que el dashboard consulte una tabla rapida.
CACHE_TABLA = "GD_SAP_MAESTRO_CACHE"
VISTA_MAESTRO = "QAD.SAP_MAESTRO_MATERIALES_GENERAL"
_CACHE_DDL = [
    f"""CREATE TABLE {CACHE_TABLA} (
           NUMERO_PRODUCTO_ANTIGUO VARCHAR2(30),
           PT_DOMAIN               VARCHAR2(8),
           PT_PROD_LINE            VARCHAR2(30),
           DESCRIPCION             VARCHAR2(200))""",
    f"CREATE INDEX IX_GD_MAESTRO_CACHE_PART ON {CACHE_TABLA} (NUMERO_PRODUCTO_ANTIGUO)",
]


def refrescar_cache_maestro(cur) -> int:
    """(Re)genera GD_SAP_MAESTRO_CACHE desde la vista maestra. Devuelve nº de filas."""
    cur.execute("SELECT COUNT(*) FROM user_tables WHERE table_name = :n", n=CACHE_TABLA)
    if cur.fetchone()[0] == 0:
        for sql in _CACHE_DDL:
            cur.execute(sql)
    else:
        cur.execute(f"TRUNCATE TABLE {CACHE_TABLA}")
    cur.execute(
        f"""INSERT INTO {CACHE_TABLA} (NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN, PT_PROD_LINE, DESCRIPCION)
            SELECT NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN, PT_PROD_LINE, SUBSTR(DESCRIPCION, 1, 200)
              FROM {VISTA_MAESTRO}""")
    return cur.rowcount

_DDL = [
    f"""CREATE TABLE {TABLA} AS
        SELECT CAST(NULL AS VARCHAR2(40)) AS RUN_ID,
               CAST(NULL AS TIMESTAMP)    AS RUN_TS,
               v.* FROM {VISTA} v WHERE 1 = 0""",
    f"""ALTER TABLE {TABLA} ADD CONSTRAINT PK_GD_SNAPSHOT_MAT
        PRIMARY KEY (RUN_ID, PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO)""",
    f"CREATE INDEX IX_GD_SNAP_PART ON {TABLA} (NUMERO_PRODUCTO_ANTIGUO)",
    f"CREATE INDEX IX_GD_SNAP_DOM  ON {TABLA} (PT_DOMAIN)",
    f"CREATE INDEX IX_GD_SNAP_RUN  ON {TABLA} (RUN_ID)",
]


def _tabla_existe(cur) -> bool:
    cur.execute("SELECT COUNT(*) FROM user_tables WHERE table_name = :n", n=TABLA)
    return cur.fetchone()[0] > 0


def correr_foto(dominios=("ST", "RSS")) -> list[str]:
    """Crea la tabla si falta y corre una foto por dominio. Devuelve mensajes."""
    msgs = []
    with get_connection() as con:
        cur = con.cursor()
        if not _tabla_existe(cur):
            for sql in _DDL:
                cur.execute(sql)
            con.commit()
            msgs.append(f"Tabla {TABLA} creada.")
        for dom in dominios:
            marca = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
            run_id = f"RUN_{dom}_{marca}"
            cur.execute(
                f"INSERT INTO {TABLA} SELECT :run_id, SYSTIMESTAMP, v.* "
                f"FROM {VISTA} v WHERE v.PT_DOMAIN = :dom",
                run_id=run_id, dom=dom)
            n = cur.rowcount
            con.commit()
            msgs.append(f"{dom}: {n:,} materiales  (RUN_ID={run_id})")
        # Mantener la cache del universo maestro al dia con cada foto.
        try:
            nc = refrescar_cache_maestro(cur)
            con.commit()
            msgs.append(f"Cache maestro SAP refrescada: {nc:,} materiales.")
        except Exception as e:  # noqa: BLE001
            msgs.append(f"Aviso: no se pudo refrescar la cache maestro ({e}).")
    return msgs
