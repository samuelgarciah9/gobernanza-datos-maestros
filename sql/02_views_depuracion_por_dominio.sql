--------------------------------------------------------------------------------
-- DEPURACION POR DOMINIO (ST y RSS por separado) + DUPLICADOS ENTRE ESPECIALIDADES
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
--
-- Objetivo : La migracion de ST y RSS se analiza POR SEPARADO. Por eso, a
--            diferencia del query general (que colapsa dominios y se queda con
--            el "ganador"), aqui se conserva UNA fila por material EN CADA dominio.
--
-- Cambio clave vs. query original:
--   ROW_NUMBER() PARTITION BY NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN
--   (antes solo por NUMERO_PRODUCTO_ANTIGUO -> escondia los cruces ST<->RSS)
--
-- Vistas que se crean:
--   V_GD_MATERIALES_DEP        -> base: 1 fila por (material, dominio) para ST y RSS
--   V_GD_MATERIALES_ST         -> depuracion del dominio ST
--   V_GD_MATERIALES_RSS        -> depuracion del dominio RSS
--   V_GD_MATERIALES_DUP_ST_RSS -> materiales que existen en AMBOS (comparativa)
--------------------------------------------------------------------------------


--==============================================================================
-- 1) VISTA BASE  -  una fila por (material, dominio) para ST y RSS
--    Incluye PESO_ACTIVIDAD (score ponderado de vida), DIAS_SIN_MOVIMIENTO y
--    BANDERAS_HASH (huella de estado).
--==============================================================================
CREATE OR REPLACE VIEW V_GD_MATERIALES_DEP AS
SELECT "NUMERO_PRODUCTO",
       "CLASE_PRODUCTO",
       "CATEGORIA_PRODUCTO",
       "GRUPO_PRODUCTO",
       "PT_PROD_LINE",
       "PT_GROUP",
       "PT_PART_TYPE",
       "PT_DRAW",
       "PT_DSGN_GRP",
       "RO_MCH",
       "PT_PROMO",
       "PROYECTO",
       "REVISION",
       "REVISION_INTERNA",
       "CL_CLIENTE",
       "DE_CLIENTE",
       "CL_PARTE_CLIENTE",
       "RAMO",
       "DESCRIPCION",
       "CODIGO_IDIOMA",
       "UNIDAD_MEDIDA_BASE",
       "NUMERO_PRODUCTO_ANTIGUO",
       "JERARQUIA_PRODUCTO",
       "PT_SHIP_WT",
       "PESO_BRUTO",
       "PESO_NETO",
       "UNIDAD_PESO_ISO",
       "INDICADOR_ABC",
       "GRUPO_COMPRA",
       "FUENTE_APROVISIONAMIENTO",
       "NUM_PRODUCTO",
       "EXIST_TOTAL",
       "ULTIMA_TRANSACCION",
       "ULTIMO_TIPO_TXN",
       "DIAS_SIN_MOVIMIENTO",
       "HAS_EXIST",
       "HAS_DIST",
       "HAS_PO",
       "HAS_SO",
       "HAS_WO",
       "HAS_RET",
       "HAS_INV_SEG",
       "HAS_ULT_TXN",
       -- PESO_ACTIVIDAD: numero de senales de actividad (0..8). Cada bandera vale 1,
       --   SIN pesos (todas cuentan igual). 0 = sin ninguna senal = candidato a DESCARTE.
       NVL (  "HAS_EXIST" + "HAS_DIST" + "HAS_PO" + "HAS_SO"
            + "HAS_WO" + "HAS_RET" + "HAS_INV_SEG" + "HAS_ULT_TXN", 0)  AS PESO_ACTIVIDAD,
       -- Huella del estado (mismo orden fijo que la tabla snapshot)
          TO_CHAR ("HAS_EXIST")   || TO_CHAR ("HAS_DIST")
       || TO_CHAR ("HAS_PO")      || TO_CHAR ("HAS_SO")
       || TO_CHAR ("HAS_WO")      || TO_CHAR ("HAS_RET")
       || TO_CHAR ("HAS_INV_SEG") || TO_CHAR ("HAS_ULT_TXN")           AS BANDERAS_HASH,
       "PT_DOMAIN",
       "PT_SITE"
  FROM (SELECT A.*,
               ROW_NUMBER ()
                  OVER (PARTITION BY A.NUMERO_PRODUCTO_ANTIGUO, A.PT_DOMAIN   -- <<< clave del cambio
                        ORDER BY A.NUMERO_PRODUCTO_ANTIGUO)   AS RN_FINAL
          FROM (SELECT DISTINCT
                       UPPER (PT_PART) AS NUMERO_PRODUCTO,          -- llaves SIEMPRE en mayusculas
                       ' ' AS CLASE_PRODUCTO,
                       ' ' AS CATEGORIA_PRODUCTO,
                       QAD.fnGetSAPPartGroup (PT_PROD_LINE, PT_GROUP, PT_PART_TYPE, PT_DOMAIN) AS GRUPO_PRODUCTO,
                       PT_PROD_LINE,
                       EXIST_TOTAL,
                       ULTIMA_TRANSACCION,
                       ULTIMO_TIPO_TXN,
                       DIAS_SIN_MOVIMIENTO,
                       HAS_EXIST, HAS_DIST, HAS_PO, HAS_SO, HAS_WO, HAS_RET, HAS_INV_SEG, HAS_ULT_TXN,
                       PT_GROUP, PT_PART_TYPE, PT_DRAW, PT_DSGN_GRP, RO_MCH,
                       CASE WHEN UPPER (PT_DOMAIN) = 'ST' THEN PT_BUYER END PROYECTO,
                       CASE WHEN UPPER (PT_DOMAIN) = 'ST' THEN PT_REV   END REVISION,
                       CL_CLIENTE, DE_CLIENTE, CL_PARTE_CLIENTE,
                       XXCRRF_AUT01 AS REVISION_INTERNA,
                       PT_PROMO,
                       ' ' AS RAMO,
                       PT_DESC1 || ' ' || PT_DESC2 AS DESCRIPCION,
                       'ES' AS CODIGO_IDIOMA,
                       UPPER (PT_UM) AS UNIDAD_MEDIDA_BASE,
                       UPPER (PT_PART) AS NUMERO_PRODUCTO_ANTIGUO,
                       PT_PART_TYPE AS JERARQUIA_PRODUCTO,
                       A.PT_SHIP_WT,
                       CASE WHEN UPPER (PT_UM) = 'PZ' AND UPPER (UM_ALT_UM) = 'KG' THEN ROUND ((1 / UM_CONV), 3)
                            WHEN UPPER (PT_UM) = 'KG' AND UPPER (UM_ALT_UM) = 'PZ' THEN ROUND (UM_CONV, 3)
                       END AS PESO_BRUTO,
                       CASE WHEN UPPER (PT_UM) = 'PZ' AND UPPER (UM_ALT_UM) = 'KG' THEN ROUND ((1 / UM_CONV), 3)
                            WHEN UPPER (PT_UM) = 'KG' AND UPPER (UM_ALT_UM) = 'PZ' THEN ROUND (UM_CONV, 3)
                       END AS PESO_NETO,
                       A.PT_SHIP_WT_UM AS UNIDAD_PESO_ISO,
                       UPPER (IN_ABC) AS INDICADOR_ABC,
                       ' ' AS GRUPO_COMPRA,
                       UPPER (PT_PM_CODE) AS FUENTE_APROVISIONAMIENTO,
                       UPPER (PT_PART) AS NUM_PRODUCTO,
                       UPPER (PT_DOMAIN) AS PT_DOMAIN,
                       PT_SITE
                  FROM PT_MSTR A
                       LEFT JOIN UM_MSTR
                          ON     UPPER (PT_PART) = UPPER (UM_PART)
                             AND UPPER (PT_DOMAIN) = UPPER (UM_DOMAIN)
                             AND UPPER (PT_UM) = UPPER (UM_UM)
                       INNER JOIN SAP_AUX_CODIGOS_OBSOLETOS AUX
                          ON     UPPER (A.PT_PART) = AUX.PT_PART      -- AUX ya viene en mayusculas
                             AND UPPER (A.PT_DOMAIN) = AUX.PT_DOMAIN
                             AND (   AUX.HAS_EXIST = 1 OR AUX.HAS_DIST = 1
                                  OR AUX.HAS_PO = 1    OR AUX.HAS_SO = 1
                                  OR AUX.HAS_WO = 1    OR AUX.HAS_RET = 1
                                  OR AUX.HAS_INV_SEG = 1 OR AUX.HAS_ULT_TXN = 1)
                       LEFT JOIN IN_MSTR
                          ON     UPPER (PT_PART) = UPPER (IN_PART)
                             AND UPPER (PT_DOMAIN) = UPPER (IN_DOMAIN)
                             AND UPPER (PT_SITE) = UPPER (IN_SITE)
                       LEFT JOIN QAD.RO_DET
                          ON     UPPER (A.PT_PART) = UPPER (RO_ROUTING)
                             AND UPPER (RO_DOMAIN) = UPPER (A.PT_DOMAIN)
                       LEFT JOIN QAD.xxcrrf_Det
                          ON     UPPER (xxcrrf_part) = UPPER (A.PT_PART)
                             AND UPPER (xxcrrf_domain) = 'ST'
                             AND UPPER (xxcrrf_type) = 'PT-DATA'
                       LEFT JOIN (SELECT UPPER (cp_part) CL_ARTICULO,
                                         cp_cust AS CL_CLIENTE,
                                         UPPER (B.CM_SORT) DE_CLIENTE,
                                         cp_cust_part AS CL_PARTE_CLIENTE
                                    FROM CP_MSTR, CM_MSTR B, PT_MSTR C
                                   WHERE UPPER (CP_CUST) = UPPER (B.CM_ADDR(+))
                                         AND UPPER (cp_domain) = 'ST'
                                         AND UPPER (cm_domain(+)) = 'ST'
                                         AND UPPER (C.PT_PART(+)) = UPPER (cp_part)
                                         AND UPPER (C.PT_DOMAIN(+)) = 'ST') B
                          ON UPPER (A.pt_part) = B.CL_ARTICULO
                 WHERE UPPER (PT_STATUS) = 'A'   -- 'a' y 'A' cuentan como activo
                       AND UPPER (pt_domain) IN ('ST', 'RSS')    -- <<< solo las dos especialidades
               ) A)
 WHERE RN_FINAL = 1;


