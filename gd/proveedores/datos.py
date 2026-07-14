"""Consultas de monitoreo de PROVEEDORES (buckets / observación SAP) — prototipo ST.

Espejo de gd/datos.py. Devuelve estructuras planas para la UI.
"""

from __future__ import annotations

from gd.conexion import get_connection


def cargar_datos() -> dict:
    with get_connection() as con:
        cur = con.cursor()

        # Avance por sociedad (dominio)
        cur.execute(
            """SELECT DOMINIO,
                      COUNT(*) AS TOTAL,
                      SUM(CASE WHEN DECISION_PREVIA IN ('MIGRAR','DESCARTAR') THEN 1 ELSE 0 END) AS DECIDIDOS,
                      SUM(CASE WHEN DECISION_PREVIA='MIGRAR'    THEN 1 ELSE 0 END) AS MIGRAR,
                      SUM(CASE WHEN DECISION_PREVIA='DESCARTAR' THEN 1 ELSE 0 END) AS DESCARTAR
                 FROM V_GD_PROV_MERGE
                GROUP BY DOMINIO ORDER BY DOMINIO"""
        )
        dominios = {}
        for dom, total, dec, mig, des in cur.fetchall():
            total, dec, mig, des = int(total), int(dec), int(mig), int(des)
            dominios[dom] = {
                "total": total, "dec": dec, "pend": total - dec,
                "migrar": mig, "descartar": des, "salio": 0,
                "pct": (100.0 * dec / total) if total else 0.0,
            }

        cur.execute("SELECT BUCKET, COUNT(*) FROM V_GD_PROV_MERGE GROUP BY BUCKET")
        buckets = {b: int(n) for b, n in cur.fetchall()}

        cur.execute("SELECT ATENCION, COUNT(*) FROM V_GD_PROV_SALIO GROUP BY ATENCION")
        salio = {a: int(n) for a, n in cur.fetchall()}
        cur.execute("SELECT DOMINIO, COUNT(*) FROM V_GD_PROV_SALIO GROUP BY DOMINIO")
        for dom, n in cur.fetchall():
            if dom in dominios:
                dominios[dom]["salio"] = int(n)

        # Observación SAP (BP / extender FI 1200)
        cur.execute("SELECT ESTADO_SAP, COUNT(*) FROM V_GD_PROV_SAP_AVANCE GROUP BY ESTADO_SAP")
        sap = {e: int(n) for e, n in cur.fetchall()}

        # Duplicados entre sociedades (RFC presente en ST y RSS)
        try:
            cur.execute("SELECT COUNT(*) FROM V_GD_PROV_DUP_ST_RSS")
            duplicados = int(cur.fetchone()[0])
        except Exception:  # noqa: BLE001
            duplicados = 0

    tot = sum(d["total"] for d in dominios.values())
    dec = sum(d["dec"] for d in dominios.values())
    return {
        "dominios": dominios,
        "buckets": buckets,
        "salio": salio,
        "sap": sap,
        "tot": tot, "dec": dec, "pend": tot - dec,
        "pct": (100.0 * dec / tot) if tot else 0.0,
        "n_salio": sum(salio.values()),
        "duplicados": duplicados,
        "extendido_1200": sap.get("MIGRADO_EXTENDIDO_1200", 0),
        "falta_1200": sap.get("MIGRADO_FALTA_EXTENDER_1200", 0),
        "ya_bp": sap.get("MIGRADO_EXTENDIDO_1200", 0) + sap.get("MIGRADO_FALTA_EXTENDER_1200", 0),
        "por_crear": sap.get("POR_CREAR", 0),
        "estados": {
            "Migrar": sum(d["migrar"] for d in dominios.values()),
            "Descartar": sum(d["descartar"] for d in dominios.values()),
        },
    }
