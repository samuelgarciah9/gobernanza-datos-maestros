# Gobernanza de Datos Maestros — Estrategia de Depuración para Migración SAP

> **Documento de contexto para reanudar en Claude Code (CLI).**
> Proyecto: rediseño del proceso de depuración de materiales para la migración a SAP S/4HANA (MM/EWM). Empresa: anonimizada (manufactura). Sistema legado: QAD sobre Oracle.

---

## 1. El problema que se está resolviendo

En la primera implementación, la depuración de materiales funcionaba así:

```
Query Oracle (con banderas) → Excel → usuarios de operación seleccionan → se pierde
```

**Falla raíz:** la decisión humana (migrar/descartar) NO se persistía con trazabilidad. Vivía en Excel suelto. Consecuencias:

- Cada nueva extracción re-preguntaba TODO a los usuarios → desgaste.
- Descartes sin justificación documentada → no auditable.
- Sin forma de medir avance real hacia el Go-Live.
- **Retrabajo masivo.**

**Insight central:** el query técnico ya hace el 100% del trabajo de detección. Lo único que faltaba era **capturar y persistir la capa de decisión humana** encima de él.

**Validación con el estándar de la industria:** este enfoque corresponde a los patrones formales de migración SAP:
- Snapshot = *staging layer* (perfilar/corregir el extracto ANTES de cargar a SAP).
- Banderas = *data profiling*.
- Campo `DECIDIDO_POR`/`ROL` = *named business owners*.
- Campo `RAZON` = documentación/auditoría de exclusiones.
- El Migration Cockpit de SAP NO garantiza calidad; solo carga. La gobernanza (qué merece cargarse) es trabajo propio, y es justo lo que este diseño cubre.

---

## 2. Concepto clave: separar tres capas

| Capa | Qué es | Quién manda | Dónde debe vivir |
|---|---|---|---|
| Datos origen | Estado del material en el legado | Sistema | Snapshot congelado |
| Banderas/criterios | Resultado de reglas de depuración | El query | Calculado, versionado |
| Decisión humana | Migrar/descartar + razón | Compras/Inventarios/Ingeniería | Tabla de decisiones persistente |

**Regla de oro:** *La siguiente extracción nunca empieza de cero.* Arrastra decisiones previas y solo enruta a revisión lo nuevo o lo que cambió.

---

## 3. El flujo completo — 7 pasos

```
[1] Snapshot                     (tabla)    ✓ diseñado
[2] Tabla de decisiones          (tabla)    ✓ diseñado
[3] Merge                        (proceso)  ✓ diseñado
[4] Captura de decisiones                   ← PUNTO ACTUAL
[5] Control / tablero
[6] Carga (LTMC)
[7] Avance / reconciliación de carga a SAP  ✓ implementado
```

### Paso 1 — Tabla Snapshot

Cada corrida del query se persiste como foto inmutable. La tabla SOLO crece (append), nunca se sobrescribe.

Columnas de control que se agregan sobre la salida del query:
- `RUN_ID` — identifica la corrida (ej. `RUN_2026-06-15`).
- `RUN_TS` — timestamp de la foto.
- `BANDERAS_HASH` — huella del estado = las 8 flags concatenadas (ej. `10100001`).

Clave natural (ya existe en el query, se deduplica por ella con `ROW_NUMBER() PARTITION BY`):
- **`NUMERO_PRODUCTO_ANTIGUO` + `PT_DOMAIN`**

Llave primaria de la tabla: `RUN_ID + NUMERO_PRODUCTO_ANTIGUO + PT_DOMAIN` (un material aparece una vez por corrida).

**Las 8 banderas (ya existen en el query `SAP_AUX_CODIGOS_OBSOLETOS`):**
`HAS_EXIST`, `HAS_DIST`, `HAS_PO`, `HAS_SO`, `HAS_WO`, `HAS_RET`, `HAS_INV_SEG`, `HAS_ULT_TXN`.
En la vista general, `ES_OBSOLETO = suma de las 8 flags` (si 0 → sin actividad → candidato a descarte).

**La huella (`BANDERAS_HASH`)** es la firma del estado. Si entre dos corridas la huella es igual, el material no cambió en nada relevante. Si cambió, merece nueva revisión. Se compara UNA cadena en lugar de 8 columnas.

