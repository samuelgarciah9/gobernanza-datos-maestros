--------------------------------------------------------------------------------
-- PASO 3  |  RECONCILIACION (MERGE)  -  clasifica cada material en buckets
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
--
-- Compara el ULTIMO snapshot por dominio contra las decisiones guardadas, por
-- llave (NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN), usando BANDERAS_HASH vs HASH_AL_DECIDIR.
--
-- Orden del hash: EXIST(1) DIST(2) PO(3) SO(4) WO(5) RET(6) INV_SEG(7) ULT_TXN(8).
-- Firmes = EXIST/PO/SO/WO/INV_SEG. Ligeras = DIST/RET. Recencia = ULT_TXN.
--
-- BUCKETS (V_GD_MERGE_MATERIALES, materiales presentes en el ultimo snapshot):
--   POR_DECIDIR : sin decision o ESTADO=PENDIENTE.
--   VIGENTE     : decision concluyente y hash igual, o cambio INMATERIAL.
--   RE_REVISAR  : decision concluyente y cambio que IMPORTA (disparador A o B).
-- Bucket 4 (V_GD_MERGE_SALIO): decision concluyente cuyo material ya NO esta
--   en el ultimo snapshot (perdio todas las senales).
--
-- Disparadores del bucket RE_REVISAR:
--   A) DESCARTAR -> POSIBLE_MIGRAR : aparece (0->1) EXIST, PO, SO o WO.
--   B) MIGRAR -> POSIBLE_DESCARTAR : se apagan TODAS las firmes.
--------------------------------------------------------------------------------


--==============================================================================
-- 1) VISTA DE MERGE  -  buckets 1/2/3 sobre el ultimo snapshot por dominio
--==============================================================================
CREATE OR REPLACE VIEW V_GD_MERGE_MATERIALES AS
WITH ultimos AS (
   SELECT PT_DOMAIN, MAX(RUN_TS) AS MX
     FROM GD_SNAPSHOT_MATERIALES
    GROUP BY PT_DOMAIN
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
          d.NUMERO_PRODUCTO_ANTIGUO AS DEC_MAT,
          NVL(d.HASH_AL_DECIDIR, '00000000') AS PREV_HASH,
          CASE WHEN d.ESTADO = 'DESCARTAR' AND (
                    (SUBSTR(NVL(d.HASH_AL_DECIDIR,'00000000'),1,1) = '0' AND s.HAS_EXIST = 1) OR
                    (SUBSTR(NVL(d.HASH_AL_DECIDIR,'00000000'),3,1) = '0' AND s.HAS_PO   = 1) OR
                    (SUBSTR(NVL(d.HASH_AL_DECIDIR,'00000000'),4,1) = '0' AND s.HAS_SO   = 1) OR
                    (SUBSTR(NVL(d.HASH_AL_DECIDIR,'00000000'),5,1) = '0' AND s.HAS_WO   = 1))
               THEN 1 ELSE 0 END AS TRIG_A,
          CASE WHEN d.ESTADO = 'MIGRAR' AND
                    s.HAS_EXIST = 0 AND s.HAS_PO = 0 AND s.HAS_SO = 0 AND
                    s.HAS_WO = 0 AND s.HAS_INV_SEG = 0
               THEN 1 ELSE 0 END AS TRIG_B
     FROM GD_SNAPSHOT_MATERIALES s
          JOIN ultimos u
             ON u.PT_DOMAIN = s.PT_DOMAIN AND u.MX = s.RUN_TS
          LEFT JOIN GD_DECISIONES_MATERIALES d
             ON d.NUMERO_PRODUCTO_ANTIGUO = s.NUMERO_PRODUCTO_ANTIGUO
            AND d.PT_DOMAIN = s.PT_DOMAIN
)
SELECT c.*,
       CASE
          WHEN c.DEC_MAT IS NULL OR c.DECISION_PREVIA = 'PENDIENTE' THEN 'POR_DECIDIR'
          WHEN c.BANDERAS_HASH = c.PREV_HASH                        THEN 'VIGENTE'
          WHEN c.TRIG_A = 1 OR c.TRIG_B = 1                         THEN 'RE_REVISAR'
          ELSE 'VIGENTE'
       END AS BUCKET,
       CASE WHEN c.DEC_MAT IS NOT NULL AND c.DECISION_PREVIA <> 'PENDIENTE'
                 AND c.BANDERAS_HASH <> c.PREV_HASH THEN
               CASE WHEN c.TRIG_A = 1 THEN 'POSIBLE_MIGRAR'
                    WHEN c.TRIG_B = 1 THEN 'POSIBLE_DESCARTAR' END
       END AS MOTIVO,
       CASE WHEN c.DEC_MAT IS NOT NULL AND c.HASH_PREVIO IS NOT NULL THEN
          TRIM(
             CASE WHEN SUBSTR(c.PREV_HASH,1,1) <> TO_CHAR(c.HAS_EXIST)   THEN (CASE WHEN c.HAS_EXIST=1   THEN '+' ELSE '-' END)||'EXIST '   END ||
             CASE WHEN SUBSTR(c.PREV_HASH,2,1) <> TO_CHAR(c.HAS_DIST)    THEN (CASE WHEN c.HAS_DIST=1    THEN '+' ELSE '-' END)||'DIST '    END ||
             CASE WHEN SUBSTR(c.PREV_HASH,3,1) <> TO_CHAR(c.HAS_PO)      THEN (CASE WHEN c.HAS_PO=1      THEN '+' ELSE '-' END)||'PO '      END ||
             CASE WHEN SUBSTR(c.PREV_HASH,4,1) <> TO_CHAR(c.HAS_SO)      THEN (CASE WHEN c.HAS_SO=1      THEN '+' ELSE '-' END)||'SO '      END ||
             CASE WHEN SUBSTR(c.PREV_HASH,5,1) <> TO_CHAR(c.HAS_WO)      THEN (CASE WHEN c.HAS_WO=1      THEN '+' ELSE '-' END)||'WO '      END ||
             CASE WHEN SUBSTR(c.PREV_HASH,6,1) <> TO_CHAR(c.HAS_RET)     THEN (CASE WHEN c.HAS_RET=1     THEN '+' ELSE '-' END)||'RET '     END ||
             CASE WHEN SUBSTR(c.PREV_HASH,7,1) <> TO_CHAR(c.HAS_INV_SEG) THEN (CASE WHEN c.HAS_INV_SEG=1 THEN '+' ELSE '-' END)||'INV_SEG ' END ||
             CASE WHEN SUBSTR(c.PREV_HASH,8,1) <> TO_CHAR(c.HAS_ULT_TXN) THEN (CASE WHEN c.HAS_ULT_TXN=1 THEN '+' ELSE '-' END)||'ULT_TXN ' END
          )
       END AS FLAGS_CAMBIADOS
  FROM clasif c;


