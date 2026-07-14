--------------------------------------------------------------------------------
-- PROVEEDORES · PASO 3 y 7  |  RECONCILIACION (buckets) + AVANCE/OBSERVACION SAP
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA  (prototipo ST)
--
-- Espejo de sql/10 y sql/12 para proveedores. Llave = RFC.
-- Hash de 4 banderas, orden fijo: BACKORDER(1) RECEPT(2) PENDING(3) VOUCHER(4).
-- Firmes = BACKORDER/RECEPT/PENDING. Blanda = VOUCHER.
--
-- Disparadores RE_REVISAR:
--   A) DESCARTAR -> POSIBLE_MIGRAR : aparece (0->1) una firme (backorder/recept/pending).
--   B) MIGRAR    -> POSIBLE_DESCARTAR : se apagan TODAS las firmes.
--
-- Observacion SAP (V_GD_PROV_SAP_AVANCE), cruzando contra XXVEND_PROVEEDORES por RFC:
--   YA_BP_EXTENDER_FI1200 : ya es BP en SAP (XXVEND_ID_PRD real) -> NO migrar, solo
--                           extender a la sociedad FI 1200 (ST). Sale de pendientes.
--   POR_CREAR             : decidido MIGRAR y aun NO es BP.
--   DESCARTADO_OK         : decidido DESCARTAR y no es BP.
--   CONTRADICCION         : es BP pero decidido DESCARTAR -> ALERTA.
--   PENDIENTE             : sin decision y no es BP.
-- "Es BP" = XXVEND_PROVEEDORES.XXVEND_ID_PRD con numero real (ni nulo ni INDEFINIDO).
--------------------------------------------------------------------------------


--==============================================================================
-- 1) MERGE  -  buckets sobre el ultimo snapshot ST por RFC
--==============================================================================
CREATE OR REPLACE VIEW V_GD_PROV_MERGE AS
WITH ultimos AS (
   SELECT DOMINIO, MAX (RUN_TS) AS MX FROM GD_SNAPSHOT_PROVEEDORES GROUP BY DOMINIO
),
clasif AS (
   SELECT s.*,
          d.ESTADO            AS DECISION_PREVIA,
          d.RAZON             AS RAZON_PREVIA,
          d.COMENTARIO        AS COMENTARIO_PREVIO,
          d.DECIDIDO_POR      AS DECIDIDO_POR_PREVIO,
          d.ROL               AS ROL_PREVIO,
          d.HASH_AL_DECIDIR   AS HASH_PREVIO,
          d.RUN_ID_AL_DECIDIR AS RUN_PREVIO,
          d.RFC               AS DEC_RFC,
          NVL (d.HASH_AL_DECIDIR, '0000') AS PREV_HASH,
          CASE WHEN d.ESTADO = 'DESCARTAR' AND (
                    (SUBSTR (NVL (d.HASH_AL_DECIDIR,'0000'),1,1) = '0' AND s.HAS_BACKORDER = 1) OR
                    (SUBSTR (NVL (d.HASH_AL_DECIDIR,'0000'),2,1) = '0' AND s.HAS_RECEPT    = 1) OR
                    (SUBSTR (NVL (d.HASH_AL_DECIDIR,'0000'),3,1) = '0' AND s.HAS_PENDING   = 1))
               THEN 1 ELSE 0 END AS TRIG_A,
          CASE WHEN d.ESTADO = 'MIGRAR' AND
                    s.HAS_BACKORDER = 0 AND s.HAS_RECEPT = 0 AND s.HAS_PENDING = 0
               THEN 1 ELSE 0 END AS TRIG_B
     FROM GD_SNAPSHOT_PROVEEDORES s
          JOIN ultimos u ON u.DOMINIO = s.DOMINIO AND u.MX = s.RUN_TS
          LEFT JOIN GD_DECISIONES_PROVEEDORES d ON d.RFC = s.RFC
)
SELECT c.*,
       CASE
          WHEN c.DEC_RFC IS NULL OR c.DECISION_PREVIA = 'PENDIENTE' THEN 'POR_DECIDIR'
          WHEN c.BANDERAS_HASH = c.PREV_HASH                        THEN 'VIGENTE'
          WHEN c.TRIG_A = 1 OR c.TRIG_B = 1                         THEN 'RE_REVISAR'
          ELSE 'VIGENTE'
       END AS BUCKET,
       CASE WHEN c.DEC_RFC IS NOT NULL AND c.DECISION_PREVIA <> 'PENDIENTE'
                 AND c.BANDERAS_HASH <> c.PREV_HASH THEN
               CASE WHEN c.TRIG_A = 1 THEN 'POSIBLE_MIGRAR'
                    WHEN c.TRIG_B = 1 THEN 'POSIBLE_DESCARTAR' END
       END AS MOTIVO,
       CASE WHEN c.DEC_RFC IS NOT NULL AND c.HASH_PREVIO IS NOT NULL THEN
          TRIM (
             CASE WHEN SUBSTR (c.PREV_HASH,1,1) <> TO_CHAR (c.HAS_BACKORDER) THEN (CASE WHEN c.HAS_BACKORDER=1 THEN '+' ELSE '-' END)||'BACKORDER ' END ||
             CASE WHEN SUBSTR (c.PREV_HASH,2,1) <> TO_CHAR (c.HAS_RECEPT)    THEN (CASE WHEN c.HAS_RECEPT=1    THEN '+' ELSE '-' END)||'RECEPT '    END ||
             CASE WHEN SUBSTR (c.PREV_HASH,3,1) <> TO_CHAR (c.HAS_PENDING)   THEN (CASE WHEN c.HAS_PENDING=1   THEN '+' ELSE '-' END)||'PENDING '   END ||
             CASE WHEN SUBSTR (c.PREV_HASH,4,1) <> TO_CHAR (c.HAS_VOUCHER)   THEN (CASE WHEN c.HAS_VOUCHER=1   THEN '+' ELSE '-' END)||'VOUCHER '   END
          )
       END AS FLAGS_CAMBIADOS
  FROM clasif c;


