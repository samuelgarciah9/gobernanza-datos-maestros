# Módulo de Proveedores — Depuración para migración SAP (prototipo ST)

Espejo del proceso de **materiales** aplicado al maestro de **proveedores**. Reutiliza el
mismo patrón: **foto inmutable (snapshot) + decisión humana por separado**, reconciliación
por buckets y round-trip en Excel. Vive en el mismo proyecto y las mismas apps
(dashboard e importador); el código está en `gd/proveedores/` y el SQL en
`sql/20_proveedores_dep.sql` y `sql/21_proveedores_merge_sap.sql`.

Sociedades cubiertas: **ST** (prototipo principal) y **RSS**.

---

## Llave natural: el RFC

A diferencia de materiales (llave = `NUMERO_PRODUCTO_ANTIGUO` por dominio), en proveedores
la llave es el **RFC** (`AD_GST_ID`) y la **decisión es única por RFC**:

- Un proveedor puede existir en varias sociedades (ST y RSS); se decide **una sola vez**.
- `DOMINIO` (sociedad) es un **atributo**, no parte de la llave de decisión.
- `PERSONA_FISICA = 'X'` cuando el RFC tiene 13 caracteres.
- Todo cruce de texto es case-insensitive (`UPPER` en ambos lados), igual que en materiales.

La vista `V_GD_PROV_DUP_ST_RSS` lista los RFC presentes en **ambas** sociedades (sobre el
último snapshot de cada una) con sus pesos lado a lado — es **informativa**: como la
decisión es por RFC, esos proveedores comparten decisión.

---

## Las 4 banderas de actividad

| # | Bandera | Señal | Tipo |
|---|---|---|---|
| 1 | `HAS_BACKORDER` | Orden de compra viva (líneas no cerradas/canceladas con cantidad pendiente) | **Firme** |
| 2 | `HAS_RECEPT` | Recepción en los últimos 12 meses (`PRH_HIST`) | **Firme** |
| 3 | `HAS_PENDING` | Pago pendiente (cuentas por pagar abiertas) | **Firme** |
| 4 | `HAS_VOUCHER` | Voucher desde 2025-08-01 (`AP_D_VO_##_A_ST_SAP`) | Blanda |

- **`PESO_ACTIVIDAD`** = suma plana de las 4 banderas (0..4), sin ponderación — mismo
  modelo que materiales. `0` = sin actividad = candidato a DESCARTAR.
- **`BANDERAS_HASH`** = huella de 4 dígitos en orden fijo `BACKORDER · RECEPT · PENDING ·
  VOUCHER` (p. ej. `1010`). Se guarda al decidir (`HASH_AL_DECIDIR`) y sirve para detectar
  cambios reales entre corridas.
- **Sugerencia** en el Excel: `MIGRAR` si `PESO_ACTIVIDAD > 0`, si no `DESCARTAR`.

**Diferencias vs materiales:**

1. La vista de depuración trae **TODOS** los proveedores de la sociedad (con o sin señal);
   en materiales solo entran los que tienen señal. Los de peso 0 son el universo a depurar.
2. **RSS no tiene fuente de vouchers SAP** en el servidor (solo existe la tabla de ST),
   por lo que en RSS `HAS_VOUCHER = 0` siempre y su hash termina en `0`. Las 3 firmes sí
   aplican en ambas sociedades.

---

## Objetos Oracle

Todos en el servidor **ERP-PROD** (`oracle-host.example / ORCLPDB1`), esquema `QAD`:

| Objeto | Tipo | Qué es |
|---|---|---|
| `V_GD_PROV_DEP_ST` / `V_GD_PROV_DEP_RSS` | Vista | Depuración por sociedad: 1 fila por RFC con banderas, montos 2025, OC vivas y datos de contacto/dirección (`sql/20`) |
| `GD_SNAPSHOT_PROVEEDORES` | Tabla | Fotos inmutables; PK `(RUN_ID, DOMINIO, RFC)` |
| `GD_DECISIONES_PROVEEDORES` | Tabla | Decisión humana; PK `RFC`; `ESTADO ∈ {MIGRAR, DESCARTAR, PENDIENTE}`, `RAZON` obligatoria si no es PENDIENTE |
| `V_GD_PROV_MERGE` | Vista | Reconciliación (buckets) sobre el último snapshot (`sql/21`) |
| `V_GD_PROV_SALIO` | Vista | Decisiones concluyentes cuyo RFC ya no aparece en el último snapshot |
| `V_GD_PROV_SAP_AVANCE` | Vista | Observación SAP: cruce contra `XXVEND_PROVEEDORES` por RFC |
| `V_GD_PROV_DUP_ST_RSS` | Vista | RFC duplicados entre ST y RSS (informativa) |

> **No existe vista unificada** `V_GD_PROV_DEP` con `SELECT * ... UNION ALL`: Oracle falla
> (ORA-00942) al expandir `*` porque las vistas exponen atributos de tipo objeto
> (`QAD.fnObtenerDireccion(...).calle`). Por eso la foto lee **cada vista por sociedad**
> (`gd/proveedores/proceso.py` → `VISTA_POR_DOMINIO`). Las tablas se crean solas desde la
> app la primera vez que se corre la foto (`crear_estructura`).