--==============================================================================
-- 2) DEPURACION DOMINIO ST  (analisis independiente)
--==============================================================================
CREATE OR REPLACE VIEW V_GD_MATERIALES_ST AS
SELECT *
  FROM V_GD_MATERIALES_DEP
 WHERE PT_DOMAIN = 'ST';


--==============================================================================
-- 3) DEPURACION DOMINIO RSS  (analisis independiente)
--==============================================================================
CREATE OR REPLACE VIEW V_GD_MATERIALES_RSS AS
SELECT *
  FROM V_GD_MATERIALES_DEP
 WHERE PT_DOMAIN = 'RSS';


--==============================================================================
-- 4) DUPLICADOS ENTRE ESPECIALIDADES  (material presente en ST **y** en RSS)
--    Comparativa lado a lado -> ayuda a decidir cual dominio migra cada material.
--    El INNER JOIN por NUMERO_PRODUCTO_ANTIGUO deja SOLO los que estan en ambos.
--==============================================================================
CREATE OR REPLACE VIEW V_GD_MATERIALES_DUP_ST_RSS AS
SELECT st.NUMERO_PRODUCTO_ANTIGUO,

       -- Descripcion / linea de producto en cada dominio
       st.DESCRIPCION           AS DESCRIPCION_ST,
       rss.DESCRIPCION          AS DESCRIPCION_RSS,
       st.PT_PROD_LINE          AS PROD_LINE_ST,
       rss.PT_PROD_LINE         AS PROD_LINE_RSS,
       st.GRUPO_PRODUCTO        AS GRUPO_PROD_ST,
       rss.GRUPO_PRODUCTO       AS GRUPO_PROD_RSS,
       st.UNIDAD_MEDIDA_BASE    AS UM_ST,
       rss.UNIDAD_MEDIDA_BASE   AS UM_RSS,

       -- Estado / actividad en cada dominio
       st.EXIST_TOTAL           AS EXIST_ST,
       rss.EXIST_TOTAL          AS EXIST_RSS,
       st.ULTIMA_TRANSACCION    AS ULT_TXN_ST,
       rss.ULTIMA_TRANSACCION   AS ULT_TXN_RSS,
       st.PESO_ACTIVIDAD        AS ACTIVIDAD_ST,   -- score ponderado (0 = sin actividad)
       rss.PESO_ACTIVIDAD       AS ACTIVIDAD_RSS,
       st.BANDERAS_HASH         AS HASH_ST,
       rss.BANDERAS_HASH        AS HASH_RSS,

       -- Sugerencia de dominio con mas actividad (apoyo a la decision, no la sustituye)
       CASE
          WHEN st.PESO_ACTIVIDAD >  rss.PESO_ACTIVIDAD THEN 'ST'
          WHEN rss.PESO_ACTIVIDAD > st.PESO_ACTIVIDAD  THEN 'RSS'
          WHEN st.PESO_ACTIVIDAD = rss.PESO_ACTIVIDAD AND st.PESO_ACTIVIDAD > 0 THEN 'AMBOS_ACTIVOS'
          ELSE 'REVISAR'
       END                       AS DOMINIO_MAS_ACTIVO
  FROM V_GD_MATERIALES_ST  st
       INNER JOIN V_GD_MATERIALES_RSS rss
          ON st.NUMERO_PRODUCTO_ANTIGUO = rss.NUMERO_PRODUCTO_ANTIGUO;