--==============================================================================
-- 2) SALIO  -  decision concluyente cuyo RFC ya NO esta en el ultimo snapshot
--==============================================================================
CREATE OR REPLACE VIEW V_GD_PROV_SALIO AS
SELECT d.RFC,
       d.DOMINIO,
       d.ESTADO       AS DECISION,
       d.RAZON,
       d.DECIDIDO_POR,
       d.ROL,
       d.RUN_ID_AL_DECIDIR,
       d.FECHA_DECISION,
       CASE WHEN d.ESTADO = 'MIGRAR' THEN 'REVISAR' ELSE 'INFORMATIVO' END AS ATENCION
  FROM GD_DECISIONES_PROVEEDORES d
 WHERE d.ESTADO IN ('MIGRAR','DESCARTAR')
   AND NOT EXISTS (
          SELECT 1 FROM GD_SNAPSHOT_PROVEEDORES s
           WHERE s.RFC = d.RFC
             AND s.RUN_TS = (SELECT MAX (s2.RUN_TS) FROM GD_SNAPSHOT_PROVEEDORES s2
                              WHERE s2.DOMINIO = d.DOMINIO));


--==============================================================================
-- 3) AVANCE / OBSERVACION SAP  -  1 fila por RFC del ultimo snapshot ST
--==============================================================================
CREATE OR REPLACE VIEW V_GD_PROV_SAP_AVANCE AS
WITH ultimos AS (
   SELECT DOMINIO, MAX (RUN_TS) AS MX FROM GD_SNAPSHOT_PROVEEDORES GROUP BY DOMINIO
),
-- "Es BP" = el RFC EXISTE en XXVEND_PROVEEDORES (la tabla ya trae los BP de SAP,
-- XXVEND_ID_PRD viene vacio). CHR03 = lista de sociedades FI (separadas por coma)
-- donde el BP ya esta extendido. 1200 = FI de ST -> si NO aparece, falta extender.
bp AS (
   SELECT UPPER (XXVEND_TAX_ID1) AS RFC,
          MAX (CASE WHEN INSTR (',' || REPLACE (NVL (XXVEND__CHR03,' '),' ','') || ',', ',1200,') > 0
                    THEN 1 ELSE 0 END) AS EXT_1200,
          MAX (XXVEND__CHR03) AS FI_EXTENDIDO
     FROM QAD.XXVEND_PROVEEDORES
    GROUP BY UPPER (XXVEND_TAX_ID1)
)
SELECT s.RFC,
       s.DOMINIO,
       s.NOMBRE_CONSOLIDADO,
       s.TIPO_PROVEEDOR,
       CASE WHEN b.RFC IS NOT NULL THEN 1 ELSE 0 END AS ES_BP,
       NVL (b.EXT_1200, 0) AS EXT_1200,
       b.FI_EXTENDIDO,
       d.ESTADO AS DECISION,
       CASE
          WHEN b.RFC IS NOT NULL AND d.ESTADO = 'DESCARTAR' THEN 'CONTRADICCION'
          WHEN b.RFC IS NOT NULL AND b.EXT_1200 = 1         THEN 'MIGRADO_EXTENDIDO_1200'
          WHEN b.RFC IS NOT NULL                            THEN 'MIGRADO_FALTA_EXTENDER_1200'
          WHEN d.ESTADO = 'MIGRAR'                          THEN 'POR_CREAR'
          WHEN d.ESTADO = 'DESCARTAR'                       THEN 'DESCARTADO_OK'
          ELSE 'PENDIENTE'
       END AS ESTADO_SAP,
       CASE
          WHEN b.RFC IS NOT NULL AND b.EXT_1200 = 1
               THEN 'Ya es BP y extendido a FI 1200 (ST) - completo'
          WHEN b.RFC IS NOT NULL
               THEN 'Ya es BP (extendido a FI: ' || b.FI_EXTENDIDO || ') - FALTA extender a FI 1200 (ST)'
       END AS OBSERVACION
  FROM GD_SNAPSHOT_PROVEEDORES s
       JOIN ultimos u ON u.DOMINIO = s.DOMINIO AND u.MX = s.RUN_TS
       LEFT JOIN bp b ON b.RFC = s.RFC
       LEFT JOIN GD_DECISIONES_PROVEEDORES d ON d.RFC = s.RFC;
