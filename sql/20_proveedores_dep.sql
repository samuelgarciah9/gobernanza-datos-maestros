--------------------------------------------------------------------------------
-- PROVEEDORES · PASO 1  |  VISTA DE DEPURACION POR SOCIEDAD (prototipo ST)
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
--
-- Espejo de V_GD_MATERIALES_DEP pero para proveedores. Una fila por RFC
-- (NUM_ID_FISCAL / AD_GST_ID) de la sociedad ST, con las 4 senales de actividad:
--   HAS_BACKORDER (OC viva) · HAS_RECEPT (recepcion 12m) ·
--   HAS_PENDING (pago pendiente) · HAS_VOUCHER (voucher desde 2025-08-01).
--
-- Gobernanza agregada:
--   PESO_ACTIVIDAD = suma plana de las 4 banderas (0..4). 0 = sin actividad.
--   BANDERAS_HASH  = huella de estado, orden fijo BACKORDER(1) RECEPT(2) PENDING(3) VOUCHER(4).
--
-- A diferencia de materiales, aqui se traen TODOS los proveedores de ST (con o sin
-- actividad): los de PESO_ACTIVIDAD=0 son los candidatos a DESCARTAR.
--
-- Llave natural del proyecto para proveedores = RFC (un proveedor puede existir en
-- varias sociedades; se decide una sola vez por RFC). SOCIEDAD/DOMINIO = atributo.
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GD_PROV_DEP_ST AS
WITH maestro_rfc AS (
    SELECT UPPER (ad.AD_DOMAIN) AS DOMINIO,
           UPPER (ad.AD_GST_ID) AS RFC,
           MAX (ad.AD_SORT || ad.AD_LINE3) AS NOMBRE_CONSOLIDADO,
           MAX (ad.AD_ATTN) AS PERSONA_CONTACTO,
           CASE WHEN LENGTH (UPPER (ad.AD_GST_ID)) = 13 THEN 'X' ELSE ' ' END AS PERSONA_FISICA,
           UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)) AS DE_DIRECCION,
           SUBSTR ((QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).calle, 1, 60) AS CALLE,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).numero_ext AS NUMERO_INMUEBLE_EXT,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).numero_int AS NUMERO_INMUEBLE_INT,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).colonia AS DISTRITO,
           MAX (ad.ad_zip) AS CP,
           MAX (ad.AD_CITY) AS POBLACION,
           MAX (ad.AD_COUNTRY) AS PAIS_REGION,
           MAX (ad.AD_STATE) AS ESTADO_DIR,
           MAX (ad.AD_PHONE) AS TELEFONO_DEFECTO,
           MAX (CD_CMMT##1) AS CORREO1,
           MAX (CD_CMMT##2) AS CORREO2,
           MAX (CD_CMMT##3) AS CORREO3,
           MAX (CD_CMMT##4) AS CORREO4,
           MAX (vd.vd_cr_terms) AS TERMINOS_CREDITO,
           MAX (vd.VD_CURR) AS MONEDA_ORDEN,
           MAX (vd.vd_type) AS TIPO_PROVEEDOR
      FROM VD_MSTR vd
           JOIN AD_MSTR ad ON ad.AD_ADDR = vd.VD_ADDR AND ad.AD_DOMAIN = vd.VD_DOMAIN
           LEFT JOIN CD_DET ON AD_DOMAIN = CD_DOMAIN AND AD_ADDR = CD_REF AND CD_TYPE = 'SM'
     WHERE ad.AD_GST_ID IS NOT NULL AND TRIM (ad.AD_GST_ID) <> ' ' AND ad.AD_DOMAIN = 'ST'
     GROUP BY UPPER (ad.AD_DOMAIN), UPPER (ad.AD_GST_ID)
),
compras_anuales AS (
    SELECT UPPER (ad.AD_GST_ID) AS RFC, MAX (UPPER (POD_SITE)) ALMACEN,
           COUNT (DISTINCT PO_NBR) AS TOTAL_OC_ANUAL, MAX (PO_ORD_DATE) AS LAST_ORD,
           SUM (CASE WHEN UPPER (PO_CURR) = 'USD' THEN (POD_QTY_ORD * POD_PUR_COST) ELSE 0 END) AS PRECIO_USD_2025,
           SUM (CASE WHEN UPPER (PO_CURR) = 'MN'  THEN (POD_QTY_ORD * POD_PUR_COST) ELSE 0 END) AS PRECIO_MXN_2025,
           SUM (POD_QTY_ORD) AS VOLUMEN_COMPRADO_2025
      FROM POD_DET INNER JOIN PO_MSTR ON UPPER (POD_NBR) = UPPER (PO_NBR) AND UPPER (POD_DOMAIN) = UPPER (PO_DOMAIN)
           INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (PO_VEND) AND UPPER (ad.AD_DOMAIN) = UPPER (PO_DOMAIN)
     WHERE PO_ORD_DATE >= DATE '2025-01-01' AND POD_CONSIGNMENT = 0 AND UPPER (PO_DOMAIN) = 'ST'
     GROUP BY UPPER (ad.AD_GST_ID)
),
back_orders_agrupados AS (
    SELECT UPPER (ad.AD_GST_ID) AS RFC, COUNT (DISTINCT PO_NBR) AS TOTAL_OC_PEND,
           SUM (POD_QTY_ORD * POD_PUR_COST) AS TOTAL_PRECIO_PEND
      FROM POD_DET INNER JOIN PO_MSTR ON UPPER (POD_NBR) = UPPER (PO_NBR) AND UPPER (POD_DOMAIN) = UPPER (PO_DOMAIN)
           INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (PO_VEND) AND UPPER (ad.AD_DOMAIN) = UPPER (PO_DOMAIN)
     WHERE UPPER (POD_STATUS) NOT IN ('X', 'C') AND (POD_QTY_ORD - POD_QTY_RCVD) > 0 AND UPPER (PO_DOMAIN) = 'ST'
     GROUP BY UPPER (ad.AD_GST_ID)
),
recepciones_filtradas AS (
    SELECT DISTINCT UPPER (ad.AD_GST_ID) AS RFC
      FROM qad.PRH_HIST a INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (a.prh_vend) AND UPPER (ad.AD_DOMAIN) = UPPER (a.PRH_DOMAIN)
     WHERE UPPER (a.PRH_DOMAIN) = 'ST' AND a.prh_rcp_date >= ADD_MONTHS (SYSDATE, -12)
),
pagos_pendientes AS (
    SELECT DISTINCT UPPER (ad.AD_GST_ID) AS RFC
      FROM QAD.AP_D_AP_VO_QAD_ST p INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (p.cl_proveedor) AND UPPER (ad.AD_DOMAIN) = 'ST'
     WHERE CL_STATUS_ABIERTO <> 0
),
vouchers_agrupados AS (
    SELECT UPPER (CL_RFC) AS RFC, COUNT (CL_VOUCHER) AS TOTAL_VOUCHERS, MAX (FE_EFECTIVA) AS ULTIMA_FECHA_EF_VO
      FROM AP_D_VO_##_A_ST_SAP
     WHERE FE_EFECTIVA >= DATE '2025-08-01' AND CL_RFC IS NOT NULL AND CL_RFC <> ' '
     GROUP BY UPPER (CL_RFC)
)
SELECT m.DOMINIO,
       m.RFC,
       m.TIPO_PROVEEDOR,
       m.NOMBRE_CONSOLIDADO,
       m.PERSONA_CONTACTO,
       m.PERSONA_FISICA,
       m.DE_DIRECCION,
       m.CALLE,
       m.NUMERO_INMUEBLE_EXT,
       m.NUMERO_INMUEBLE_INT,
       m.DISTRITO,
       m.CP,
       m.POBLACION,
       m.PAIS_REGION,
       m.ESTADO_DIR,
       m.TELEFONO_DEFECTO,
       m.CORREO1, m.CORREO2, m.CORREO3, m.CORREO4,
       m.TERMINOS_CREDITO,
       m.MONEDA_ORDEN,
       NVL (c.TOTAL_OC_ANUAL, 0)  AS OC_2025,
       c.LAST_ORD                 AS FECHA_ULT_COMPRA,
       NVL (c.PRECIO_USD_2025, 0) AS MONTO_USD_2025,
       NVL (c.PRECIO_MXN_2025, 0) AS MONTO_MXN_2025,
       NVL (b.TOTAL_OC_PEND, 0)   AS OC_VIVAS,
       NVL (b.TOTAL_PRECIO_PEND, 0) AS MONTO_PEND,
       NVL (v.TOTAL_VOUCHERS, 0)  AS CANTIDAD_VOUCHERS,
       v.ULTIMA_FECHA_EF_VO       AS FECHA_VOUCHER_RECIENTE,
       CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_BACKORDER,
       CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_RECEPT,
       CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_PENDING,
       CASE WHEN v.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_VOUCHER,
       (CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN v.RFC IS NOT NULL THEN 1 ELSE 0 END) AS PESO_ACTIVIDAD,
       (TO_CHAR (CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || TO_CHAR (CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || TO_CHAR (CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || TO_CHAR (CASE WHEN v.RFC IS NOT NULL THEN 1 ELSE 0 END)) AS BANDERAS_HASH
  FROM maestro_rfc m
       LEFT JOIN compras_anuales c       ON c.RFC = m.RFC
       LEFT JOIN back_orders_agrupados b ON b.RFC = m.RFC
       LEFT JOIN recepciones_filtradas r ON r.RFC = m.RFC
       LEFT JOIN pagos_pendientes p      ON p.RFC = m.RFC
       LEFT JOIN vouchers_agrupados v    ON v.RFC = m.RFC;


--------------------------------------------------------------------------------
-- PROVEEDORES · DEPURACION SOCIEDAD RSS
-- Igual que ST pero con fuentes RSS. NOTA: RSS no tiene tabla de vouchers SAP en
-- este servidor (solo existe AP_D_VO_##_A_ST_SAP), por lo que HAS_VOUCHER = 0
-- para RSS (bandera sin fuente). Las 3 firmes (backorder/recept/pending) sí aplican.
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GD_PROV_DEP_RSS AS
WITH maestro_rfc AS (
    SELECT UPPER (ad.AD_DOMAIN) AS DOMINIO,
           UPPER (ad.AD_GST_ID) AS RFC,
           MAX (ad.AD_SORT || ad.AD_LINE3) AS NOMBRE_CONSOLIDADO,
           MAX (ad.AD_ATTN) AS PERSONA_CONTACTO,
           CASE WHEN LENGTH (UPPER (ad.AD_GST_ID)) = 13 THEN 'X' ELSE ' ' END AS PERSONA_FISICA,
           UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)) AS DE_DIRECCION,
           SUBSTR ((QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).calle, 1, 60) AS CALLE,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).numero_ext AS NUMERO_INMUEBLE_EXT,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).numero_int AS NUMERO_INMUEBLE_INT,
           (QAD.fnObtenerDireccion (UPPER (MAX (ad.AD_LINE1 || ad.AD_LINE2 || ad.AD_MISC2_id)))).colonia AS DISTRITO,
           MAX (ad.ad_zip) AS CP,
           MAX (ad.AD_CITY) AS POBLACION,
           MAX (ad.AD_COUNTRY) AS PAIS_REGION,
           MAX (ad.AD_STATE) AS ESTADO_DIR,
           MAX (ad.AD_PHONE) AS TELEFONO_DEFECTO,
           MAX (CD_CMMT##1) AS CORREO1,
           MAX (CD_CMMT##2) AS CORREO2,
           MAX (CD_CMMT##3) AS CORREO3,
           MAX (CD_CMMT##4) AS CORREO4,
           MAX (vd.vd_cr_terms) AS TERMINOS_CREDITO,
           MAX (vd.VD_CURR) AS MONEDA_ORDEN,
           MAX (vd.vd_type) AS TIPO_PROVEEDOR
      FROM VD_MSTR vd
           JOIN AD_MSTR ad ON ad.AD_ADDR = vd.VD_ADDR AND ad.AD_DOMAIN = vd.VD_DOMAIN
           LEFT JOIN CD_DET ON AD_DOMAIN = CD_DOMAIN AND AD_ADDR = CD_REF AND CD_TYPE = 'SM'
     WHERE ad.AD_GST_ID IS NOT NULL AND TRIM (ad.AD_GST_ID) <> ' ' AND ad.AD_DOMAIN = 'RSS'
     GROUP BY UPPER (ad.AD_DOMAIN), UPPER (ad.AD_GST_ID)
),
compras_anuales AS (
    SELECT UPPER (ad.AD_GST_ID) AS RFC, MAX (UPPER (POD_SITE)) ALMACEN,
           COUNT (DISTINCT PO_NBR) AS TOTAL_OC_ANUAL, MAX (PO_ORD_DATE) AS LAST_ORD,
           SUM (CASE WHEN UPPER (PO_CURR) = 'USD' THEN (POD_QTY_ORD * POD_PUR_COST) ELSE 0 END) AS PRECIO_USD_2025,
           SUM (CASE WHEN UPPER (PO_CURR) = 'MN'  THEN (POD_QTY_ORD * POD_PUR_COST) ELSE 0 END) AS PRECIO_MXN_2025,
           SUM (POD_QTY_ORD) AS VOLUMEN_COMPRADO_2025
      FROM POD_DET INNER JOIN PO_MSTR ON UPPER (POD_NBR) = UPPER (PO_NBR) AND UPPER (POD_DOMAIN) = UPPER (PO_DOMAIN)
           INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (PO_VEND) AND UPPER (ad.AD_DOMAIN) = UPPER (PO_DOMAIN)
     WHERE PO_ORD_DATE >= DATE '2025-01-01' AND POD_CONSIGNMENT = 0 AND UPPER (PO_DOMAIN) = 'RSS'
     GROUP BY UPPER (ad.AD_GST_ID)
),
back_orders_agrupados AS (
    SELECT UPPER (ad.AD_GST_ID) AS RFC, COUNT (DISTINCT PO_NBR) AS TOTAL_OC_PEND,
           SUM (POD_QTY_ORD * POD_PUR_COST) AS TOTAL_PRECIO_PEND
      FROM POD_DET INNER JOIN PO_MSTR ON UPPER (POD_NBR) = UPPER (PO_NBR) AND UPPER (POD_DOMAIN) = UPPER (PO_DOMAIN)
           INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (PO_VEND) AND UPPER (ad.AD_DOMAIN) = UPPER (PO_DOMAIN)
     WHERE UPPER (POD_STATUS) NOT IN ('X', 'C') AND (POD_QTY_ORD - POD_QTY_RCVD) > 0 AND UPPER (PO_DOMAIN) = 'RSS'
     GROUP BY UPPER (ad.AD_GST_ID)
),
recepciones_filtradas AS (
    SELECT DISTINCT UPPER (ad.AD_GST_ID) AS RFC
      FROM qad.PRH_HIST a INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (a.prh_vend) AND UPPER (ad.AD_DOMAIN) = UPPER (a.PRH_DOMAIN)
     WHERE UPPER (a.PRH_DOMAIN) = 'RSS' AND a.prh_rcp_date >= ADD_MONTHS (SYSDATE, -12)
),
pagos_pendientes AS (
    SELECT DISTINCT UPPER (ad.AD_GST_ID) AS RFC
      FROM QAD.AP_D_AP_VO_QAD_RSS p INNER JOIN AD_MSTR ad ON UPPER (ad.AD_ADDR) = UPPER (p.cl_proveedor) AND UPPER (ad.AD_DOMAIN) = 'RSS'
     WHERE CL_STATUS_ABIERTO <> 0
)
SELECT m.DOMINIO,
       m.RFC,
       m.TIPO_PROVEEDOR,
       m.NOMBRE_CONSOLIDADO,
       m.PERSONA_CONTACTO,
       m.PERSONA_FISICA,
       m.DE_DIRECCION,
       m.CALLE,
       m.NUMERO_INMUEBLE_EXT,
       m.NUMERO_INMUEBLE_INT,
       m.DISTRITO,
       m.CP,
       m.POBLACION,
       m.PAIS_REGION,
       m.ESTADO_DIR,
       m.TELEFONO_DEFECTO,
       m.CORREO1, m.CORREO2, m.CORREO3, m.CORREO4,
       m.TERMINOS_CREDITO,
       m.MONEDA_ORDEN,
       NVL (c.TOTAL_OC_ANUAL, 0)  AS OC_2025,
       c.LAST_ORD                 AS FECHA_ULT_COMPRA,
       NVL (c.PRECIO_USD_2025, 0) AS MONTO_USD_2025,
       NVL (c.PRECIO_MXN_2025, 0) AS MONTO_MXN_2025,
       NVL (b.TOTAL_OC_PEND, 0)   AS OC_VIVAS,
       NVL (b.TOTAL_PRECIO_PEND, 0) AS MONTO_PEND,
       0                          AS CANTIDAD_VOUCHERS,       -- RSS sin fuente de vouchers SAP
       CAST (NULL AS DATE)        AS FECHA_VOUCHER_RECIENTE,
       CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_BACKORDER,
       CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_RECEPT,
       CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END AS HAS_PENDING,
       0                          AS HAS_VOUCHER,
       (CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END) AS PESO_ACTIVIDAD,
       (TO_CHAR (CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || TO_CHAR (CASE WHEN r.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || TO_CHAR (CASE WHEN p.RFC IS NOT NULL THEN 1 ELSE 0 END)
     || '0') AS BANDERAS_HASH
  FROM maestro_rfc m
       LEFT JOIN compras_anuales c       ON c.RFC = m.RFC
       LEFT JOIN back_orders_agrupados b ON b.RFC = m.RFC
       LEFT JOIN recepciones_filtradas r ON r.RFC = m.RFC
       LEFT JOIN pagos_pendientes p      ON p.RFC = m.RFC;


-- NOTA: NO se usa una vista unificada V_GD_PROV_DEP con "SELECT * UNION ALL".
-- Oracle falla (ORA-00942) al expandir '*' sobre estas vistas porque exponen
-- atributos de tipo OBJETO (QAD.fnObtenerDireccion(...).calle) dentro de un UNION.
-- La foto (gd/proveedores/proceso.py) lee cada vista por dominio:
--   ST  -> V_GD_PROV_DEP_ST     RSS -> V_GD_PROV_DEP_RSS


--------------------------------------------------------------------------------
-- PROVEEDORES · DUPLICADOS ENTRE SOCIEDADES  -  RFC presente en ST y en RSS
-- Comparativa lado a lado sobre el ULTIMO snapshot de cada sociedad. Como la
-- decisión es por RFC (una sola), estos comparten decisión (informativo).
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GD_PROV_DUP_ST_RSS AS
WITH u AS (SELECT DOMINIO, MAX (RUN_TS) AS MX FROM GD_SNAPSHOT_PROVEEDORES GROUP BY DOMINIO),
     st  AS (SELECT s.* FROM GD_SNAPSHOT_PROVEEDORES s JOIN u ON u.DOMINIO = s.DOMINIO AND u.MX = s.RUN_TS WHERE s.DOMINIO = 'ST'),
     rss AS (SELECT s.* FROM GD_SNAPSHOT_PROVEEDORES s JOIN u ON u.DOMINIO = s.DOMINIO AND u.MX = s.RUN_TS WHERE s.DOMINIO = 'RSS')
SELECT st.RFC,
       st.NOMBRE_CONSOLIDADO,
       st.PESO_ACTIVIDAD AS PESO_ST,
       rss.PESO_ACTIVIDAD AS PESO_RSS,
       st.OC_2025 AS OC_2025_ST,
       rss.OC_2025 AS OC_2025_RSS
  FROM st INNER JOIN rss ON rss.RFC = st.RFC;
