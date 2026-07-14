"""Sistema de diseño Qt: paleta (azul), QSS y sombras de tarjeta.

Reproduce el look de los dashboards aprobados (banner blanco con franja azul,
tarjetas, barras medidor). Tema claro fijo.
"""

from __future__ import annotations

from PySide6.QtGui import QColor
from PySide6.QtWidgets import QGraphicsDropShadowEffect

FONT_FAMILY = "Segoe UI"
RADIUS_CARD = 14
RADIUS_CTRL = 10

# Paleta (misma identidad que el dashboard aprobado)
C = {
    "bg": "#f1f3f6",
    "surface": "#ffffff",
    "surface_2": "#eef2f7",
    "border": "#e6e9ef",
    "border_strong": "#cdd6e2",
    "text": "#1f2733",
    "muted": "#6b7684",
    "faint": "#94a3b8",
    "track": "#e9edf2",
    "alt_row": "#f5f8fb",
    "accent": "#0d6efd",          # azul primario
    "accent_hover": "#0b5ed7",
    "accent_pressed": "#0a58ca",
    "accent_soft": "#e8f0ff",
    "green": "#1f9d55",
    "green_soft": "#e5f4ec",
    "red": "#d64545",
    "amber": "#e0a100",
    "blue_soft": "#7aa7ff",
    "slate": "#94a3b8",
    "gray": "#c3c9d2",
}


def apply_shadow(widget, *, blur: int = 26, y: int = 4):
    eff = widget.graphicsEffect()
    if not isinstance(eff, QGraphicsDropShadowEffect):
        eff = QGraphicsDropShadowEffect(widget)
        widget.setGraphicsEffect(eff)
    eff.setBlurRadius(blur)
    eff.setXOffset(0)
    eff.setYOffset(y)
    eff.setColor(QColor(16, 24, 40, 28))
    return eff


def build_stylesheet() -> str:
    p = C
    return f"""
    * {{ font-family: '{FONT_FAMILY}', 'Segoe UI Variable', system-ui; }}
    QMainWindow, QDialog, QWidget#Root {{ background-color: {p['bg']}; }}
    QWidget {{ color: {p['text']}; font-size: 13px; }}
    QScrollArea {{ border: none; background: transparent; }}
    QScrollArea > QWidget > QWidget {{ background: transparent; }}

    QFrame#Card {{
        background-color: {p['surface']};
        border: 1px solid {p['border']};
        border-radius: {RADIUS_CARD}px;
    }}

    QLabel#Title    {{ font-size: 22px; font-weight: 800; color: {p['text']}; background: transparent; }}
    QLabel#Subtitle {{ font-size: 13px; color: {p['muted']}; background: transparent; }}
    QLabel#Section  {{ font-size: 12px; font-weight: 800; color: {p['muted']}; background: transparent; }}
    QLabel#CardTitle{{ font-size: 14px; font-weight: 700; color: {p['text']}; background: transparent; }}
    QLabel#Muted    {{ color: {p['muted']}; font-size: 12px; background: transparent; }}
    QLabel#KpiLbl   {{ color: {p['muted']}; font-size: 12px; font-weight: 700; background: transparent; }}
    QLabel#KpiVal   {{ color: {p['text']}; font-size: 28px; font-weight: 800; background: transparent; }}
    QLabel#KpiValHi {{ color: {p['accent']}; font-size: 28px; font-weight: 800; background: transparent; }}
    QLabel#KpiSub   {{ color: {p['muted']}; font-size: 12px; background: transparent; }}
    QLabel#KpiDom   {{ color: {p['muted']}; font-size: 13px; font-weight: 700; background: transparent; }}
    QLabel#KpiValSm   {{ color: {p['text']};   font-size: 20px; font-weight: 800; background: transparent; }}
    QLabel#KpiValHiSm {{ color: {p['accent']}; font-size: 20px; font-weight: 800; background: transparent; }}
    QLabel#BigVal   {{ font-size: 30px; font-weight: 800; background: transparent; }}
    QLabel#Pill {{
        background-color: {p['accent_soft']}; color: {p['accent']};
        border: 1px solid #cfe0ff; border-radius: 11px;
        padding: 5px 12px; font-size: 12px; font-weight: 700;
    }}

    QPushButton#Primary {{
        background-color: {p['accent']}; color: #ffffff; border: none;
        border-radius: {RADIUS_CTRL}px; padding: 9px 18px; font-weight: 700; font-size: 13px;
    }}
    QPushButton#Primary:hover {{ background-color: {p['accent_hover']}; }}
    QPushButton#Primary:pressed {{ background-color: {p['accent_pressed']}; }}
    QPushButton#Primary:disabled {{ background-color: {p['border_strong']}; color: {p['surface']}; }}

    QPushButton#Ghost {{
        background-color: {p['surface']}; color: {p['text']};
        border: 1px solid {p['border_strong']}; border-radius: {RADIUS_CTRL}px;
        padding: 9px 16px; font-weight: 600; font-size: 13px;
    }}
    QPushButton#Ghost:hover {{ border-color: {p['accent']}; color: {p['accent']}; background-color: {p['accent_soft']}; }}
    QPushButton#Ghost:disabled {{ color: {p['faint']}; border-color: {p['border']}; }}

    /* Selector de entidad (Materiales | Proveedores) */
    QPushButton#SegOn {{
        background-color: {p['accent']}; color: #ffffff; border: 1px solid {p['accent']};
        padding: 5px 16px; font-weight: 700; font-size: 12px;
    }}
    QPushButton#SegOff {{
        background-color: {p['surface']}; color: {p['muted']}; border: 1px solid {p['border_strong']};
        padding: 5px 16px; font-weight: 600; font-size: 12px;
    }}
    QPushButton#SegOff:hover {{ color: {p['accent']}; border-color: {p['accent']}; }}

    QLineEdit, QComboBox {{
        background-color: {p['surface']}; border: 1px solid {p['border_strong']};
        border-radius: {RADIUS_CTRL}px; padding: 8px 12px; min-height: 20px;
        selection-background-color: {p['accent']}; selection-color: #fff;
    }}
    QLineEdit:focus, QComboBox:focus {{ border: 2px solid {p['accent']}; padding: 7px 11px; }}
    QComboBox::drop-down {{ border: none; width: 24px; }}
    QComboBox QAbstractItemView {{
        background: {p['surface']}; border: 1px solid {p['border_strong']};
        border-radius: 8px; selection-background-color: {p['accent_soft']}; selection-color: {p['accent']};
        outline: none;
    }}

    QTableWidget {{
        background-color: {p['surface']}; alternate-background-color: {p['alt_row']};
        border: 1px solid {p['border']}; border-radius: {RADIUS_CARD}px;
        gridline-color: {p['track']}; outline: none;
    }}
    QTableWidget::item {{ padding: 4px 8px; }}
    QHeaderView::section {{
        background-color: #16324f; color: #ffffff; padding: 8px 10px;
        border: none; border-right: 1px solid #23486b; font-weight: 700; font-size: 12px;
    }}
    QTableCornerButton::section {{ background: #16324f; border: none; }}

    QScrollBar:vertical {{ background: transparent; width: 12px; margin: 2px; }}
    QScrollBar::handle:vertical {{ background: {p['border_strong']}; border-radius: 5px; min-height: 30px; }}
    QScrollBar::handle:vertical:hover {{ background: {p['muted']}; }}
    QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; }}
    QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}
    """
