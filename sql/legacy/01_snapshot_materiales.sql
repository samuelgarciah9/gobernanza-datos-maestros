--------------------------------------------------------------------------------
-- PASO 1  |  TABLA SNAPSHOT DE MATERIALES  (foto inmutable, APPEND-ONLY)
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA (MM/EWM)
-- Empresa  : (anonimizada - empresa manufacturera)
-- Fuente   : Query general de materiales depurados (QAD/Oracle)
--            + auxiliar SAP_AUX_CODIGOS_OBSOLETOS (8 banderas de actividad)
--
-- Concepto : Cada corrida del query se persiste como una FOTO. La tabla solo
--            crece (INSERT), nunca se sobrescribe. La PK incluye RUN_ID para
--            que convivan todas las fotos historicas.
--
-- Clave natural REAL del material : NUMERO_PRODUCTO_ANTIGUO (= PT_PART).
--            El query ya dedupe por esta columna (una fila por material,
--            dominio ganador por prioridad ST=1, RSS=2, HOS=3).
--            PT_DOMAIN es ATRIBUTO (dominio ganador), NO parte de la clave.
--------------------------------------------------------------------------------


--==============================================================================
-- 1) DDL  -  TABLA SNAPSHOT
--==============================================================================
CREATE TABLE GD_SNAPSHOT_MATERIALES
(
   ------------------------------------------------------------------
   -- Columnas de CONTROL / GOBERNANZA  (se agregan sobre el query)
   ------------------------------------------------------------------
   RUN_ID                     VARCHAR2(30)         NOT NULL,   -- id de corrida, ej. 'RUN_2026-06-15'
   RUN_TS                     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,  -- timestamp de la foto
   BANDERAS_HASH              VARCHAR2(8)          NOT NULL,   -- 8 flags concatenadas, ej. '10100001'

   ------------------------------------------------------------------
   -- Clave natural + dominio ganador (atributo)
   ------------------------------------------------------------------
   NUMERO_PRODUCTO_ANTIGUO    VARCHAR2(30)         NOT NULL,   -- PT_PART  <- clave natural real
   PT_DOMAIN                  VARCHAR2(8)          NOT NULL,   -- dominio ganador (ST/RSS/HOS)

   ------------------------------------------------------------------
   -- Datos de negocio (salida del query; fidelidad c/ plantilla SAP)
   ------------------------------------------------------------------
   NUMERO_PRODUCTO            VARCHAR2(30),                    -- = PT_PART (redundante, se conserva)
   CLASE_PRODUCTO             VARCHAR2(10),                    -- placeholder ' '
   CATEGORIA_PRODUCTO         VARCHAR2(10),                    -- placeholder ' '
   GRUPO_PRODUCTO             VARCHAR2(30),                    -- fnGetSAPPartGroup(...)
   PT_PROD_LINE               VARCHAR2(20),                    -- linea de producto (enrutamiento piloto)
   PT_GROUP                   VARCHAR2(20),
   PT_PART_TYPE               VARCHAR2(20),
   PT_DRAW                    VARCHAR2(30),
   PT_DSGN_GRP                VARCHAR2(30),
   RO_MCH                     VARCHAR2(30),
   PT_PROMO                   VARCHAR2(10),
   PROYECTO                   VARCHAR2(30),                    -- PT_BUYER (solo dominio ST)
   REVISION                   VARCHAR2(10),                    -- PT_REV   (solo dominio ST)
   REVISION_INTERNA           VARCHAR2(30),                    -- xxcrrf_aut01
   CL_CLIENTE                 VARCHAR2(24),
   DE_CLIENTE                 VARCHAR2(30),
   CL_PARTE_CLIENTE           VARCHAR2(30),
   RAMO                       VARCHAR2(10),                    -- placeholder ' '
   DESCRIPCION                VARCHAR2(60),                    -- PT_DESC1 || ' ' || PT_DESC2
   CODIGO_IDIOMA              VARCHAR2(2),                     -- 'ES'
   UNIDAD_MEDIDA_BASE         VARCHAR2(10),                    -- UPPER(PT_UM)
   JERARQUIA_PRODUCTO         VARCHAR2(20),                    -- = PT_PART_TYPE (redundante)
   PT_SHIP_WT                 NUMBER,
   PESO_BRUTO                 NUMBER,
   PESO_NETO                  NUMBER,                          -- = PESO_BRUTO (misma formula)
   UNIDAD_PESO_ISO            VARCHAR2(10),                    -- PT_SHIP_WT_UM
   INDICADOR_ABC              VARCHAR2(4),                     -- UPPER(IN_ABC)
   GRUPO_COMPRA               VARCHAR2(10),                    -- placeholder ' ' (destino final SAP)
   FUENTE_APROVISIONAMIENTO   VARCHAR2(10),                    -- UPPER(PT_PM_CODE)
   NUM_PRODUCTO               VARCHAR2(30),                    -- = PT_PART (redundante)
   EXIST_TOTAL                NUMBER,
   ULTIMA_TRANSACCION         DATE,
   ULTIMO_TIPO_TXN            VARCHAR2(10),                    -- TR_TYPE
   PT_SITE                    VARCHAR2(8),

   ------------------------------------------------------------------
   -- Banderas de actividad (data profiling)  -  siempre 0/1
   ------------------------------------------------------------------
   HAS_EXIST                  NUMBER(1)            NOT NULL,
   HAS_DIST                   NUMBER(1)            NOT NULL,
   HAS_PO                     NUMBER(1)            NOT NULL,
   HAS_SO                     NUMBER(1)            NOT NULL,
   HAS_WO                     NUMBER(1)            NOT NULL,
   HAS_RET                    NUMBER(1)            NOT NULL,
   HAS_INV_SEG                NUMBER(1)            NOT NULL,
   HAS_ULT_TXN                NUMBER(1)            NOT NULL,
   ES_OBSOLETO                NUMBER(2)            NOT NULL,   -- suma de las 8 flags (0..8).
                                                              -- OJO semantica: 0 = SIN actividad
                                                              -- = candidato a DESCARTE. >0 = activo.

   CONSTRAINT PK_GD_SNAPSHOT_MAT
      PRIMARY KEY (RUN_ID, NUMERO_PRODUCTO_ANTIGUO)
);