Prueba de que quedó bien: poder responder con un SELECT "¿cómo se veía el material X en la corrida del 15-jun?" y "¿qué huella tenía en cada foto?".

### Paso 2 — Tabla de Decisiones

Una fila POR MATERIAL (por clave natural), no por corrida. Solo cambia cuando un humano decide/cambia de opinión.

Columnas:
- `NUMERO_PRODUCTO_ANTIGUO` + `PT_DOMAIN` — clave natural (une con snapshot).
- `ESTADO` — catálogo CERRADO: `MIGRAR` / `DESCARTAR` / `ENRIQUECER` / `PENDIENTE`.
- `RAZON` — obligatoria. Híbrida: lista de razones comunes + texto libre opcional.
- `DECIDIDO_POR` — usuario (automático).
- `ROL` — área: COMPRAS / INVENTARIOS / INGENIERIA (automático).
- `FECHA_DECISION` — automático.
- `HASH_AL_DECIDIR` — la huella del snapshot al momento de decidir. **Pieza más astuta del diseño.**

De los 6 campos de una decisión, solo 2 los pone el humano (`ESTADO`, `RAZON`); los otros 4 se sellan automáticamente.

### Paso 3 — Merge (PROCESO, no tabla)

⚠️ Aclaración importante: el merge NO es una tabla. Es la lógica que se ejecuta en cada corrida cruzando snapshot vs. decisiones. No persiste.

Reparte cada material en 3 cubos:

| Caso | ¿Existe decisión previa? | ¿Huella actual = HASH_AL_DECIDIR? | Cubo | Acción |
|---|---|---|---|---|
| Nuevo | No | — | **A** | A revisión (primera vez) |
| Estable | Sí | Sí | **B** | Respetar, no molestar |
| Cambió | Sí | No | **C** | Reactivar a revisión |

**Por qué `HASH_AL_DECIDIR` lo cambia todo:** evita los dos errores opuestos:
- Preguntar de más (retrabajo): si la huella no cambió, se respeta la decisión.
- Arrastrar decisiones obsoletas (peligro silencioso): si un material descartado por "sin actividad" (`00000000`) luego recibe una PO (`00100000`), la huella difiere → Cubo C → se reactiva solo. Nadie tuvo que acordarse.

Efecto numérico (ejemplo): de 50,000 materiales, tras la 1ª corrida solo ~1,100 requieren atención humana (nuevos + cambiados), no los 50,000. Ahí muere el retrabajo.

Cierre del ciclo: cuando el usuario decide sobre un material de cubo A o C, se guarda/actualiza su fila en la tabla de decisiones con la huella actual como nuevo `HASH_AL_DECIDIR`. En la siguiente corrida cae en cubo B mientras no cambie.

### Paso 4 — Captura de decisiones ← PUNTO ACTUAL

Donde el humano convierte un pendiente (cubo A/C) en decisión registrada. Es el punto de contacto con el usuario; si es incómodo, la gente lo evade y se vuelve al Excel suelto.

**Decisiones de diseño YA tomadas:**

1. **Herramienta — enfoque en dos tiempos:**
   - **Piloto (2-3 semanas):** Excel controlado (listas desplegables, columnas bloqueadas). No porque sea bueno, sino porque obliga a definir bien estados/razones/enrutamiento con esfuerzo mínimo. Banco de pruebas barato.
   - **Operación real:** Power Apps (sobre M365 ya conectado). Blinda los 4 campos automáticos, sin bombas de versiones de archivos, filtrado por rol nativo, concurrencia sana.
   - SAP MDG se descartó por ahora: sobreingeniería/costoso para migración puntual.
   - **Error a evitar:** construir la Power App antes de validar el flujo en Excel → se rehace 2-3 veces.

2. **Estados:** catálogo CERRADO siempre (nunca texto libre para estado) → habilita el tablero del Paso 5.

3. **Razón:** híbrida (lista común + texto libre opcional).

4. **Enrutamiento por rol** — cada material lo revisa quien corresponde. Decisión tomada: **arrancar el piloto con Opción B (línea de producto `PT_PROD_LINE`, ya poblada)** y migrar a **Opción A (grupo de compras)** para operación real, que es el estándar SAP.

