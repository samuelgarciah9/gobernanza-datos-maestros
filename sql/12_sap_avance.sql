--------------------------------------------------------------------------------
-- PASO 7  |  AVANCE / RECONCILIACION DE CARGA A SAP
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
--
-- Mide DOS cosas complementarias sobre CADA material del universo maestro:
--   1) COBERTURA  : que tanto del universo ya esta cargado en SAP PRD.
--   2) CUMPLIMIENTO: de lo que se DECIDIO migrar, cuanto esta efectivamente en SAP.
--
-- RENDIMIENTO (2026-07-13): la vista QAD.SAP_MAESTRO_MATERIALES_GENERAL es CARA
--   (~27s: DISTINCT sobre PT_MSTR + fnGetSAPPartGroup por fila + vista AUX que
--   agrega 8 tablas). El dashboard la consultaba 2-3 veces por carga (>80s).
--   Solucion: se CACHEA el universo maestro en GD_SAP_MAESTRO_CACHE (tabla, ~5k
--   filas, cambia lento). El cruce con decisiones/carga (que cambian seguido) queda
--   EN VIVO. La cache se refresca al 'correr foto' (gd/proceso.py) o con
--   refrescar_cache_maestro(). Ver sql: la tabla se crea/rellena desde Python.
--
-- Fuentes:
--   - Universo    : GD_SAP_MAESTRO_CACHE (cache de SAP_MAESTRO_MATERIALES_GENERAL).
--   - Mapeo SAP   : QAD.XXPTSAP_MSTR. NO es registro de carga -- es CLON one-shot de
--                   PT_MSTR. La carga real a PRD va en XXPTSAP__CHR01 (numero final):
--                     numero real   = cargado en PRD
--                     'INDEFINIDO'  = decidido migrar, AUN sin cargar (sin numero)
--                     vacio         = sin marcar
--   - Decision    : GD_DECISIONES_MATERIALES (capa de gobernanza).
--
-- Llaves: todas en MAYUSCULAS por construccion (vistas base y cache las emiten
--   UPPER; snapshot/decisiones/xxptsap ya estan en mayusculas). Por eso los JOINS
--   NO usan UPPER() -> pueden usar indices (critico para el rendimiento).
--
-- ESTADO_MAPEO: REAL / INDEFINIDO / SIN_MARCAR / FUERA_DEL_CLON.
-- ESTADO_SAP  : CARGADO_OK / CARGADO_SIN_DECISION / CONTRADICCION / POR_CARGAR /
--               DESCARTADO_OK / PENDIENTE  ("en SAP" = ESTADO_MAPEO REAL).
--------------------------------------------------------------------------------


--==============================================================================
-- 0) CACHE DEL UNIVERSO MAESTRO  (tabla; se rellena/refresca desde Python)
--    Se documenta aqui el contrato; la creacion vive en gd/proceso.py
--    (refrescar_cache_maestro) para poder recrearla con un TRUNCATE+INSERT.
--
--    CREATE TABLE GD_SAP_MAESTRO_CACHE (
--       NUMERO_PRODUCTO_ANTIGUO VARCHAR2(30),
--       PT_DOMAIN               VARCHAR2(8),
--       PT_PROD_LINE            VARCHAR2(30),
--       DESCRIPCION             VARCHAR2(200));
--    CREATE INDEX IX_GD_MAESTRO_CACHE_PART ON GD_SAP_MAESTRO_CACHE (NUMERO_PRODUCTO_ANTIGUO);
--==============================================================================