-- Indices de apoyo al MERGE (Paso 3) y a las consultas del tablero
CREATE INDEX IX_GD_SNAP_PART ON GD_SNAPSHOT_MATERIALES (NUMERO_PRODUCTO_ANTIGUO);
CREATE INDEX IX_GD_SNAP_RUN  ON GD_SNAPSHOT_MATERIALES (RUN_ID);
CREATE INDEX IX_GD_SNAP_LINE ON GD_SNAPSHOT_MATERIALES (PT_PROD_LINE);  -- enrutamiento por linea

COMMENT ON TABLE  GD_SNAPSHOT_MATERIALES               IS 'Paso 1: foto inmutable (append-only) del query de materiales depurados por corrida (RUN_ID).';
COMMENT ON COLUMN GD_SNAPSHOT_MATERIALES.RUN_ID        IS 'Identificador de la corrida/foto. Ej: RUN_2026-06-15.';
COMMENT ON COLUMN GD_SNAPSHOT_MATERIALES.BANDERAS_HASH IS 'Huella del estado = 8 flags concatenadas en orden EXIST,DIST,PO,SO,WO,RET,INV_SEG,ULT_TXN.';
COMMENT ON COLUMN GD_SNAPSHOT_MATERIALES.PT_DOMAIN     IS 'Dominio ganador (ST/RSS/HOS). Atributo, NO clave: puede cambiar entre corridas.';
COMMENT ON COLUMN GD_SNAPSHOT_MATERIALES.ES_OBSOLETO   IS 'Score de actividad = suma de flags (0..8). 0 = sin actividad = candidato a descarte.';