---

## Reconciliación: los buckets

Misma mecánica de 4 buckets que materiales, calculada en `V_GD_PROV_MERGE`:

| Bucket | Cuándo |
|---|---|
| `POR_DECIDIR` | Sin decisión previa, o decisión `PENDIENTE` |
| `VIGENTE` | Hash actual = hash al decidir (nada cambió), o cambió pero sin disparador |
| `RE_REVISAR` | La decisión previa quedó en duda (ver disparadores) |
| SALIÓ (`V_GD_PROV_SALIO`) | Decidido MIGRAR/DESCARTAR pero el RFC ya no está en el último snapshot; si era MIGRAR → `ATENCION = REVISAR` |

**Disparadores de RE_REVISAR** (solo cuentan las banderas **firmes**; la blanda VOUCHER
nunca dispara re-revisión por sí sola):

- **A)** `DESCARTAR → POSIBLE_MIGRAR`: se **prende** (0→1) alguna firme que estaba apagada
  al decidir.
- **B)** `MIGRAR → POSIBLE_DESCARTAR`: se **apagan TODAS** las firmes.

La columna `MOTIVO` trae el disparador y `FLAGS_CAMBIADOS` el detalle legible
(p. ej. `+BACKORDER -RECEPT`).

---

## Observación SAP (avance de carga)

`V_GD_PROV_SAP_AVANCE` cruza el último snapshot contra `QAD.XXVEND_PROVEEDORES`
(por RFC = `XXVEND_TAX_ID1`):

- **"Ya es BP"** = el RFC existe en `XXVEND_PROVEEDORES` (la tabla trae los Business
  Partner ya creados en SAP).
- `XXVEND__CHR03` = lista (separada por comas) de sociedades FI donde el BP ya está
  **extendido**. **`1200` es la sociedad FI de ST** → si no aparece, falta extenderlo.

| `ESTADO_SAP` | Significado |
|---|---|
| `MIGRADO_EXTENDIDO_1200` | Ya es BP y ya está extendido a FI 1200 — completo |
| `MIGRADO_FALTA_EXTENDER_1200` | Ya es BP pero **falta extenderlo** a FI 1200 (ST) |
| `POR_CREAR` | Decidido MIGRAR y aún no es BP |
| `DESCARTADO_OK` | Decidido DESCARTAR y no es BP — consistente |
| `CONTRADICCION` | **Alerta:** es BP en SAP pero se decidió DESCARTAR |
| `PENDIENTE` | Sin decisión y no es BP |

Consecuencia operativa: los proveedores que **ya son BP no aparecen en el Excel de
captura** — su destino ya es MIGRAR de facto; lo único pendiente es la extensión a FI 1200.

---

## Flujo en la app

Mismo ciclo que materiales, desde la sección de **Proveedores** del dashboard:

```
V_GD_PROV_DEP_ST/RSS → ① FOTO (snapshot por sociedad) → ② MERGE (buckets)
   → ③ EXCEL por sociedad (POR_DECIDIR + RE_REVISAR) → ④ se captura ESTADO/RAZON
   → ⑤ IMPORTADOR hace UPSERT por RFC en GD_DECISIONES_PROVEEDORES → (repetir)
```

| Paso | Código | Notas |
|---|---|---|
| Foto | `gd/proveedores/proceso.py` | `RUN_ID = RUN_PROV_{SOCIEDAD}_{fecha-hora}`; crea las tablas si faltan |
| Monitoreo | `gd/proveedores/datos.py` | KPIs por sociedad, buckets, SALIÓ, observación SAP y duplicados ST/RSS |
| Excel de captura | `gd/proveedores/exportador.py` | `entregables/decisiones_PROV_{SOC}_{RUN_ID}_para_captura.xlsx` |
| Importación | `gd/proveedores/importar.py` | Valida hoja/columnas, `ESTADO` y `RAZON`; MERGE por RFC |

**El Excel de captura** sigue el formato del de materiales: hoja `Decisiones` protegida
con columnas grises de contexto (banderas, montos MXN/USD 2025, OC vivas, decisión previa,
`FLAGS_CAMBIADOS`), la sugerencia en amarillo y solo las columnas verdes editables
(`ESTADO` con lista MIGRAR/DESCARTAR/PENDIENTE, `RAZON` con catálogo propio de proveedores,
`COMENTARIO` libre). Las columnas de control (`DOMINIO`, `RUN_ID_AL_DECIDIR`,
`HASH_AL_DECIDIR`) van ocultas y permiten auditar contra qué foto se decidió.

---

## Reaplicar la base (solo si cambia la lógica)

Los objetos ya existen. Si se modifica la lógica, reaplicar en orden:

1. `sql/20_proveedores_dep.sql` — vistas de depuración ST/RSS + duplicados.
2. `sql/21_proveedores_merge_sap.sql` — merge (buckets), SALIÓ y observación SAP.

Las tablas (`GD_SNAPSHOT_PROVEEDORES`, `GD_DECISIONES_PROVEEDORES`) no se tocan al
reaplicar vistas; las crea la app si faltan. La foto se corre desde el dashboard.
