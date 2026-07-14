"""Conexion a Oracle.

Las credenciales se leen del archivo `.env` (en la misma carpeta que este
archivo) o de las variables de entorno del sistema.

Uso rapido (prueba de conexion):
    python connection.py

Uso como libreria:
    from connection import get_connection
    with get_connection() as con:
        ...
"""

from __future__ import annotations

import os
from pathlib import Path

import oracledb
from dotenv import load_dotenv


# Raiz del proyecto = carpeta donde vive este archivo. Sin dependencia de
# un paquete/modulo externo (antes se importaba de .config, que no existe).
PROJECT_ROOT = Path(__file__).resolve().parent

# Carga el .env de la raiz del proyecto si existe (no sobrescribe variables
# de entorno ya definidas en el sistema).
load_dotenv(PROJECT_ROOT / ".env")


def _require(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(
            f"Falta la variable de entorno {name}. Revisa el archivo .env."
        )
    return value


USUARIO = _require("ORACLE_USER")
CONTRASENA = _require("ORACLE_PASSWORD")
HOST = _require("ORACLE_HOST")
PUERTO = int(_require("ORACLE_PORT"))
SID = _require("ORACLE_SID")


def _resolver_instant_client() -> str:
    """Ubica el Oracle Instant Client (modo Thick), en este orden:

    1) La variable ORACLE_CLIENT_LIB_DIR del .env, si apunta a una carpeta que existe.
    2) La carpeta 'instantclient' incluida junto al proyecto (paquete autocontenido).
    3) La variable del .env aunque no exista (para dar un error claro luego).
    """
    env_dir = os.getenv("ORACLE_CLIENT_LIB_DIR")
    if env_dir and Path(env_dir).is_dir():
        return env_dir
    bundled = PROJECT_ROOT / "instantclient"
    if bundled.is_dir():
        return str(bundled)
    if env_dir:
        return env_dir
    raise RuntimeError(
        "No se encontro el Oracle Instant Client. Define ORACLE_CLIENT_LIB_DIR en el .env "
        "o coloca la carpeta 'instantclient' junto al proyecto."
    )


def init_client() -> None:
    try:
        oracledb.init_oracle_client(lib_dir=_resolver_instant_client())
        print("Modo Thick de Oracle inicializado correctamente.")
    except oracledb.ProgrammingError:
        # Ya estaba inicializado; no es un error real.
        pass
    except Exception as e:  # noqa: BLE001
        print(f"Error al inicializar el cliente de Oracle: {e}")


def get_connection() -> oracledb.Connection:
    init_client()
    return oracledb.connect(
        user=USUARIO,
        password=CONTRASENA,
        host=HOST,
        port=PUERTO,
        sid=SID,
    )


if __name__ == "__main__":
    # Prueba de humo: conecta y valida contra el servidor.
    print(f"Conectando a {USUARIO}@{HOST}:{PUERTO}/{SID} ...")
    try:
        with get_connection() as con:
            with con.cursor() as cur:
                cur.execute(
                    "SELECT USER, SYSDATE FROM DUAL"
                )
                usuario_bd, fecha = cur.fetchone()
                print("OK - conexion exitosa.")
                print(f"   Usuario BD : {usuario_bd}")
                print(f"   Fecha serv : {fecha}")

                # Verifica que las vistas de depuracion ya existan
                cur.execute(
                    """
                    SELECT view_name
                      FROM all_views
                     WHERE view_name IN (
                           'V_GD_MATERIALES_DEP',
                           'V_GD_MATERIALES_ST',
                           'V_GD_MATERIALES_RSS',
                           'V_GD_MATERIALES_DUP_ST_RSS')
                     ORDER BY view_name
                    """
                )
                vistas = [r[0] for r in cur.fetchall()]
                if vistas:
                    print(f"   Vistas GD encontradas: {', '.join(vistas)}")
                else:
                    print("   (Aun no se ven las vistas GD desde este usuario.)")
    except Exception as e:  # noqa: BLE001
        print(f"FALLO la conexion: {e}")