--==============================================================================
-- 2) CARGA DE UNA CORRIDA  (INSERT ... SELECT)
--    Reemplaza &RUN_ID por el id de la foto, ej. RUN_2026-06-15.
--    (Desde Python/SQLAlchemy usar un bind param :run_id en vez de &RUN_ID.)
--
--    El BANDERAS_HASH se calcula concatenando las 8 flags en ORDEN FIJO.
--    Las flags nunca son NULL (el INNER JOIN a AUX garantiza fila 0/1).
--==============================================================================
INSERT INTO GD_SNAPSHOT_MATERIALES
(
   RUN_ID, RUN_TS, BANDERAS_HASH,
   NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN,
   NUMERO_PRODUCTO, CLASE_PRODUCTO, CATEGORIA_PRODUCTO, GRUPO_PRODUCTO,
   PT_PROD_LINE, PT_GROUP, PT_PART_TYPE, PT_DRAW, PT_DSGN_GRP, RO_MCH, PT_PROMO,
   PROYECTO, REVISION, REVISION_INTERNA, CL_CLIENTE, DE_CLIENTE, CL_PARTE_CLIENTE,
   RAMO, DESCRIPCION, CODIGO_IDIOMA, UNIDAD_MEDIDA_BASE, JERARQUIA_PRODUCTO,
   PT_SHIP_WT, PESO_BRUTO, PESO_NETO, UNIDAD_PESO_ISO, INDICADOR_ABC,
   GRUPO_COMPRA, FUENTE_APROVISIONAMIENTO, NUM_PRODUCTO, EXIST_TOTAL,
   ULTIMA_TRANSACCION, ULTIMO_TIPO_TXN, PT_SITE,
   HAS_EXIST, HAS_DIST, HAS_PO, HAS_SO, HAS_WO, HAS_RET, HAS_INV_SEG, HAS_ULT_TXN,
   ES_OBSOLETO
)
SELECT
   '&RUN_ID'                                     AS RUN_ID,
   SYSTIMESTAMP                                  AS RUN_TS,
   TO_CHAR(Q.HAS_EXIST)   || TO_CHAR(Q.HAS_DIST) ||
   TO_CHAR(Q.HAS_PO)      || TO_CHAR(Q.HAS_SO)   ||
   TO_CHAR(Q.HAS_WO)      || TO_CHAR(Q.HAS_RET)  ||
   TO_CHAR(Q.HAS_INV_SEG) || TO_CHAR(Q.HAS_ULT_TXN)   AS BANDERAS_HASH,
   Q.NUMERO_PRODUCTO_ANTIGUO, Q.PT_DOMAIN,
   Q.NUMERO_PRODUCTO, Q.CLASE_PRODUCTO, Q.CATEGORIA_PRODUCTO, Q.GRUPO_PRODUCTO,
   Q.PT_PROD_LINE, Q.PT_GROUP, Q.PT_PART_TYPE, Q.PT_DRAW, Q.PT_DSGN_GRP, Q.RO_MCH, Q.PT_PROMO,
   Q.PROYECTO, Q.REVISION, Q.REVISION_INTERNA, Q.CL_CLIENTE, Q.DE_CLIENTE, Q.CL_PARTE_CLIENTE,
   Q.RAMO, Q.DESCRIPCION, Q.CODIGO_IDIOMA, Q.UNIDAD_MEDIDA_BASE, Q.JERARQUIA_PRODUCTO,
   Q.PT_SHIP_WT, Q.PESO_BRUTO, Q.PESO_NETO, Q.UNIDAD_PESO_ISO, Q.INDICADOR_ABC,
   Q.GRUPO_COMPRA, Q.FUENTE_APROVISIONAMIENTO, Q.NUM_PRODUCTO, Q.EXIST_TOTAL,
   Q.ULTIMA_TRANSACCION, Q.ULTIMO_TIPO_TXN, Q.PT_SITE,
   Q.HAS_EXIST, Q.HAS_DIST, Q.HAS_PO, Q.HAS_SO, Q.HAS_WO, Q.HAS_RET, Q.HAS_INV_SEG, Q.HAS_ULT_TXN,
   Q.ES_OBSOLETO
