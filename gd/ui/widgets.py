"""Widgets a medida para reproducir el look del dashboard: tarjeta, KPI, medidor."""

from __future__ import annotations

from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QFrame, QHBoxLayout, QLabel, QVBoxLayout, QWidget, QSizePolicy,
)

from gd.ui.estilo import C, apply_shadow


class Card(QFrame):
    """Tarjeta blanca con borde, esquinas redondeadas y sombra suave."""

    def __init__(self, title: str | None = None, parent=None):
        super().__init__(parent)
        self.setObjectName("Card")
        apply_shadow(self)
        self.v = QVBoxLayout(self)
        self.v.setContentsMargins(18, 16, 18, 16)
        self.v.setSpacing(10)
        if title:
            lbl = QLabel(title)
            lbl.setObjectName("CardTitle")
            self.v.addWidget(lbl)

    def add(self, w):
        self.v.addWidget(w)
        return w


class KpiTile(QFrame):
    """Tile de indicador: fondo blanco, franja de acento a la izquierda."""

    def __init__(self, label: str, value: str, sub: str, accent: str,
                 highlight: bool = False, parent=None):
        super().__init__(parent)
        self._accent = accent
        self._hi = highlight
        apply_shadow(self)
        self.setMinimumHeight(92)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 14, 16, 14)
        lay.setSpacing(3)
        l1 = QLabel(label); l1.setObjectName("KpiLbl")
        l2 = QLabel(value); l2.setObjectName("KpiValHi" if highlight else "KpiVal")
        l3 = QLabel(sub); l3.setObjectName("KpiSub")
        lay.addWidget(l1); lay.addWidget(l2); lay.addWidget(l3)

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        border = QColor(C["accent"]) if self._hi else QColor(C["border"])
        p.setPen(QPen(border, 2 if self._hi else 1))
        p.setBrush(QColor(C["surface"]))
        p.drawRoundedRect(r, 14, 14)
        # franja de acento
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self._accent))
        p.drawRoundedRect(QRectF(r.x() + 1.5, r.y() + 10, 4, r.height() - 20), 2, 2)
        super().paintEvent(e)


class KpiSplitTile(QFrame):
    """Tile de indicador partido por dominio: una etiqueta y una fila por dominio
    (p. ej. ST / RSS), cada una con su valor. Misma piel que KpiTile."""

    def __init__(self, label: str, filas: list[tuple[str, str]], accent: str,
                 highlight: bool = False, parent=None):
        super().__init__(parent)
        self._accent = accent
        self._hi = highlight
        apply_shadow(self)
        self.setMinimumHeight(92)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 12, 16, 12)
        lay.setSpacing(4)
        l1 = QLabel(label); l1.setObjectName("KpiLbl")
        lay.addWidget(l1)
        for dom, valor in filas:
            row = QWidget(); h = QHBoxLayout(row)
            h.setContentsMargins(0, 0, 0, 0); h.setSpacing(6)
            ld = QLabel(dom); ld.setObjectName("KpiDom")
            lv = QLabel(valor)
            lv.setObjectName("KpiValHiSm" if highlight else "KpiValSm")
            h.addWidget(ld); h.addStretch(1); h.addWidget(lv)
            lay.addWidget(row)
        lay.addStretch(1)

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        border = QColor(C["accent"]) if self._hi else QColor(C["border"])
        p.setPen(QPen(border, 2 if self._hi else 1))
        p.setBrush(QColor(C["surface"]))
        p.drawRoundedRect(r, 14, 14)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self._accent))
        p.drawRoundedRect(QRectF(r.x() + 1.5, r.y() + 10, 4, r.height() - 20), 2, 2)
        super().paintEvent(e)


class MeterBar(QWidget):
    """Barra tipo medidor: track redondeado + segmentos de colores proporcionales.

    segmentos = lista de (color_hex, valor). El resto del track queda en gris.
    """

    def __init__(self, segmentos, total, height=12, parent=None):
        super().__init__(parent)
        self._segs = segmentos
        self._total = total or 1
        self.setFixedHeight(height)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def set_data(self, segmentos, total):
        self._segs = segmentos
        self._total = total or 1
        self.update()

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect())
        radius = r.height() / 2
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(C["track"]))
        p.drawRoundedRect(r, radius, radius)
        path = QPainterPath()
        path.addRoundedRect(r, radius, radius)
        p.setClipPath(path)
        x = r.x()
        for color, val in self._segs:
            w = r.width() * (val / self._total)
            if w <= 0:
                continue
            p.setBrush(QColor(color))
            p.drawRect(QRectF(x, r.y(), w + 0.5, r.height()))
            x += w


def _dot(color: str) -> QLabel:
    d = QLabel()
    d.setFixedSize(11, 11)
    d.setStyleSheet(f"background:{color}; border-radius:3px;")
    return d


def legend_row(color: str, label: str, value: str, pct: str) -> QWidget:
    w = QWidget()
    h = QHBoxLayout(w)
    h.setContentsMargins(0, 0, 0, 0)
    h.setSpacing(8)
    h.addWidget(_dot(color))
    ll = QLabel(label); ll.setStyleSheet(f"color:{C['text']}; background:transparent;")
    h.addWidget(ll)
    h.addStretch(1)
    lv = QLabel(value); lv.setStyleSheet(f"color:{C['text']}; font-weight:700; background:transparent;")
    h.addWidget(lv)
    lp = QLabel(pct); lp.setStyleSheet(f"color:{C['muted']}; background:transparent;")
    lp.setFixedWidth(54); lp.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
    h.addWidget(lp)
    return w


def stat_row(label: str, value_text: str, pct: float, color: str) -> QWidget:
    """Fila: etiqueta + valor arriba, barra proporcional abajo (para estados/figuras)."""
    w = QWidget()
    v = QVBoxLayout(w)
    v.setContentsMargins(0, 4, 0, 4)
    v.setSpacing(5)
    top = QWidget(); th = QHBoxLayout(top); th.setContentsMargins(0, 0, 0, 0)
    ll = QLabel(label); ll.setStyleSheet(f"color:{C['text']}; font-weight:600; background:transparent;")
    th.addWidget(ll); th.addStretch(1)
    lv = QLabel(value_text); lv.setStyleSheet(f"color:{C['text']}; font-weight:700; background:transparent;")
    th.addWidget(lv)
    v.addWidget(top)
    v.addWidget(MeterBar([(color, max(pct, 0))], 100, height=12))
    return w