**Comparación Excel vs Power Apps (resumen del análisis hecho):**

| Dimensión | Excel controlado | Power Apps |
|---|---|---|
| Arranque | Horas | Días-semanas |
| Sella campos automáticos | Tú al reimportar (riesgo error) | La app, blindado |
| Riesgo manipulación | Alto | Bajo |
| Concurrencia | Caótica (versiones) | Nativa |
| Filtrado por rol | Manual | Automático |
| Trazabilidad | Frágil | Sólida |
| Carga sobre ti | Alta (eres el cartero) | Mínima |
| Escala 50k+ | Se desmorona | Aguanta |

### Paso 5 — Control / Tablero (pendiente de diseñar)

Power BI sobre la tabla de decisiones. Métricas: % resuelto por objeto/iteración, pendientes por dueño/rol, decisiones invalidadas (reactivadas por cambio de huella), velocidad de resolución (proyección a Go-Live), trazabilidad por registro. Se arma casi solo porque los estados son cerrados y cada decisión tiene rol/fecha/razón.

### Paso 6 — Carga (LTMC) (pendiente de diseñar)

Solo migran los `ESTADO = MIGRAR` aprobados → se construyen plantillas del SAP Migration Cockpit (LTMC) y se cargan a S/4HANA.

### Paso 7 — Avance / reconciliación de carga a SAP ✓ IMPLEMENTADO

Mide **lo que efectivamente ya está en SAP**, distinto de la decisión de gobernanza (Pasos 2-4). A medida que se cargan materiales, quedan registrados en **`QAD.XXPTSAP_MSTR`** (el registro de "ya cargado"; solo trae `XXPTSAP_PART` + `XXPTSAP_DOMAIN`). Esta capa cruza ese registro contra el universo maestro y contra las decisiones.

**Cruce:** por la clave natural `XXPTSAP_PART = NUMERO_PRODUCTO_ANTIGUO` (por parte sola; parte+dominio difiere en ~7 materiales). **Universo/denominador:** `QAD.SAP_MAESTRO_MATERIALES_GENERAL` (5,024 partes ST/RSS, 1 fila por parte; el snapshot NO sirve de denominador porque solo trae materiales con señal).

**Dos métricas complementarias:**
- **Cobertura** = en SAP / universo maestro. Hoy: **63.5%** (ST No-Prod 66%, ST Prod 63%, RSS 40%).
- **Cumplimiento** = MIGRAR ya en SAP / decididos MIGRAR. Hoy 0/0 porque `GD_DECISIONES_MATERIALES` está vacía → arranca a medir en cuanto fluyan decisiones.

**`ESTADO_SAP`** (matriz de reconciliación, mutuamente excluyente): `CARGADO_OK` (en SAP + MIGRAR) · `CARGADO_SIN_DECISION` · `CONTRADICCION` (en SAP + DESCARTAR → alerta) · `POR_CARGAR` (MIGRAR sin cargar) · `DESCARTADO_OK` · `PENDIENTE`.

**Implementación** (`sql/12_sap_avance.sql`, vistas ya creadas en el esquema QAD):
- `V_GD_SAP_AVANCE` — una fila por parte del universo con `EN_SAP`, `DECISION`, `ESTADO_SAP`.
- `V_GD_SAP_HUERFANOS` — en SAP pero fuera del universo maestro (1,285: incluye los 148 HOS y `PT_STATUS<>'A'`; hallazgo de auditoría por sí mismo).
- Conectado en `gd/datos.py::_cargar_sap()` → sección "Avance de carga a SAP" del dashboard + hojas `Avance/Reconciliacion/Huerfanos SAP` del reporte.

---

## 4. PENDIENTE INMEDIATO al reanudar

**Armar la tabla de mapeo `PT_PROD_LINE → área responsable`** (COMPRAS / INVENTARIOS / INGENIERIA), como plantilla para validar con los líderes de cada área. Es el insumo que destraba el Paso 4: la capa de captura la consulta para filtrar la cola de cada usuario.

