--------------------------------------------------------------------------------
-- VISTA AUXILIAR DE ACTIVIDAD  |  SAP_AUX_CODIGOS_OBSOLETOS
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
-- Servidor : ERP-PROD (oracle-host.example / ORCLPDB1), esquema QAD
--
-- Calcula, por (PT_PART, PT_DOMAIN), las senales de actividad de cada material:
-- existencias, distribuciones/PO/SO/WO/devoluciones pendientes, inventario de
-- seguridad y ultima transaccion. Fuente de las banderas HAS_* que consumen
-- V_GD_MATERIALES_DEP y SAP_MAESTRO_MATERIALES_GENERAL.
--
-- Cambios (2026-07-08):
--   * HOS fuera de alcance: solo ST y RSS.
--   * ULTIMA_TRANSACCION ahora es la fecha REAL de la ultima transaccion
--     (sin tope de 180 dias), para poder medir la antiguedad real.
--   * Se conserva la bandera HAS_ULT_TXN = actividad en los ultimos 180 dias.
--   * NUEVO: DIAS_SIN_MOVIMIENTO = dias desde la ultima transaccion (NULL = nunca).
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW SAP_AUX_CODIGOS_OBSOLETOS AS
WITH base AS (
  SELECT UPPER(PT_PART) AS PT_PART,
         UPPER(PT_DOMAIN) AS PT_DOMAIN
  FROM PT_MSTR
  WHERE UPPER(PT_DOMAIN) IN ('ST', 'RSS')
    AND UPPER(PT_STATUS) = 'A'
),

-- 1) EXISTENCIAS (IN_MSTR)  -- incluye no-neteable (IN_QTY_NONET), por acuerdo
exist AS (
  SELECT UPPER(IN_PART) AS PT_PART,
         SUM(NVL(IN_QTY_OH,0) + NVL(IN_QTY_NONET,0)) AS EXIST_TOTAL,
         UPPER(IN_DOMAIN) AS IN_DOMAIN
  FROM IN_MSTR
  WHERE UPPER(IN_DOMAIN) IN ('ST', 'RSS')
  GROUP BY UPPER(IN_PART), UPPER(IN_DOMAIN)
),

-- 2) DISTRIBUCIONES PENDIENTES (DS_DET)
dist AS (
  SELECT UPPER(ds_part) AS PT_PART,
         SUM(GREATEST(NVL(DS_QTY_CONF,0) - NVL(DS_QTY_SHIP,0), 0)) AS DIST_PEND_QTY,
         COUNT(*)                                               AS DIST_PEND_DOCS,
         MAX(DS_DUE_DATE)                                       AS DIST_MAX_DUE,
         UPPER(DS_DOMAIN) AS DS_DOMAIN
  FROM DS_DET
  WHERE UPPER(ds_domain) IN ('ST', 'RSS')
    AND UPPER(DS_STATUS) NOT IN ('C','P')
    AND GREATEST(NVL(DS_QTY_CONF,0) - NVL(DS_QTY_SHIP,0), 0) > 0
  GROUP BY UPPER(ds_part), UPPER(DS_DOMAIN)
),

-- 3) ORDENES DE COMPRA PENDIENTES (POD_DET)
po AS (
  SELECT UPPER(POD_PART) AS PT_PART,
         SUM(GREATEST(NVL(POD_QTY_ORD,0) - NVL(POD_QTY_RCVD,0),0)) AS PO_PEND_QTY,
         COUNT(*)                                                  AS PO_PEND_DOCS,
         MAX(POD_DUE_DATE)                                         AS PO_MAX_DUE,
         UPPER(POD_DOMAIN) AS POD_DOMAIN
  FROM POD_DET d
  WHERE UPPER(POD_DOMAIN) IN ('ST', 'RSS')
    AND d.POD_STATUS = ' '              -- abierto
    AND NVL(d.POD_CONSIGNMENT,0) = 0
    AND GREATEST(NVL(POD_QTY_ORD,0) - NVL(POD_QTY_RCVD,0),0) > 0
  GROUP BY UPPER(POD_PART), UPPER(POD_DOMAIN)
),

