"""Corrida de la foto (snapshot) de PROVEEDORES + DDL de tablas (prototipo ST).

Espejo de gd/proceso.py. Llave natural = RFC. Sociedad/DOMINIO = atributo.
"""

from __future__ import annotations

import datetime as dt

from gd.conexion import get_connection

TABLA = "GD_SNAPSHOT_PROVEEDORES"
# Vista por sociedad (no hay vista unificada: el UNION ALL con '*' rompe por los
# atributos de tipo objeto de fnObtenerDireccion). La foto lee la que toca.
VISTA_POR_DOMINIO = {"ST": "V_GD_PROV_DEP_ST", "RSS": "V_GD_PROV_DEP_RSS"}
VISTA = "V_GD_PROV_DEP_ST"  # base para el DDL del snapshot (define las columnas)
TABLA_DEC = "GD_DECISIONES_PROVEEDORES"

_SNAP_DDL = [
    f"""CREATE TABLE {TABLA} AS
        SELECT CAST(NULL AS VARCHAR2(40)) AS RUN_ID,
               CAST(NULL AS TIMESTAMP)    AS RUN_TS,
               v.* FROM {VISTA} v WHERE 1 = 0""",
    f"""ALTER TABLE {TABLA} ADD CONSTRAINT PK_GD_SNAP_PROV
        PRIMARY KEY (RUN_ID, DOMINIO, RFC)""",
    f"CREATE INDEX IX_GD_SNAP_PROV_RFC   ON {TABLA} (RFC)",
    f"CREATE INDEX IX_GD_SNAP_PROV_DOMTS ON {TABLA} (DOMINIO, RUN_TS)",
]

# Capa de decisión humana. PK = RFC (una decisión por proveedor).
_DEC_DDL = [
    f"""CREATE TABLE {TABLA_DEC} (
           RFC                 VARCHAR2(40)   NOT NULL,
           DOMINIO             VARCHAR2(8),                 -- sociedad donde se depuró (ref)
           ESTADO              VARCHAR2(12)   DEFAULT 'PENDIENTE' NOT NULL,
           RAZON               VARCHAR2(500),
           COMENTARIO          VARCHAR2(500),
           DECIDIDO_POR        VARCHAR2(60),
           ROL                 VARCHAR2(12),
           FECHA_DECISION      DATE,
           HASH_AL_DECIDIR     VARCHAR2(4),
           RUN_ID_AL_DECIDIR   VARCHAR2(40),
           FECHA_ALTA          TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
           FECHA_ACTUALIZACION TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
           CONSTRAINT PK_GD_DEC_PROV PRIMARY KEY (RFC),
           CONSTRAINT CK_GD_DEC_PROV_EST CHECK (ESTADO IN ('MIGRAR','DESCARTAR','PENDIENTE')),
           CONSTRAINT CK_GD_DEC_PROV_RAZ CHECK (ESTADO = 'PENDIENTE' OR RAZON IS NOT NULL))""",
    f"CREATE INDEX IX_GD_DEC_PROV_EST ON {TABLA_DEC} (ESTADO)",
]


def _tabla_existe(cur, nombre) -> bool:
    cur.execute("SELECT COUNT(*) FROM user_tables WHERE table_name = :n", n=nombre)
    return cur.fetchone()[0] > 0


def crear_estructura(cur) -> list[str]:
    """Crea tablas de decisiones y snapshot si faltan. Devuelve mensajes."""
    msgs = []
    if not _tabla_existe(cur, TABLA_DEC):
        for sql in _DEC_DDL:
            cur.execute(sql)
        msgs.append(f"Tabla {TABLA_DEC} creada.")
    if not _tabla_existe(cur, TABLA):
        for sql in _SNAP_DDL:
            cur.execute(sql)
        msgs.append(f"Tabla {TABLA} creada.")
    return msgs


def correr_foto(dominios=("ST", "RSS")) -> list[str]:
    """Crea estructura si falta y corre una foto por sociedad. Devuelve mensajes."""
    msgs = []
    with get_connection() as con:
        cur = con.cursor()
        msgs += crear_estructura(cur)
        con.commit()
        for dom in dominios:
            vista = VISTA_POR_DOMINIO.get(dom)
            if not vista:
                msgs.append(f"{dom}: sin vista de depuración definida, se omite.")
                continue
            marca = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
            run_id = f"RUN_PROV_{dom}_{marca}"
            cur.execute(
                f"INSERT INTO {TABLA} SELECT :run_id, SYSTIMESTAMP, v.* "
                f"FROM {vista} v WHERE v.DOMINIO = :dom",
                run_id=run_id, dom=dom)
            n = cur.rowcount
            con.commit()
            msgs.append(f"{dom}: {n:,} proveedores  (RUN_ID={run_id})")
    return msgs