FROM
(
   ----------------------------------------------------------------------------
   -- >>> QUERY GENERAL DE MATERIALES DEPURADOS (tal cual, sin el ORDER BY final)
   ----------------------------------------------------------------------------
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
          "HAS_EXIST",
          "HAS_DIST",
          "HAS_PO",
          "HAS_SO",
          "HAS_WO",
          "HAS_RET",
          "HAS_INV_SEG",
          "HAS_ULT_TXN",
          NVL (  "HAS_EXIST" + "HAS_DIST" + "HAS_PO" + "HAS_SO"
               + "HAS_WO" + "HAS_RET" + "HAS_INV_SEG" + "HAS_ULT_TXN", 0)  ES_OBSOLETO,
          "PT_DOMAIN",
          "PT_SITE"
     FROM (SELECT A.*,
                  ROW_NUMBER ()
                     OVER (PARTITION BY A.NUMERO_PRODUCTO_ANTIGUO
                           ORDER BY CASE
                                       WHEN UPPER (A.PT_DOMAIN) = 'ST'  THEN 1
                                       WHEN UPPER (A.PT_DOMAIN) = 'RSS' THEN 2
                                       WHEN UPPER (A.PT_DOMAIN) = 'HOS' THEN 3
                                       ELSE 99
                                    END)   AS RN_FINAL
             FROM (SELECT DISTINCT
                          PT_PART AS NUMERO_PRODUCTO,
                          ' ' AS CLASE_PRODUCTO,
                          ' ' AS CATEGORIA_PRODUCTO,
                          QAD.fnGetSAPPartGroup (PT_PROD_LINE, PT_GROUP, PT_PART_TYPE, PT_DOMAIN) AS GRUPO_PRODUCTO,
                          PT_PROD_LINE,
                          EXIST_TOTAL,
                          ULTIMA_TRANSACCION,
                          ULTIMO_TIPO_TXN,
                          HAS_EXIST, HAS_DIST, HAS_PO, HAS_SO, HAS_WO, HAS_RET, HAS_INV_SEG, HAS_ULT_TXN,
                          PT_GROUP, PT_PART_TYPE, PT_DRAW, PT_DSGN_GRP, RO_MCH,
                          CASE WHEN PT_DOMAIN = 'ST' THEN PT_BUYER END PROYECTO,
                          CASE WHEN PT_DOMAIN = 'ST' THEN PT_REV   END REVISION,
                          CL_CLIENTE, DE_CLIENTE, CL_PARTE_CLIENTE,
                          XXCRRF_AUT01 AS REVISION_INTERNA,
                          PT_PROMO,
                          ' ' AS RAMO,
                          PT_DESC1 || ' ' || PT_DESC2 AS DESCRIPCION,
                          'ES' AS CODIGO_IDIOMA,
                          UPPER (PT_UM) AS UNIDAD_MEDIDA_BASE,
                          PT_PART AS NUMERO_PRODUCTO_ANTIGUO,
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
                          PT_PART AS NUM_PRODUCTO,
                          PT_DOMAIN,
                          PT_SITE
                     FROM PT_MSTR A
                          LEFT JOIN UM_MSTR
                             ON     PT_PART = UM_PART
                                AND UPPER (PT_DOMAIN) = UPPER (UM_DOMAIN)
                                AND UPPER (PT_UM) = UPPER (UM_UM)
                          INNER JOIN SAP_AUX_CODIGOS_OBSOLETOS AUX
                             ON     A.PT_PART = AUX.PT_PART
                                AND A.PT_DOMAIN = AUX.PT_DOMAIN
                                AND (   AUX.HAS_EXIST = 1 OR AUX.HAS_DIST = 1
                                     OR AUX.HAS_PO = 1    OR AUX.HAS_SO = 1
                                     OR AUX.HAS_WO = 1    OR AUX.HAS_RET = 1
                                     OR AUX.HAS_INV_SEG = 1 OR AUX.HAS_ULT_TXN = 1)
                          LEFT JOIN IN_MSTR
                             ON     PT_PART = IN_PART
                                AND PT_DOMAIN = IN_DOMAIN
                                AND PT_SITE = IN_SITE
                          LEFT JOIN QAD.RO_DET
                             ON     UPPER (A.PT_PART) = UPPER (RO_ROUTING)
                                AND UPPER (RO_DOMAIN) = UPPER (A.PT_DOMAIN)
                          LEFT JOIN QAD.xxcrrf_Det
                             ON     xxcrrf_part = UPPER (A.PT_PART)
                                AND xxcrrf_domain = 'ST'
                                AND xxcrrf_type = 'PT-DATA'
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
                             ON A.pt_part = B.CL_ARTICULO
                    WHERE PT_STATUS = 'A'
                          AND UPPER (pt_domain) IN ('ST', 'HOS', 'RSS')) A)
    WHERE RN_FINAL = 1
   ----------------------------------------------------------------------------
   -- <<< FIN QUERY GENERAL
   ----------------------------------------------------------------------------
) Q;

COMMIT;


--==============================================================================
-- 3) VERIFICACION  ("prueba de que quedo bien")
--==============================================================================

-- 3.1  Conteo de materiales por corrida (una fila por RUN_ID)
SELECT RUN_ID, COUNT(*) AS MATERIALES, MIN(RUN_TS) AS FOTO
  FROM GD_SNAPSHOT_MATERIALES
 GROUP BY RUN_ID
 ORDER BY RUN_ID;

-- 3.2  ¿Como se veia el material X en la corrida del 15-jun?
SELECT *
  FROM GD_SNAPSHOT_MATERIALES
 WHERE NUMERO_PRODUCTO_ANTIGUO = '&MATERIAL'
   AND RUN_ID = 'RUN_2026-06-15';

-- 3.3  ¿Que huella tuvo el material X en cada foto? (linea de tiempo del estado)
SELECT RUN_ID, RUN_TS, PT_DOMAIN, BANDERAS_HASH, ES_OBSOLETO
  FROM GD_SNAPSHOT_MATERIALES
 WHERE NUMERO_PRODUCTO_ANTIGUO = '&MATERIAL'
 ORDER BY RUN_TS;

-- 3.4  Salud de la carga: la clave natural debe ser unica dentro de cada corrida
--      (debe devolver 0 filas)
SELECT RUN_ID, NUMERO_PRODUCTO_ANTIGUO, COUNT(*)
  FROM GD_SNAPSHOT_MATERIALES
 GROUP BY RUN_ID, NUMERO_PRODUCTO_ANTIGUO
HAVING COUNT(*) > 1;

-- 3.5  Integridad del hash: largo distinto de 8 => algo raro (debe devolver 0 filas)
SELECT COUNT(*) AS HASHES_MALOS
  FROM GD_SNAPSHOT_MATERIALES
 WHERE LENGTH(BANDERAS_HASH) <> 8;