-- 4) ORDENES DE VENTA PENDIENTES (SOD_DET)
so AS (
  SELECT UPPER(SOD_PART) AS PT_PART,
         SUM(GREATEST(NVL(SOD_QTY_ORD,0) - NVL(SOD_QTY_SHIP,0) - NVL(SOD_QTY_INV,0),0)) AS SO_PEND_QTY,
         COUNT(*)                                                                        AS SO_PEND_DOCS,
         MAX(SOD_DUE_DATE)                                                               AS SO_MAX_DUE,
         UPPER(SOD_DOMAIN) AS SOD_DOMAIN
  FROM SOD_DET
  WHERE UPPER(SOD_DOMAIN) IN ('ST', 'RSS')
    AND GREATEST(NVL(SOD_QTY_ORD,0) - NVL(SOD_QTY_SHIP,0) - NVL(SOD_QTY_INV,0),0) > 0
  GROUP BY UPPER(SOD_PART), UPPER(SOD_DOMAIN)
),

-- 5) ORDENES DE TRABAJO PENDIENTES (WO_MSTR)
wo AS (
  SELECT UPPER(WO_PART) AS PT_PART,
         SUM(GREATEST(NVL(WO_QTY_ORD,0) - NVL(WO_QTY_COMP,0),0)) AS WO_PEND_QTY,
         COUNT(*)                                                AS WO_PEND_DOCS,
         MAX(WO_DUE_DATE)                                        AS WO_MAX_DUE,
         UPPER(WO_DOMAIN) AS WO_DOMAIN
  FROM WO_MSTR
  WHERE UPPER(WO_DOMAIN) IN ('ST', 'RSS')
    AND UPPER(WO_STATUS) = 'R'
    AND GREATEST(NVL(WO_QTY_ORD,0) - NVL(WO_QTY_COMP,0),0) > 0
  GROUP BY UPPER(WO_PART), UPPER(WO_DOMAIN)
),

-- 6) DEVOLUCIONES PENDIENTES (XXRFCRED_DET)
-- Nota: validar la columna de cantidad si la metrica difiere de XXRFCRED_QTY_REJ
ret AS (
  SELECT UPPER(xxrfcred_part) AS PT_PART,
         SUM(NVL(XXRFCRED_QTY_REJ, 0)) AS RET_PEND_QTY,
         COUNT(*)                      AS RET_PEND_DOCS,
         UPPER(xxrfcred_domain) AS XXRFCRED_DOMAIN
  FROM xxrfcred_det
  WHERE UPPER(xxrfcred_domain) IN ('ST', 'RSS')
    AND xxrfcred_cre_nbr = ' '
  GROUP BY UPPER(xxrfcred_part), UPPER(xxrfcred_domain)
),

-- 7) INVENTARIO DE SEGURIDAD (PTP_DET)
ptp AS (
  SELECT UPPER(PTP_PART) AS PT_PART,
         MAX(NVL(PTP_SFTY_STK,0)) AS INV_SEG,
         MAX(NVL(PTP_ORD_MAX,0))  AS INV_MAX,
         UPPER(PTP_DOMAIN) AS PTP_DOMAIN
  FROM PTP_DET
  WHERE UPPER(PTP_DOMAIN) IN ('ST', 'RSS')
    AND PTP_MS = 1
  GROUP BY UPPER(PTP_PART), UPPER(PTP_DOMAIN)
),

-- 8) ULTIMA TRANSACCION (TR_HIST)  -- fecha REAL + bandera 180d + antiguedad
txn AS (
  SELECT
    PT_PART,
    TR_DOMAIN,
    ULTIMA_TRANSACCION,                                          -- fecha real (sin tope 180d)
    TR_TYPE AS ULTIMO_TIPO_TXN,
    CASE WHEN ULTIMA_TRANSACCION >= TRUNC(SYSDATE) - 180
         THEN 1 ELSE 0 END                    AS HAS_ULT_TXN,    -- actividad en 180 dias (se conserva)
    TRUNC(SYSDATE) - TRUNC(ULTIMA_TRANSACCION) AS DIAS_SIN_MOVIMIENTO  -- antiguedad real (dias)
  FROM (
    SELECT
      UPPER(TR_PART)   AS PT_PART,
      UPPER(TR_DOMAIN) AS TR_DOMAIN,
      TR_EFFDATE       AS ULTIMA_TRANSACCION,
      TR_TYPE,
      ROW_NUMBER() OVER (
        PARTITION BY UPPER(TR_PART), UPPER(TR_DOMAIN)
        ORDER BY TR_EFFDATE DESC, TR_TIME DESC
      ) AS rnk
    FROM TR_HIST
    WHERE UPPER(TR_DOMAIN) IN ('ST', 'RSS')
      AND TR_TYPE NOT IN ('CYC-CNT','CYC-RCNT','CST-ADJ','CYC-ERR')
      -- (se elimina el tope de 180 dias: ULTIMA_TRANSACCION debe ser la fecha real)
  )
  WHERE rnk = 1
)

