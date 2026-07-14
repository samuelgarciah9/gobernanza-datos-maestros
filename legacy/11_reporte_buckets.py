"""Paso 3 - Reporte de reconciliacion: buckets por dominio + lista SALIO.

Muestra, para el ultimo snapshot de cada dominio, cuantos materiales caen en cada
bucket (POR_DECIDIR / VIGENTE / RE_REVISAR), el desglose por MOTIVO de los
RE_REVISAR, y la lista del bucket 4 (SALIO: decididos que ya no estan en el run).

Uso:
    python 11_reporte_buckets.py
"""

from __future__ import annotations

from connection import get_connection


def main() -> None:
    with get_connection() as con:
        cur = con.cursor()

        print("=" * 60)
        print(" RECONCILIACION (Paso 3) - estado por bucket")
        print("=" * 60)

        cur.execute(
            """SELECT PT_DOMAIN, BUCKET, COUNT(*)
                 FROM V_GD_MERGE_MATERIALES
                GROUP BY PT_DOMAIN, BUCKET
                ORDER BY PT_DOMAIN, BUCKET"""
        )
        rows = cur.fetchall()
        dom_actual = None
        for dom, bucket, n in rows:
            if dom != dom_actual:
                print(f"\nDominio {dom}:")
                dom_actual = dom
            print(f"   {bucket:12} {n:>7,}")

        print("\n--- RE_REVISAR por MOTIVO ---")
        cur.execute(
            """SELECT PT_DOMAIN, MOTIVO, COUNT(*)
                 FROM V_GD_MERGE_MATERIALES
                WHERE BUCKET = 'RE_REVISAR'
                GROUP BY PT_DOMAIN, MOTIVO
                ORDER BY PT_DOMAIN, MOTIVO"""
        )
        motivos = cur.fetchall()
        if motivos:
            for dom, motivo, n in motivos:
                print(f"   {dom:4} {motivo:20} {n:>7,}")
        else:
            print("   (ninguno)")

        print("\n--- Bucket 4: SALIO (decididos que ya no estan en el run) ---")
        cur.execute(
            """SELECT ATENCION, COUNT(*)
                 FROM V_GD_MERGE_SALIO
                GROUP BY ATENCION ORDER BY ATENCION"""
        )
        salio = cur.fetchall()
        if salio:
            for atencion, n in salio:
                print(f"   {atencion:12} {n:>7,}")
            print("\n   Detalle (los que requieren REVISAR):")
            cur.execute(
                """SELECT NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN, DECISION, DECIDIDO_POR
                     FROM V_GD_MERGE_SALIO WHERE ATENCION = 'REVISAR'
                    ORDER BY PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO"""
            )
            det = cur.fetchall()
            for mat, dom, dec, quien in det[:50]:
                print(f"     {mat:20} {dom:4} {dec:10} {quien or ''}")
            if len(det) > 50:
                print(f"     ... y {len(det) - 50} mas.")
        else:
            print("   (ninguno)")

        print()


if __name__ == "__main__":
    main()
