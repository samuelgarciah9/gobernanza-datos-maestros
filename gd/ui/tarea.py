"""Ejecuta una función en un hilo para no congelar la interfaz."""

from __future__ import annotations

from PySide6.QtCore import QThread, Signal


class Worker(QThread):
    ok = Signal(object)
    fail = Signal(str)

    def __init__(self, fn):
        super().__init__()
        self._fn = fn

    def run(self):
        try:
            self.ok.emit(self._fn())
        except Exception as e:  # noqa: BLE001
            self.fail.emit(str(e))


def correr(owner, fn, on_ok, on_error):
    """Corre fn() en un hilo. Guarda el worker en owner para evitar que lo recolecten."""
    w = Worker(fn)
    owner._worker = w
    w.ok.connect(on_ok)
    w.fail.connect(on_error)
    w.finished.connect(lambda: setattr(owner, "_worker", None))
    w.start()