Opciones de enrutamiento evaluadas:
- **A — Grupo de compras:** estándar SAP correcto, pero hoy `GRUPO_COMPRA` viene vacío y `PT_BUYER` solo se llena en dominio `ST`. Destino final.
- **B — Línea de producto (`PT_PROD_LINE`):** poblado, intuitivo por tipo de material. **Elegido para el piloto.**
- C — Dominio (ST/HOS/RSS): demasiado grueso, solo filtro previo.
- D — Combinación de banderas: sofisticado, para v2.

---

## 5. Contexto técnico del query fuente (para no perderlo)

Dos objetos Oracle en el sistema QAD:

1. **`QAD.SAP_MAESTRO_MATERIALES_GENERAL`** (vista general): produce el maestro de materiales con datos de negocio. Deduplica por `NUMERO_PRODUCTO_ANTIGUO` con `ROW_NUMBER() PARTITION BY` priorizando dominio (ST=1, RSS=2, HOS=3). Calcula `ES_OBSOLETO` como suma de las 8 flags. Filtra `PT_STATUS='A'` y dominios `ST/HOS/RSS`.

2. **`SAP_AUX_CODIGOS_OBSOLETOS`** (consulta de depuración): genera las 8 banderas HAS_* por material/dominio, cruzando:
   - `HAS_EXIST` ← IN_MSTR (existencias)
   - `HAS_DIST` ← DS_DET (distribuciones pendientes)
   - `HAS_PO` ← POD_DET (órdenes de compra abiertas)
   - `HAS_SO` ← SOD_DET (órdenes de venta pendientes)
   - `HAS_WO` ← WO_MSTR (órdenes de trabajo activas)
   - `HAS_RET` ← XXRFCRED_DET (devoluciones pendientes)
   - `HAS_INV_SEG` ← PTP_DET (inventario de seguridad)
   - `HAS_ULT_TXN` ← TR_HIST (movimiento en últimos 180 días)
   - Clave: `PT_PART` + `PT_DOMAIN`, dominios `HOS/ST/RSS`, status `A`.

3. **`QAD.XXPTSAP_MSTR`** (registro de carga a SAP, Paso 7): tabla donde se va registrando lo **ya cargado a SAP**. 4,475 filas; solo `XXPTSAP_PART` + `XXPTSAP_DOMAIN` (descripciones en blanco). Clave de cruce: `XXPTSAP_PART = NUMERO_PRODUCTO_ANTIGUO`.

---

## 6. Recomendaciones para subir de "buena improvisación" a "gobernanza defendible ante auditor"

1. **Agregar banderas de conformidad técnica** (además de las de actividad): no solo "¿se usa el material?" sino "¿cumplirá las reglas de SAP al cargarse?" (longitud de campo, UoM válida, grupo de artículos existente, etc.). Hoy las 8 flags miden actividad; falta la capa de conformidad.
2. **Usar vocabulario estándar** en la documentación: snapshot = *staging layer*; banderas = *data profiling*; cubos = *remediation routing*; dueños = *business data owners*; Paso 7 = *reconciliation*. Mismo trabajo, lenguaje de consultor.
3. Conocer (no necesariamente adoptar entero) la metodología **SAP Activate** y su fase de análisis de datos.

---

## 7. Próximos entregables candidatos (para elegir al reanudar)

- [ ] Tabla de mapeo `PT_PROD_LINE → área` (pendiente inmediato).
- [ ] DDL de las tablas snapshot + decisiones (Oracle), con la clave natural real.
- [ ] Script Python del motor de merge (snapshot nuevo vs decisiones, lógica de cubos A/B/C con `HASH_AL_DECIDIR`).
- [ ] Diseño del Paso 5 (tablero Power BI).
- [ ] Diseño del Paso 6 (carga LTMC).
- [x] Paso 7 — avance/reconciliación de carga a SAP (vistas `V_GD_SAP_*`, dashboard, reporte).
- [ ] Catálogo de banderas de conformidad técnica para MM/EWM.

---

## Stack de referencia
- **Legado:** QAD sobre Oracle.
- **Snapshot + decisiones:** Oracle (BD corporativa).
- **Motor de merge/banderas:** Python (pandas + SQLAlchemy).
- **Captura:** Excel controlado (piloto) → Power Apps (operación).
- **Tablero:** Power BI.
- **Destino:** SAP S/4HANA vía Migration Cockpit (LTMC).
- **Ecosistema disponible:** Microsoft 365 conectado.
