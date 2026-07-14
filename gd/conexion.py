"""Conexión a Oracle (modo Thick), consciente de PyInstaller.

- En desarrollo, la base de recursos (.env, instantclient/) es la raíz del proyecto.
- Congelado (.exe), es la carpeta del ejecutable (ahí los pone el instalador).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import oracledb
from dotenv import load_dotenv


def base_dir() -> Path:
    """Carpeta base de recursos (.env, instantclient/, entregables/)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


BASE = base_dir()
load_dotenv(BASE / ".env")


def _require(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Falta la variable de entorno {name}. Revisa el archivo .env.")
    return value


def _resolver_instant_client() -> str:
    """Ubica el Instant Client. Prioriza la carpeta 'instantclient' incluida (el
    cliente 19.30 que sabemos bueno) sobre el .env, para no depender de clientes
    Oracle viejos que pueda tener la máquina."""
    bundled = BASE / "instantclient"
    if bundled.is_dir():
        return str(bundled)
    env_dir = os.getenv("ORACLE_CLIENT_LIB_DIR")
    if env_dir and Path(env_dir).is_dir():
        return env_dir
    if env_dir:
        return env_dir
    raise RuntimeError(
        "No se encontró el Oracle Instant Client. Coloca la carpeta 'instantclient' "
        "junto a la aplicación o define ORACLE_CLIENT_LIB_DIR en el .env."
    )


_iniciado = False


def init_client() -> None:
    """Inicializa el cliente Thick forzando NUESTRA carpeta primero en la búsqueda
    de DLLs. Evita DPI-1072 cuando la máquina tiene un cliente Oracle 10g/11g viejo
    en el PATH (sus DLLs dependientes se cargarían en vez de las del 19.30)."""
    global _iniciado
    if _iniciado:
        return
    libdir = _resolver_instant_client()
    if os.name == "nt":
        os.environ["PATH"] = libdir + os.pathsep + os.environ.get("PATH", "")
        try:
            os.add_dll_directory(libdir)
        except (OSError, AttributeError):
            pass
    try:
        oracledb.init_oracle_client(lib_dir=libdir)
    except oracledb.ProgrammingError:
        pass  # ya estaba inicializado
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(
            f"No se pudo iniciar el cliente Oracle desde:\n{libdir}\n\n{e}"
        ) from e
    _iniciado = True


def get_connection() -> oracledb.Connection:
    init_client()
    return oracledb.connect(
        user=_require("ORACLE_USER"),
        password=_require("ORACLE_PASSWORD"),
        host=_require("ORACLE_HOST"),
        port=int(_require("ORACLE_PORT")),
        sid=_require("ORACLE_SID"),
    )
