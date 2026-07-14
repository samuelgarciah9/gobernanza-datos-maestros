--------------------------------------------------------------------------------
-- PASO 1  |  TABLA SNAPSHOT DE MATERIALES  (append-only, separada por dominio)
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
-- Servidor : ERP-PROD (oracle-host.example / ORCLPDB1), esquema QAD
--
-- Alimentada desde la vista V_GD_MATERIALES_DEP (una fila por material+dominio).
-- Los tipos se HEREDAN de la vista via CTAS WHERE 1=0 (blindaje: cero desajuste
-- de anchos en la carga). BANDERAS_HASH y ES_OBSOLETO ya vienen de la vista.
--
-- Clave: una foto guarda una fila por (material, dominio). Por eso PT_DOMAIN
-- forma parte de la PK -> los materiales que existen en ST y en RSS (75 dup.)
-- NO colisionan dentro de una misma corrida.
--------------------------------------------------------------------------------

-- 1) Estructura: hereda columnas/tipos de la vista + 2 columnas de control
CREATE TABLE GD_SNAPSHOT_MATERIALES AS
SELECT CAST(NULL AS VARCHAR2(40)) AS RUN_ID,     -- ej. 'RUN_ST_20260707-154830'
       CAST(NULL AS TIMESTAMP)    AS RUN_TS,     -- timestamp de la foto
       v.*                                       -- todas las columnas de la vista
  FROM V_GD_MATERIALES_DEP v
 WHERE 1 = 0;                                    -- no copia datos, solo la estructura

-- 2) Llave primaria (foto + dominio + material)
ALTER TABLE GD_SNAPSHOT_MATERIALES
   ADD CONSTRAINT PK_GD_SNAPSHOT_MAT
   PRIMARY KEY (RUN_ID, PT_DOMAIN, NUMERO_PRODUCTO_ANTIGUO);

-- 3) Indices de apoyo (merge Paso 3 y tablero Paso 5)
CREATE INDEX IX_GD_SNAP_PART ON GD_SNAPSHOT_MATERIALES (NUMERO_PRODUCTO_ANTIGUO);
CREATE INDEX IX_GD_SNAP_DOM  ON GD_SNAPSHOT_MATERIALES (PT_DOMAIN);
CREATE INDEX IX_GD_SNAP_RUN  ON GD_SNAPSHOT_MATERIALES (RUN_ID);

-- 4) Carga de una corrida (por dominio). Desde Python se parametriza :run_id / :dom.
--    Insercion posicional: la tabla es [RUN_ID, RUN_TS] + columnas de la vista.
--    INSERT INTO GD_SNAPSHOT_MATERIALES
--    SELECT '&RUN_ID', SYSTIMESTAMP, v.*
--      FROM V_GD_MATERIALES_DEP v
--     WHERE v.PT_DOMAIN = '&DOMINIO';
--    COMMIT;