SELECT
  b.PT_PART,

  -- Existencias
  NVL(e.EXIST_TOTAL,0) AS EXIST_TOTAL,

  -- Distribuciones
  NVL(d.DIST_PEND_QTY,0)  AS DIST_PEND_QTY,
  NVL(d.DIST_PEND_DOCS,0) AS DIST_PEND_DOCS,
  d.DIST_MAX_DUE,

  -- Compras
  NVL(p.PO_PEND_QTY,0)  AS PO_PEND_QTY,
  NVL(p.PO_PEND_DOCS,0) AS PO_PEND_DOCS,
  p.PO_MAX_DUE,

  -- Ventas
  NVL(s.SO_PEND_QTY,0)  AS SO_PEND_QTY,
  NVL(s.SO_PEND_DOCS,0) AS SO_PEND_DOCS,
  s.SO_MAX_DUE,

  -- Ordenes de trabajo
  NVL(w.WO_PEND_QTY,0)  AS WO_PEND_QTY,
  NVL(w.WO_PEND_DOCS,0) AS WO_PEND_DOCS,
  w.WO_MAX_DUE,

  -- Devoluciones
  NVL(r.RET_PEND_QTY,0)  AS RET_PEND_QTY,
  NVL(r.RET_PEND_DOCS,0) AS RET_PEND_DOCS,

  -- Inventario de seguridad
  NVL(t.INV_SEG,0) AS INV_SEG,
  NVL(t.INV_MAX,0) AS INV_MAX,

  -- Ultima transaccion
  x.ULTIMA_TRANSACCION,
  x.ULTIMO_TIPO_TXN,
  x.DIAS_SIN_MOVIMIENTO,                                    -- NULL = nunca tuvo transaccion

  -- Flags (0/1)
  CASE WHEN NVL(e.EXIST_TOTAL,0) > 0 THEN 1 ELSE 0 END AS HAS_EXIST,
  CASE WHEN NVL(d.DIST_PEND_QTY,0) > 0 THEN 1 ELSE 0 END AS HAS_DIST,
  CASE WHEN NVL(p.PO_PEND_QTY,0) > 0 THEN 1 ELSE 0 END AS HAS_PO,
  CASE WHEN NVL(s.SO_PEND_QTY,0) > 0 THEN 1 ELSE 0 END AS HAS_SO,
  CASE WHEN NVL(w.WO_PEND_QTY,0) > 0 THEN 1 ELSE 0 END AS HAS_WO,
  CASE WHEN NVL(r.RET_PEND_QTY,0) > 0 THEN 1 ELSE 0 END AS HAS_RET,
  CASE WHEN NVL(t.INV_SEG,0) > 0 THEN 1 ELSE 0 END AS HAS_INV_SEG,
  NVL(x.HAS_ULT_TXN, 0) AS HAS_ULT_TXN,                    -- ya NO "IS NOT NULL": es la bandera 180d
  b.PT_DOMAIN

FROM base b
LEFT JOIN exist e ON e.PT_PART = b.PT_PART AND b.PT_DOMAIN = e.IN_DOMAIN
LEFT JOIN dist  d ON d.PT_PART = b.PT_PART AND b.PT_DOMAIN = d.DS_DOMAIN
LEFT JOIN po    p ON p.PT_PART = b.PT_PART AND b.PT_DOMAIN = p.POD_DOMAIN
LEFT JOIN so    s ON s.PT_PART = b.PT_PART AND b.PT_DOMAIN = s.SOD_DOMAIN
LEFT JOIN wo    w ON w.PT_PART = b.PT_PART AND b.PT_DOMAIN = w.WO_DOMAIN
LEFT JOIN ret   r ON r.PT_PART = b.PT_PART AND b.PT_DOMAIN = r.XXRFCRED_DOMAIN
LEFT JOIN ptp   t ON t.PT_PART = b.PT_PART AND b.PT_DOMAIN = t.PTP_DOMAIN
LEFT JOIN txn   x ON x.PT_PART = b.PT_PART AND b.PT_DOMAIN = x.TR_DOMAIN
