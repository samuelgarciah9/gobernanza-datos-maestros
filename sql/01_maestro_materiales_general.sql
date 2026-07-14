--------------------------------------------------------------------------------
-- PASO 1  |  UNIVERSO MAESTRO  |  SAP_MAESTRO_MATERIALES_GENERAL
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
-- Servidor : ERP-PROD (oracle-host.example / ORCLPDB1), esquema QAD
--
-- Universo maestro deduplicado: 1 fila por NUMERO_PRODUCTO_ANTIGUO con dominio
-- prioritario ST > RSS > HOS. Solo materiales ACTIVOS y CON al menos una senal
-- de actividad (INNER JOIN a SAP_AUX_CODIGOS_OBSOLETOS).
-- Es la base del avance de carga a SAP (Paso 7, sql/12).
--
-- 2026-07-10: definicion versionada por primera vez (antes solo vivia en la BD)
--   al aplicar la normalizacion case-insensitive: UPPER en PT_STATUS, en las
--   llaves de salida (PT_PART / PT_DOMAIN) y en ambos lados de todos los joins.
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW SAP_MAESTRO_MATERIALES_GENERAL AS
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
         NVL (
              "HAS_EXIST"
            + "HAS_DIST"
            + "HAS_PO"
            + "HAS_SO"
            + "HAS_WO"
            + "HAS_RET"
            + "HAS_INV_SEG"
            + "HAS_ULT_TXN",
            0)
            ES_OBSOLETO,
         "PT_DOMAIN",
         "PT_SITE"
    FROM (SELECT A.*,
                 ROW_NUMBER ()
                    OVER (PARTITION BY A.NUMERO_PRODUCTO_ANTIGUO
                          ORDER BY CASE
                                      WHEN UPPER (A.PT_DOMAIN) = 'ST' THEN 1
                                      WHEN UPPER (A.PT_DOMAIN) = 'RSS' THEN 2
                                      WHEN UPPER (A.PT_DOMAIN) = 'HOS' THEN 3
                                      ELSE 99
                                   END)
                    AS RN_FINAL
            FROM (SELECT DISTINCT
                         UPPER (PT_PART) AS NUMERO_PRODUCTO,
                         ' ' AS CLASE_PRODUCTO,
                         ' ' AS CATEGORIA_PRODUCTO,
                         QAD.fnGetSAPPartGroup (PT_PROD_LINE,
                                                PT_GROUP,
                                                PT_PART_TYPE,
                                                PT_DOMAIN)
                            AS GRUPO_PRODUCTO,
                         PT_PROD_LINE,
                         EXIST_TOTAL,
                         ULTIMA_TRANSACCION,
                         ULTIMO_TIPO_TXN,
                         HAS_EXIST,
                         HAS_DIST,
                         HAS_PO,
                         HAS_SO,
                         HAS_WO,
                         HAS_RET,
                         HAS_INV_SEG,
                         HAS_ULT_TXN,
                         PT_GROUP,
                         PT_PART_TYPE,
                         PT_DRAW,
                         PT_DSGN_GRP,
                         RO_MCH,
                         CASE WHEN UPPER (PT_DOMAIN) = 'ST' THEN PT_BUYER END PROYECTO,
                         CASE WHEN UPPER (PT_DOMAIN) = 'ST' THEN PT_REV END REVISION,
                         CL_CLIENTE,
                         DE_CLIENTE,
                         CL_PARTE_CLIENTE,
                         XXCRRF_AUT01 AS REVISION_INTERNA,
                         PT_PROMO,
                         ' ' AS RAMO,
                         PT_DESC1 || ' ' || PT_DESC2 AS DESCRIPCION,
                         'ES' AS CODIGO_IDIOMA,
                         UPPER (PT_UM) AS UNIDAD_MEDIDA_BASE,
                         UPPER (PT_PART) AS NUMERO_PRODUCTO_ANTIGUO,
                         PT_PART_TYPE AS JERARQUIA_PRODUCTO,
                         A.PT_SHIP_WT,
                         CASE
                            WHEN UPPER (PT_UM) = 'PZ'
                                 AND UPPER (UM_ALT_UM) = 'KG'
                            THEN
                               ROUND ( (1 / UM_CONV), 3)
                            WHEN UPPER (PT_UM) = 'KG'
                                 AND UPPER (UM_ALT_UM) = 'PZ'
                            THEN
                               ROUND (UM_CONV, 3)
                         END
                            AS PESO_BRUTO,
                         CASE
                            WHEN UPPER (PT_UM) = 'PZ'
                                 AND UPPER (UM_ALT_UM) = 'KG'
                            THEN
                               ROUND ( (1 / UM_CONV), 3)
                            WHEN UPPER (PT_UM) = 'KG'
                                 AND UPPER (UM_ALT_UM) = 'PZ'
                            THEN
                               ROUND (UM_CONV, 3)
                         END
                            AS PESO_NETO,
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
                            ON UPPER (A.PT_PART) = AUX.PT_PART
                               AND UPPER (A.PT_DOMAIN) = AUX.PT_DOMAIN
                               AND (   AUX.HAS_EXIST = 1
                                    OR AUX.HAS_DIST = 1
                                    OR AUX.HAS_PO = 1
                                    OR AUX.HAS_SO = 1
                                    OR AUX.HAS_WO = 1
                                    OR AUX.HAS_RET = 1
                                    OR AUX.HAS_INV_SEG = 1
                                    OR AUX.HAS_ULT_TXN = 1)
                         LEFT JOIN IN_MSTR
                            ON     UPPER (PT_PART) = UPPER (IN_PART)
                               AND UPPER (PT_DOMAIN) = UPPER (IN_DOMAIN)
                               AND UPPER (PT_SITE) = UPPER (IN_SITE)
                         LEFT JOIN QAD.RO_DET
                            ON UPPER (A.PT_PART) = UPPER (RO_ROUTING)
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
                                     WHERE UPPER (CP_CUST) =
                                              UPPER (B.CM_ADDR(+))
                                           AND UPPER (cp_domain) = 'ST'
                                           AND UPPER (cm_domain(+)) = 'ST'
                                           AND UPPER (C.PT_PART(+)) =
                                                  UPPER (cp_part)
                                           AND UPPER (C.PT_DOMAIN(+)) = 'ST') B
                            ON UPPER (A.pt_part) = B.CL_ARTICULO
                   WHERE UPPER (PT_STATUS) = 'A'
                         AND UPPER (pt_domain) IN ('ST', 'HOS', 'RSS')) A)
   WHERE RN_FINAL = 1
ORDER BY NUMERO_PRODUCTO;
