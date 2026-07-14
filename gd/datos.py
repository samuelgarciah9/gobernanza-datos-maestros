"""Consultas de monitoreo (buckets / avance / SALIÓ) sobre las vistas de merge.

Devuelve estructuras Python planas (sin pandas) para alimentar la UI Qt.
"""

from __future__ import annotations

from gd.conexion import get_connection


def cargar_datos() -> dict:
    with get_connection() as con:
        cur = con.cursor()

        cur.execute(
            """SELECT PT_DOMAIN,
                      CASE WHEN UPPER(PT_PROD_LINE)='REF' THEN 'NO_PRODUCTIVO' ELSE 'PRODUCTIVO' END AS FIGURA,
                      COUNT(*) AS TOTAL,
                      SUM(CASE WHEN DECISION_PREVIA IN ('MIGRAR','DESCARTAR') THEN 1 ELSE 0 END) AS DECIDIDOS,
                      SUM(CASE WHEN DECISION_PREVIA='MIGRAR'    THEN 1 ELSE 0 END) AS MIGRAR,
                      SUM(CASE WHEN DECISION_PREVIA='DESCARTAR' THEN 1 ELSE 0 END) AS DESCARTAR
                 FROM V_GD_MERGE_MATERIALES
                GROUP BY PT_DOMAIN,
                         CASE WHEN UPPER(PT_PROD_LINE)='REF' THEN 'NO_PRODUCTIVO' ELSE 'PRODUCTIVO' END
                ORDER BY PT_DOMAIN, FIGURA"""
        )
        avance = []
        for dom, fig, total, dec, mig, des in cur.fetchall():
            total, dec, mig, des = int(total), int(dec), int(mig), int(des)
            avance.append({
                "dominio": dom, "figura": fig, "total": total, "decididos": dec,
                "pendientes": total - dec, "migrar": mig, "descartar": des,
                "pct": (100.0 * dec / total) if total else 0.0,
            })

        cur.execute(
            """SELECT BUCKET, COUNT(*) FROM V_GD_MERGE_MATERIALES
                GROUP BY BUCKET"""
        )
        buckets = {b: int(n) for b, n in cur.fetchall()}

        cur.execute(
            """SELECT ATENCION, COUNT(*) FROM V_GD_MERGE_SALIO
                GROUP BY ATENCION"""
        )
        salio = {a: int(n) for a, n in cur.fetchall()}

        cur.execute(
            """SELECT PT_DOMAIN, COUNT(*) FROM V_GD_MERGE_SALIO
                GROUP BY PT_DOMAIN"""
        )
        salio_dom = {d: int(n) for d, n in cur.fetchall()}

        sap = _cargar_sap(cur)

    tot = sum(r["total"] for r in avance)
    dec = sum(r["decididos"] for r in avance)
    figuras = {}
    for r in avance:
        figuras[r["figura"]] = figuras.get(r["figura"], 0) + r["total"]

    # Desglose por dominio (para los KPIs partidos ST | RSS)
    dominios: dict[str, dict] = {}
    for r in avance:
        dd = dominios.setdefault(r["dominio"],
                                 {"total": 0, "dec": 0, "migrar": 0, "descartar": 0, "salio": 0})
        dd["total"] += r["total"]
        dd["dec"] += r["decididos"]
        dd["migrar"] += r["migrar"]
        dd["descartar"] += r["descartar"]
    for d, n in salio_dom.items():
        dominios.setdefault(d, {"total": 0, "dec": 0, "migrar": 0, "descartar": 0, "salio": 0})
        dominios[d]["salio"] = n
    for d, dd in dominios.items():
        dd["pend"] = dd["total"] - dd["dec"]
        dd["pct"] = (100.0 * dd["dec"] / dd["total"]) if dd["total"] else 0.0

    return {
        "avance": avance,
        "buckets": buckets,
        "salio": salio,
        "figuras": figuras,
        "dominios": dominios,
        "sap": sap,
        "tot": tot, "dec": dec, "pend": tot - dec,
        "pct": (100.0 * dec / tot) if tot else 0.0,
        "n_salio": sum(salio.values()),
        "estados": {
            "Migrar": sum(r["migrar"] for r in avance),
            "Descartar": sum(r["descartar"] for r in avance),
        },
    }


def _cargar_sap(cur) -> dict:
    """Avance/reconciliación de carga a SAP (vistas V_GD_SAP_*).

    Mide COBERTURA (del universo, cuánto ya está en SAP) y CUMPLIMIENTO (de lo
    decidido MIGRAR, cuánto está en SAP) más las excepciones de reconciliación.
    """
    cur.execute(
        """SELECT PT_DOMAIN, FIGURA, COUNT(*) AS UNIVERSO, SUM(EN_SAP) AS EN_SAP
             FROM V_GD_SAP_AVANCE
            GROUP BY PT_DOMAIN, FIGURA
            ORDER BY PT_DOMAIN, FIGURA"""
    )
    por_dominio = []
    for dom, fig, uni, ensap in cur.fetchall():
        uni, ensap = int(uni), int(ensap or 0)
        por_dominio.append({
            "dominio": dom, "figura": fig, "universo": uni, "en_sap": ensap,
            "pct": (100.0 * ensap / uni) if uni else 0.0,
        })

    cur.execute("SELECT ESTADO_SAP, COUNT(*) FROM V_GD_SAP_AVANCE GROUP BY ESTADO_SAP")
    recon = {e: int(n) for e, n in cur.fetchall()}

    cur.execute("SELECT COUNT(*) FROM V_GD_SAP_HUERFANOS")
    huerfanos = int(cur.fetchone()[0])

    universo = sum(r["universo"] for r in por_dominio)
    en_sap = sum(r["en_sap"] for r in por_dominio)
    cargado_ok = recon.get("CARGADO_OK", 0)
    por_cargar = recon.get("POR_CARGAR", 0)
    migrar_dec = cargado_ok + por_cargar
    return {
        "por_dominio": por_dominio,
        "recon": recon,
        "universo": universo, "en_sap": en_sap,
        "pct": (100.0 * en_sap / universo) if universo else 0.0,
        "cumplimiento": {
            "migrar": migrar_dec, "en_sap": cargado_ok, "por_cargar": por_cargar,
            "pct": (100.0 * cargado_ok / migrar_dec) if migrar_dec else 0.0,
        },
        "contradicciones": recon.get("CONTRADICCION", 0),
        "sin_decision": recon.get("CARGADO_SIN_DECISION", 0),
        "huerfanos": huerfanos,
    }


def cargar_huerfanos_sap() -> list[dict]:
    """Lista de materiales que están en SAP pero fuera del universo maestro."""
    with get_connection() as con:
        cur = con.cursor()
        cur.execute(
            """SELECT NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN, DESCRIPCION
                 FROM V_GD_SAP_HUERFANOS
                ORDER BY PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO"""
        )
        return [{"material": m, "dominio": dom, "descripcion": desc}
                for m, dom, desc in cur.fetchall()]