--==============================================================================
-- 2) VISTA SALIO (bucket 4)  -  decision concluyente sin material en el ultimo snapshot
--==============================================================================
-- Nota de rendimiento: el anti-join pega DIRECTO a GD_SNAPSHOT_MATERIALES usando
-- el indice (NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN) y una subconsulta escalar para el
-- ultimo RUN_TS por dominio (indexada por (PT_DOMAIN, RUN_TS) y cacheada por Oracle,
-- solo 2 dominios). Evita materializar el snapshot completo (25k+ filas, 10 corridas).
CREATE OR REPLACE VIEW V_GD_MERGE_SALIO AS
SELECT d.NUMERO_PRODUCTO_ANTIGUO,
       d.PT_DOMAIN,
       d.ESTADO       AS DECISION,
       d.RAZON,
       d.DECIDIDO_POR,
       d.ROL,
       d.RUN_ID_AL_DECIDIR,
       d.FECHA_DECISION,
       CASE WHEN d.ESTADO = 'MIGRAR' THEN 'REVISAR' ELSE 'INFORMATIVO' END AS ATENCION
  FROM GD_DECISIONES_MATERIALES d
 WHERE d.ESTADO IN ('MIGRAR','DESCARTAR')
   AND NOT EXISTS (
          SELECT 1 FROM GD_SNAPSHOT_MATERIALES s
           WHERE s.NUMERO_PRODUCTO_ANTIGUO = d.NUMERO_PRODUCTO_ANTIGUO
             AND s.PT_DOMAIN = d.PT_DOMAIN
             AND s.RUN_TS = (SELECT MAX(s2.RUN_TS) FROM GD_SNAPSHOT_MATERIALES s2
                              WHERE s2.PT_DOMAIN = d.PT_DOMAIN));
