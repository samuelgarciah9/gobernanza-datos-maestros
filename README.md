# Gobernanza de Datos Maestros — Depuración de materiales (migración SAP S/4HANA)

> **Copia de portafolio (anonimizada).** Proyecto real desarrollado en un entorno
> corporativo, publicado aquí con fines de portafolio. Se han removido credenciales,
> identificadores de infraestructura (host/SID/servidor reales), el nombre de la empresa
> y todo dato de negocio. No incluye datos reales ni el archivo `.env`; los ejemplos de
> conexión usan valores ficticios (`oracle-host.example`). El código y el diseño son
> representativos del trabajo original.

Proceso para decidir, de forma **gobernada, auditable y repetible**, qué materiales se
migran a SAP. Separa la **foto de datos** (snapshot inmutable) de la **decisión humana**,
de modo que las decisiones sobreviven a nuevas corridas y el sistema solo pide re-revisar
lo que **cambió de verdad**.

Servidor: Oracle QAD **ERP-PROD** (`oracle-host.example / ORCLPDB1`), esquema `QAD`.

La aplicación es de **escritorio (PySide6/Qt)**: un solo ejecutable con dos ventanas.

---

## Las dos herramientas

| Quién | Ventana | Cómo se abre |
|---|---|---|
| **Equipo de datos maestros** | Dashboard (operar + monitorear) | acceso directo **"Dashboard Gobernanza"** |
| **Figuras que analizan** | Importador (cargar decisiones) | acceso directo **"Importador de Decisiones"** |

Los accesos directos los crea el **instalador** (`Setup.exe`). El usuario final no necesita
Python ni configurar nada. Para desarrollo: `python run.py dashboard` / `python run.py importador`
(o los `.bat` de la raíz).

---

## Estructura

```
Gobernanza de Datos/
├── run.py                     ← punto de entrada (elige ventana por argumento)
├── requirements.txt           ← dependencias (oracledb, PySide6, openpyxl, dotenv)
├── .env / .env.example        ← credenciales Oracle (cuenta dedicada)
│
├── gd/                        ← código de la app
│   ├── conexion.py               conexión Oracle (Thick), consciente de PyInstaller
│   ├── datos.py                  consultas de monitoreo (buckets / avance / SALIÓ)
│   ├── exportador.py             genera los Excel de captura por figura
│   ├── importar.py               lee el Excel lleno y hace UPSERT de decisiones
│   ├── proceso.py                corre la foto (snapshot)
│   ├── reporte.py                reporte de avance en Excel
│   ├── proveedores/              módulo de PROVEEDORES (ver docs/PROVEEDORES.md)
│   │   ├── proceso.py               foto por sociedad (ST/RSS)
│   │   ├── datos.py                  monitoreo (buckets / SAP / duplicados)
│   │   ├── exportador.py             Excel de captura por sociedad
│   │   └── importar.py               UPSERT de decisiones por RFC
│   └── ui/                       interfaz Qt
│       ├── estilo.py                paleta + QSS (look azul)
│       ├── widgets.py               tarjeta, KPI, barra medidor
│       ├── dashboard.py             ventana del dashboard
│       ├── importador.py            ventana del importador
│       └── tarea.py                 worker en hilo
│
├── build/                     ← empaquetado
│   ├── GobernanzaDatosMaestros.spec   PyInstaller (onedir)
│   ├── installer_common.iss           Inno Setup (cuerpo compartido)
│   ├── installer_gobernanza.iss       instalador Dashboard (gobernanza)
│   ├── installer_registro.iss         instalador Importador (figuras)
│   ├── build_installer.ps1            build en un paso (los DOS instaladores)
│   └── installer_output/              Setup.exe generados
│
├── sql/                       ← DDL y vistas (referencia; el runtime no las lee)
├── docs/                      ← BUILD.md, INSTALACION.md, contexto, mockups
├── entregables/               ← salidas (Excel de captura, reportes)
└── legacy/                    ← versiones Streamlit anteriores (archivadas)
```

---

## El proceso (resumen)

```
QUERY DEPURADOR (Oracle) → ① SNAPSHOT (foto) → ② RECONCILIACIÓN (buckets)
   → ③ EXCEL por figura → ④ la figura decide → ⑤ IMPORTADOR carga a la tabla → (repetir)
```

**4 buckets:** POR_DECIDIR · VIGENTE · RE_REVISAR (con MOTIVO) · SALIÓ.
El Excel de captura solo muestra POR_DECIDIR y RE_REVISAR.

**Estados de decisión:** `MIGRAR`, `DESCARTAR` (concluyentes) y `PENDIENTE` (sin decidir).

**Figuras:** `PT_PROD_LINE = 'REF'` → NO PRODUCTIVO; el resto → PRODUCTIVO.

---

## Módulo de proveedores

El mismo modelo (foto + decisión + buckets + Excel round-trip) aplicado al maestro de
**proveedores**, con llave natural = **RFC** (decisión única aunque el proveedor exista en
ST y RSS), 4 banderas de actividad y observación del avance en SAP (BP / extensión a la
sociedad FI 1200). Detalle completo en **`docs/PROVEEDORES.md`**; SQL en `sql/20` y `sql/21`.

---

## Instalar / distribuir

- **Generar los instaladores:** ver **`docs/BUILD.md`** (`build\build_installer.ps1`).
  Un solo build (mismo `.exe`, dos modos) produce **dos instaladores** según el rol:
  - `Instalar Gobernanza de Datos Maestros 1.0.1.exe` → **equipo de gobernanza**; instala
    solo el **Dashboard** (foto/excels/reporte).
  - `Instalar Registro de Avance - Gobernanza de Datos 1.0.1.exe` → **figuras** que solo
    registran su avance; instala solo el **Importador de Decisiones**.
- Cada uno tiene su propio `AppId` y carpeta, así que conviven en la misma máquina y se
  desinstalan por separado. Ambos (~71 MB) incluyen Instant Client y `.env` — **solo canales
  internos**. El usuario lo ejecuta y listo (sin Python, sin configurar Oracle).

## Reaplicar la base (solo si cambia la lógica)

Los objetos Oracle ya existen. Si se modifica la lógica, reaplicar en orden los scripts de
`sql/`: `00` (vista AUX) → `01` (universo maestro) → `02` (vistas de depuración) → `06`
(tabla de decisiones) → `10` (vistas de merge) → `12` (avance SAP). La foto se corre desde
el dashboard (botón "Correr foto").

Regla de comparación: **todo cruce de texto es case-insensitive** (`UPPER` en ambos lados);
las llaves (`NUMERO_PRODUCTO_ANTIGUO`, `PT_DOMAIN`) salen SIEMPRE en mayúsculas desde las
vistas base ('a' y 'A' cuentan igual como activo en `PT_STATUS`).
