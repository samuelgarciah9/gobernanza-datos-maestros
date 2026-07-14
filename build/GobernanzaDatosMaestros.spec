# -*- mode: python ; coding: utf-8 -*-
# Empaqueta la app PySide6 (run.py) en modo CARPETA (onedir): arranca rapido y
# reduce falsos positivos de antivirus. Resultado: dist/GobernanzaDatosMaestros/.
# El Instant Client y el .env NO van aqui: el instalador los copia junto al .exe
# (connection.base_dir() los busca ahi).

import os
from PyInstaller.utils.hooks import collect_all

# Raiz del proyecto (el .spec vive en build/)
PROJ = os.path.dirname(os.path.abspath(SPECPATH))

QT_EXCLUDES = [
    'PySide6.QtWebEngineCore', 'PySide6.QtWebEngineWidgets', 'PySide6.QtWebEngine',
    'PySide6.QtQuick', 'PySide6.QtQml', 'PySide6.Qt3DCore', 'PySide6.Qt3DRender',
    'PySide6.QtMultimedia', 'PySide6.QtMultimediaWidgets', 'PySide6.QtCharts',
    'PySide6.QtDataVisualization', 'PySide6.QtBluetooth', 'PySide6.QtPositioning',
    'PySide6.QtSensors', 'PySide6.QtSerialPort', 'PySide6.QtTest',
    'tkinter', 'streamlit', 'pandas', 'numpy', 'pyarrow', 'altair', 'matplotlib',
]

# oracledb carga modulos de forma dinamica (thick/thin): recogerlo completo.
ora_datas, ora_bins, ora_hidden = collect_all('oracledb')

a = Analysis(
    [os.path.join(PROJ, 'run.py')],
    pathex=[PROJ],
    binaries=ora_bins,
    datas=ora_datas,
    hiddenimports=ora_hidden + ['openpyxl', 'dotenv'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=QT_EXCLUDES,
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='GobernanzaDatosMaestros',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe, a.binaries, a.datas,
    strip=False, upx=True, upx_exclude=[],
    name='GobernanzaDatosMaestros',
)