--==============================================================================
-- 1) VISTA DE AVANCE  -  una fila por material del universo (cache) maestro
--==============================================================================
CREATE OR REPLACE VIEW V_GD_SAP_AVANCE AS
WITH clon AS (
   SELECT XXPTSAP_PART AS PT_PART,
          MAX (CASE WHEN TRIM (XXPTSAP__CHR01) IS NOT NULL
                     AND UPPER (TRIM (XXPTSAP__CHR01)) <> 'INDEFINIDO'
                    THEN TRIM (XXPTSAP__CHR01) END) AS NUMERO_SAP,
          MAX (CASE WHEN UPPER (TRIM (XXPTSAP__CHR01)) = 'INDEFINIDO'
                    THEN 1 ELSE 0 END) AS MARCADO_INDEFINIDO
     FROM QAD.XXPTSAP_MSTR
    GROUP BY XXPTSAP_PART
)
SELECT g.NUMERO_PRODUCTO_ANTIGUO,
       g.PT_DOMAIN,
       CASE WHEN UPPER (g.PT_PROD_LINE) = 'REF' THEN 'NO_PRODUCTIVO' ELSE 'PRODUCTIVO' END AS FIGURA,
       g.DESCRIPCION,
       c.NUMERO_SAP,
       CASE
          WHEN c.NUMERO_SAP IS NOT NULL   THEN 'REAL'
          WHEN c.MARCADO_INDEFINIDO = 1   THEN 'INDEFINIDO'
          WHEN c.PT_PART IS NOT NULL      THEN 'SIN_MARCAR'
          ELSE 'FUERA_DEL_CLON'
       END AS ESTADO_MAPEO,
       CASE WHEN c.PT_PART IS NOT NULL THEN 1 ELSE 0 END AS EN_CLON,
       CASE WHEN c.NUMERO_SAP IS NOT NULL THEN 1 ELSE 0 END AS EN_SAP,
       d.ESTADO AS DECISION,
       CASE
          WHEN c.NUMERO_SAP IS NOT NULL AND d.ESTADO = 'MIGRAR'    THEN 'CARGADO_OK'
          WHEN c.NUMERO_SAP IS NOT NULL AND d.ESTADO = 'DESCARTAR' THEN 'CONTRADICCION'
          WHEN c.NUMERO_SAP IS NOT NULL                            THEN 'CARGADO_SIN_DECISION'
          WHEN d.ESTADO = 'MIGRAR'                                 THEN 'POR_CARGAR'
          WHEN d.ESTADO = 'DESCARTAR'                              THEN 'DESCARTADO_OK'
          ELSE 'PENDIENTE'
       END AS ESTADO_SAP
  FROM GD_SAP_MAESTRO_CACHE g
       LEFT JOIN clon c
              ON c.PT_PART = g.NUMERO_PRODUCTO_ANTIGUO
       LEFT JOIN GD_DECISIONES_MATERIALES d
              ON d.NUMERO_PRODUCTO_ANTIGUO = g.NUMERO_PRODUCTO_ANTIGUO
             AND d.PT_DOMAIN = g.PT_DOMAIN;


--==============================================================================
-- 2) VISTA HUERFANOS  -  MAPEADO (numero real o INDEFINIDO) pero FUERA del universo
--==============================================================================
CREATE OR REPLACE VIEW V_GD_SAP_HUERFANOS AS
SELECT s.XXPTSAP_PART   AS NUMERO_PRODUCTO_ANTIGUO,
       s.XXPTSAP_DOMAIN AS PT_DOMAIN,
       s.XXPTSAP_DESC1  AS DESCRIPCION,
       CASE WHEN UPPER (TRIM (s.XXPTSAP__CHR01)) = 'INDEFINIDO'
            THEN 'INDEFINIDO' ELSE 'REAL' END AS ESTADO_MAPEO,
       CASE WHEN UPPER (TRIM (s.XXPTSAP__CHR01)) <> 'INDEFINIDO'
            THEN TRIM (s.XXPTSAP__CHR01) END AS NUMERO_SAP
  FROM QAD.XXPTSAP_MSTR s
 WHERE TRIM (s.XXPTSAP__CHR01) IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM GD_SAP_MAESTRO_CACHE g
                    WHERE g.NUMERO_PRODUCTO_ANTIGUO = s.XXPTSAP_PART);