--==============================================================================
-- 5) VERIFICACION / RESUMEN
--==============================================================================

-- 5.1  Conteo de materiales depurados por dominio
SELECT PT_DOMAIN, COUNT(*) AS MATERIALES
  FROM V_GD_MATERIALES_DEP
 GROUP BY PT_DOMAIN
 ORDER BY PT_DOMAIN;

-- 5.2  ¿Cuantos materiales estan duplicados entre ST y RSS?
SELECT COUNT(*) AS MATERIALES_EN_AMBOS
  FROM V_GD_MATERIALES_DUP_ST_RSS;

-- 5.3  Materiales UNICOS de ST (no estan en RSS)
SELECT COUNT(*) AS SOLO_ST
  FROM V_GD_MATERIALES_ST st
 WHERE NOT EXISTS (SELECT 1 FROM V_GD_MATERIALES_RSS rss
                    WHERE rss.NUMERO_PRODUCTO_ANTIGUO = st.NUMERO_PRODUCTO_ANTIGUO);

-- 5.4  Materiales UNICOS de RSS (no estan en ST)
SELECT COUNT(*) AS SOLO_RSS
  FROM V_GD_MATERIALES_RSS rss
 WHERE NOT EXISTS (SELECT 1 FROM V_GD_MATERIALES_ST st
                    WHERE st.NUMERO_PRODUCTO_ANTIGUO = rss.NUMERO_PRODUCTO_ANTIGUO);

-- 5.5  Salud: la clave (material, dominio) debe ser unica en la base (debe dar 0 filas)
SELECT NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN, COUNT(*)
  FROM V_GD_MATERIALES_DEP
 GROUP BY NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN
HAVING COUNT(*) > 1;
