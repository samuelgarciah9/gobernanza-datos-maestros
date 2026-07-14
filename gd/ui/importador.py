"""Ventana del Importador de Decisiones (las figuras que analizan)."""

from __future__ import annotations

from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import (
    QComboBox, QFileDialog, QFrame, QHBoxLayout, QLabel, QLineEdit, QMainWindow,
    QMessageBox, QPushButton, QVBoxLayout, QWidget,
)

from gd.conexion import BASE
from gd.importar import ROLES, cargar_config, guardar_config, guardar_decisiones, leer_decisiones
from gd.ui.estilo import C, apply_shadow, build_stylesheet
from gd.ui.tarea import correr
from gd.ui.widgets import Card, KpiTile


class _Banner(QFrame):
    def __init__(self, titulo, subtitulo, parent=None):
        super().__init__(parent)
        apply_shadow(self)
        self.setMinimumHeight(78)
        v = QVBoxLayout(self)
        v.setContentsMargins(26, 16, 26, 16)
        v.setSpacing(3)
        t = QLabel(titulo); t.setObjectName("Title")
        s = QLabel(subtitulo); s.setObjectName("Subtitle")
        v.addWidget(t); v.addWidget(s)

    def paintEvent(self, e):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        p.setPen(QPen(QColor(C["border"]), 1)); p.setBrush(QColor(C["surface"]))
        p.drawRoundedRect(r, 14, 14)
        p.setPen(Qt.NoPen); p.setBrush(QColor(C["accent"]))
        p.drawRoundedRect(QRectF(r.x() + 1.5, r.y() + 10, 5, r.height() - 20), 2, 2)
        super().paintEvent(e)


class ImportadorWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Importar Decisiones")
        self.resize(840, 640)
        self.setStyleSheet(build_stylesheet())
        self.archivo = None
        cfg = cargar_config()

        root = QWidget(); root.setObjectName("Root")
        outer = QVBoxLayout(root)
        outer.setContentsMargins(24, 20, 24, 24)
        outer.setSpacing(14)
        self.setCentralWidget(root)

        outer.addWidget(_Banner("📥  Importar Decisiones",
                                "Carga tu Excel de captura a la base · Gobernanza de Datos Maestros"))

        # -- Revisor --
        rev = Card("Revisor")
        form = QWidget(); fh = QHBoxLayout(form); fh.setContentsMargins(0, 0, 0, 0); fh.setSpacing(12)
        cn = QVBoxLayout(); cn.addWidget(QLabel("Nombre"))
        self.nombre = QLineEdit(); self.nombre.setPlaceholderText("Tu nombre completo")
        self.nombre.setText(cfg.get("nombre", "")); cn.addWidget(self.nombre)
        cr = QVBoxLayout(); cr.addWidget(QLabel("Rol"))
        self.rol = QComboBox(); self.rol.addItems(ROLES)
        if cfg.get("rol") in ROLES:
            self.rol.setCurrentText(cfg["rol"])
        cr.addWidget(self.rol)
        fh.addLayout(cn, 2); fh.addLayout(cr, 1)
        rev.add(form)
        outer.addWidget(rev)

        # -- Archivo --
        arch = Card("Archivo de decisiones (Excel)")
        ah = QWidget(); h = QHBoxLayout(ah); h.setContentsMargins(0, 0, 0, 0); h.setSpacing(10)
        self.ruta = QLineEdit(); self.ruta.setReadOnly(True)
        self.ruta.setPlaceholderText("(ningún archivo seleccionado)")
        btn_ex = QPushButton("Examinar…"); btn_ex.setObjectName("Ghost"); btn_ex.clicked.connect(self._examinar)
        h.addWidget(self.ruta, 1); h.addWidget(btn_ex)
        arch.add(ah)
        outer.addWidget(arch)

        # -- Cargar --
        self.btn = QPushButton("📤  Cargar decisiones"); self.btn.setObjectName("Primary")
        self.btn.setMinimumHeight(42); self.btn.clicked.connect(self._cargar)
        outer.addWidget(self.btn)

        # -- Resultado --
        self.resultado = QWidget(); self.res_lay = QVBoxLayout(self.resultado)
        self.res_lay.setContentsMargins(0, 0, 0, 0); self.res_lay.setSpacing(10)
        outer.addWidget(self.resultado)
        outer.addStretch(1)

    def _examinar(self):
        base = str(BASE / "entregables")
        ruta, _ = QFileDialog.getOpenFileName(self, "Selecciona tu Excel de decisiones", base, "Excel (*.xlsx)")
        if ruta:
            self.archivo = ruta
            self.ruta.setText(ruta)

    def _limpiar_resultado(self):
        while self.res_lay.count():
            it = self.res_lay.takeAt(0)
            if it.widget():
                it.widget().deleteLater()

    def _cargar(self):
        nombre = self.nombre.text().strip()
        rol = self.rol.currentText()
        if not nombre:
            QMessageBox.warning(self, "Falta el nombre", "Escribe tu nombre antes de cargar.")
            return
        if not self.archivo:
            QMessageBox.warning(self, "Falta el archivo", "Selecciona tu Excel de decisiones.")
            return
        self.btn.setEnabled(False)
        self.btn.setText("Cargando…")

        def trabajo():
            decisiones, errores, sin_decidir = leer_decisiones(self.archivo)
            nuevas = actualizadas = 0
            if decisiones:
                nuevas, actualizadas = guardar_decisiones(decisiones, nombre, rol)
            return {"nuevas": nuevas, "actualizadas": actualizadas,
                    "sin_decidir": sin_decidir, "errores": errores, "total": len(decisiones)}

        def ok(r):
            self.btn.setEnabled(True); self.btn.setText("📤  Cargar decisiones")
            if r["total"]:
                guardar_config(nombre, rol)
            self._mostrar_resultado(r)

        def err(m):
            self.btn.setEnabled(True); self.btn.setText("📤  Cargar decisiones")
            QMessageBox.critical(self, "Error al cargar", f"No se pudo completar la carga:\n\n{m}")

        correr(self, trabajo, ok, err)

    def _mostrar_resultado(self, r):
        self._limpiar_resultado()
        sec = QLabel("RESULTADO DE LA ÚLTIMA CARGA"); sec.setObjectName("Section")
        self.res_lay.addWidget(sec)
        row = QWidget(); g = QHBoxLayout(row); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(12)
        g.addWidget(KpiTile("Nuevas", f"{r['nuevas']:,}", "insertadas", C["green"]))
        g.addWidget(KpiTile("Actualizadas", f"{r['actualizadas']:,}", "modificadas", C["accent"]))
        g.addWidget(KpiTile("Sin decidir", f"{r['sin_decidir']:,}", "vacías", C["amber"]))
        g.addWidget(KpiTile("Con problema", f"{len(r['errores']):,}", "no cargadas", C["red"]))
        self.res_lay.addWidget(row)
        if r["errores"]:
            card = Card("Filas con problema (no se cargaron)")
            txt = QLabel("\n".join(f"• {e}" for e in r["errores"][:60]))
            txt.setWordWrap(True); txt.setStyleSheet(f"color:{C['muted']}; background:transparent;")
            card.add(txt)
            self.res_lay.addWidget(card)
