--------------------------------------------------------------------------------
-- PASO 2  |  TABLA DE DECISIONES  (una fila por material+dominio)
-- Proyecto : Gobernanza de Datos Maestros - Migracion SAP S/4HANA
-- Servidor : ERP-PROD (oracle-host.example / ORCLPDB1), esquema QAD
--
-- Persiste la CAPA DE DECISION HUMANA encima del snapshot. Solo cambia cuando
-- un humano decide o cambia de opinion. Clave (material, dominio) porque ST y
-- RSS se depuran por separado (un material puede migrar en ST y descartarse en RSS).
--------------------------------------------------------------------------------

-- 1) Catalogo de razones comunes (parte "lista" de la razon hibrida)
CREATE TABLE GD_CAT_RAZONES
(
   RAZON             VARCHAR2(200)  NOT NULL,
   ESTADO_SUGERIDO   VARCHAR2(12),
   ACTIVO            CHAR(1) DEFAULT 'S' NOT NULL,
   CONSTRAINT PK_GD_CAT_RAZONES PRIMARY KEY (RAZON),
   CONSTRAINT CK_GD_CAT_ACTIVO  CHECK (ACTIVO IN ('S','N')),
   CONSTRAINT CK_GD_CAT_ESTADO  CHECK (ESTADO_SUGERIDO IS NULL OR
                                       ESTADO_SUGERIDO IN ('MIGRAR','DESCARTAR','PENDIENTE'))
);


-- 2) Tabla de decisiones
CREATE TABLE GD_DECISIONES_MATERIALES
(
   NUMERO_PRODUCTO_ANTIGUO   VARCHAR2(30)   NOT NULL,   -- clave natural (une con snapshot)
   PT_DOMAIN                 VARCHAR2(8)    NOT NULL,   -- ST / RSS  (pista separada)

   ESTADO                    VARCHAR2(12)   DEFAULT 'PENDIENTE' NOT NULL,  -- catalogo CERRADO
   RAZON                     VARCHAR2(500),                                -- obligatoria si ESTADO<>PENDIENTE
   COMENTARIO                VARCHAR2(500),                                -- nota libre del revisor (opcional)

   DECIDIDO_POR              VARCHAR2(60),                 -- sellado por la capa de captura
   ROL                       VARCHAR2(12),                 -- COMPRAS/INVENTARIOS/INGENIERIA
   FECHA_DECISION            DATE,                         -- fecha de la decision

   HASH_AL_DECIDIR           VARCHAR2(8),                  -- huella del snapshot al decidir
   RUN_ID_AL_DECIDIR         VARCHAR2(40),                 -- foto exacta que vio el humano

   FECHA_ALTA                TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
   FECHA_ACTUALIZACION       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,

   CONSTRAINT PK_GD_DECISIONES  PRIMARY KEY (NUMERO_PRODUCTO_ANTIGUO, PT_DOMAIN),
   CONSTRAINT CK_GD_DEC_ESTADO  CHECK (ESTADO IN ('MIGRAR','DESCARTAR','PENDIENTE')),
   CONSTRAINT CK_GD_DEC_DOM     CHECK (PT_DOMAIN IN ('ST','RSS')),
   CONSTRAINT CK_GD_DEC_ROL     CHECK (ROL IS NULL OR ROL IN ('COMPRAS','INVENTARIOS','INGENIERIA')),
   -- Gobernanza: toda decision concluyente debe traer razon
   CONSTRAINT CK_GD_DEC_RAZON   CHECK (ESTADO = 'PENDIENTE' OR RAZON IS NOT NULL)
);

-- Indices para el tablero (Paso 5) y el merge (Paso 3)
CREATE INDEX IX_GD_DEC_ESTADO ON GD_DECISIONES_MATERIALES (ESTADO);
CREATE INDEX IX_GD_DEC_ROL    ON GD_DECISIONES_MATERIALES (ROL);
CREATE INDEX IX_GD_DEC_DOM    ON GD_DECISIONES_MATERIALES (PT_DOMAIN);

COMMENT ON TABLE  GD_DECISIONES_MATERIALES                     IS 'Paso 2: capa de decision humana (migrar/descartar) por material y dominio.';
COMMENT ON COLUMN GD_DECISIONES_MATERIALES.HASH_AL_DECIDIR     IS 'Huella del snapshot cuando se tomo la decision. El merge compara contra la huella actual para reactivar si cambio.';
COMMENT ON COLUMN GD_DECISIONES_MATERIALES.RUN_ID_AL_DECIDIR   IS 'RUN_ID del snapshot que vio el humano al decidir (trazabilidad exacta).';


-- 3) Trigger: mantiene FECHA_ACTUALIZACION en cada cambio
CREATE OR REPLACE TRIGGER TRG_GD_DEC_UPD
   BEFORE UPDATE ON GD_DECISIONES_MATERIALES
   FOR EACH ROW
BEGIN
   :NEW.FECHA_ACTUALIZACION := SYSTIMESTAMP;
END;
/
