"""Punto de entrada de la app de Gobernanza de Datos Maestros (PySide6).

Un solo ejecutable, dos ventanas según el argumento:
    run.py dashboard     -> panel del equipo de datos maestros (por defecto)
    run.py importador    -> app de captura para las figuras
"""

from __future__ import annotations

import datetime as dt
import sys

from PySide6.QtCore import Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox


def _ahora() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M")


class _DashCtrl:
    """Conecta los botones del dashboard con la lógica (en hilo)."""

    def __init__(self):
        self.win = None
        self.busy = False
        self.entidad = "materiales"

    def _cargar(self):
        """Carga los datos de la entidad actual."""
        if self.entidad == "proveedores":
            from gd.proveedores.datos import cargar_datos
        else:
            from gd.datos import cargar_datos
        return cargar_datos()

    def refresh(self):
        try:
            self.win.actualizar(self._cargar(), _ahora(), entidad=self.entidad)
        except Exception as e:  # noqa: BLE001
            QMessageBox.critical(self.win, "Error", str(e))

    def cambiar_entidad(self, nombre):
        if self.busy or nombre == self.entidad:
            return
        self.entidad = nombre
        self.refresh()

    def foto(self):
        if self.entidad == "proveedores":
            from gd.proveedores import proceso
            self._run(lambda: proceso.correr_foto(("ST",)), "Nueva foto de proveedores (ST) generada.")
        else:
            from gd import proceso
            self._run(proceso.correr_foto, "Nueva foto (snapshot) generada.")

    def excels(self):
        if self.busy:
            return
        if self.entidad == "proveedores":
            from gd.proveedores import exportador as exp
            titulo = "Elija la carpeta donde guardar los Excel de captura de proveedores"
        else:
            from gd import exportador as exp
            titulo = "Elija la carpeta donde guardar los Excel de captura"
        carpeta = QFileDialog.getExistingDirectory(
            self.win, titulo, str(exp.BASE / "entregables"))
        if not carpeta:
            return  # el usuario canceló
        self._run(lambda: exp.generar(destino=carpeta),
                  f"Excels de captura generados en:\n{carpeta}")

    def importar(self):
        if self.busy or self.entidad != "proveedores":
            return
        from PySide6.QtWidgets import QInputDialog
        ruta, _ = QFileDialog.getOpenFileName(
            self.win, "Elija el Excel de decisiones lleno", "", "Excel (*.xlsx)")
        if not ruta:
            return
        quien, ok = QInputDialog.getText(self.win, "Responsable", "Nombre de quien decide:")
        if not ok or not quien.strip():
            return
        from gd.proveedores import importar as imp

        def trabajo():
            decisiones, errores, sin = imp.leer_decisiones(ruta)
            if errores:
                raise ValueError("Errores en el Excel:\n- " + "\n- ".join(errores[:20]))
            if not decisiones:
                return ["No hay decisiones para cargar."]
            nuevas, act = imp.guardar_decisiones(decisiones, quien.strip())
            return [f"Cargadas {len(decisiones)} decisiones "
                    f"({nuevas} nuevas, {act} actualizadas). Filas sin decidir: {sin}."]

        self._run(trabajo, "Decisiones de proveedores importadas.")

    def reporte(self):
        from gd import reporte
        self._run(lambda: [str(reporte.generar_reporte())], "Reporte de avance generado.")

    def _run(self, fn, msg_ok):
        from gd.ui.tarea import correr
        if self.busy:
            return
        self.busy = True
        QGuiApplication.setOverrideCursor(Qt.WaitCursor)

        def ok(res):
            self.busy = False
            QGuiApplication.restoreOverrideCursor()
            detalle = "\n".join(res) if isinstance(res, list) else str(res or "")
            QMessageBox.information(self.win, "Listo", msg_ok + ("\n\n" + detalle if detalle else ""))
            self.refresh()

        def err(m):
            self.busy = False
            QGuiApplication.restoreOverrideCursor()
            QMessageBox.critical(self.win, "Error", m)

        correr(self.win, fn, ok, err)


def _crear_dashboard():
    from gd.datos import cargar_datos
    from gd.ui.dashboard import DashboardWindow
    ctrl = _DashCtrl()
    callbacks = {"foto": ctrl.foto, "excels": ctrl.excels,
                 "refresh": ctrl.refresh, "reporte": ctrl.reporte,
                 "importar": ctrl.importar, "cambiar_entidad": ctrl.cambiar_entidad}
    win = DashboardWindow(cargar_datos(), callbacks, _ahora())
    ctrl.win = win
    return win


def main():
    # Auto-test sin interfaz (para validar la conexión del .exe empaquetado):
    #   set GD_SELFTEST=1 && GobernanzaDatosMaestros.exe
    import os
    import tempfile
    if os.environ.get("GD_SELFTEST") == "1":
        marca = os.path.join(tempfile.gettempdir(), "gd_selftest.txt")
        try:
            from gd.conexion import _resolver_instant_client
            from gd.datos import cargar_datos
            cliente = _resolver_instant_client()
            d = cargar_datos()
            with open(marca, "w", encoding="utf-8") as f:
                f.write(f"OK\nCLIENTE: {cliente}\ncandidatos: {d['tot']}\n")
            sys.exit(0)
        except Exception as e:  # noqa: BLE001
            with open(marca, "w", encoding="utf-8") as f:
                f.write(f"FAIL\n{e}\n")
            sys.exit(2)

    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    modo = (sys.argv[1] if len(sys.argv) > 1 else "dashboard").lower()
    try:
        if modo == "importador":
            from gd.ui.importador import ImportadorWindow
            win = ImportadorWindow()
        else:
            win = _crear_dashboard()
    except Exception as e:  # noqa: BLE001
        QMessageBox.critical(None, "Error al iniciar", str(e))
        raise
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
