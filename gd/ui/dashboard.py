"""Ventana del Dashboard (equipo de datos maestros)."""

from __future__ import annotations

from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import (
    QFrame, QGridLayout, QHBoxLayout, QHeaderView, QLabel, QMainWindow,
    QPushButton, QScrollArea, QSizePolicy, QTableWidget, QTableWidgetItem,
    QVBoxLayout, QWidget,
)

from gd.ui.estilo import C, apply_shadow, build_stylesheet
from gd.ui.widgets import Card, KpiSplitTile, KpiTile, MeterBar, legend_row, stat_row


def _fmt(n) -> str:
    return f"{int(n):,}"


def _orden_dominios(doms) -> list[str]:
    """ST primero, luego RSS, luego el resto en orden alfabético."""
    prioridad = {"ST": 0, "RSS": 1}
    return sorted(doms, key=lambda d: (prioridad.get(d, 9), d))


class _Banner(QFrame):
    """Banner blanco con franja azul a la izquierda."""

    def __init__(self, parent=None):
        super().__init__(parent)
        apply_shadow(self)
        self.setMinimumHeight(104)

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        p.setPen(QPen(QColor(C["border"]), 1))
        p.setBrush(QColor(C["surface"]))
        p.drawRoundedRect(r, 14, 14)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(C["accent"]))
        p.drawRoundedRect(QRectF(r.x() + 1.5, r.y() + 10, 5, r.height() - 20), 2, 2)
        super().paintEvent(e)


def _section(text: str) -> QLabel:
    lbl = QLabel(text.upper())
    lbl.setObjectName("Section")
    return lbl


def _meter_card(title, big, big_color, big_sub, segmentos, total, legend_items) -> Card:
    card = Card(title)
    row = QWidget(); h = QHBoxLayout(row); h.setContentsMargins(0, 0, 0, 0); h.setSpacing(6)
    bv = QLabel(big); bv.setObjectName("BigVal")
    bv.setStyleSheet(f"color:{big_color}; background:transparent;")
    h.addWidget(bv)
    sub = QLabel(big_sub); sub.setObjectName("Muted"); sub.setAlignment(Qt.AlignBottom)
    h.addWidget(sub); h.addStretch(1)
    card.add(row)
    card.add(MeterBar(segmentos, total, height=12))
    for color, label, value, pct in legend_items:
        card.add(legend_row(color, label, value, pct))
    card.v.addStretch(1)
    return card


class DashboardWindow(QMainWindow):
    def __init__(self, data: dict, callbacks: dict | None = None, actualizado: str = "",
                 entidad: str = "materiales"):
        super().__init__()
        self.callbacks = callbacks or {}
        self.actualizado = actualizado
        self.entidad = entidad  # 'materiales' | 'proveedores'
        self.setWindowTitle("Gobernanza de Datos Maestros")
        self.resize(1200, 880)
        self.setStyleSheet(build_stylesheet())

        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.setCentralWidget(self.scroll)
        self._render(data)

    def actualizar(self, data: dict, actualizado: str = "", entidad: str | None = None):
        """Reconstruye el contenido con datos nuevos (Actualizar / cambio de entidad)."""
        if actualizado:
            self.actualizado = actualizado
        if entidad:
            self.entidad = entidad
        self._render(data)

    def _on_entidad(self, nombre: str):
        cb = self.callbacks.get("cambiar_entidad")
        if cb and nombre != self.entidad:
            cb(nombre)

    # -- construcción --
    def _render(self, data: dict):
        root = QWidget(); root.setObjectName("Root")
        outer = QVBoxLayout(root)
        outer.setContentsMargins(22, 20, 22, 22)
        outer.setSpacing(14)

        outer.addWidget(self._banner())
        outer.addWidget(self._kpis(data))
        outer.addWidget(self._progress(data))
        if self.entidad == "proveedores":
            outer.addWidget(_section("Resumen de revisión"))
            outer.addWidget(self._resumen_prov(data))
            outer.addWidget(_section("Situación de carga a SAP (Business Partner)"))
            outer.addWidget(self._sap_prov(data))
            outer.addWidget(_section("Detalle por sociedad"))
            outer.addWidget(self._tabla_prov(data))
        else:
            outer.addWidget(_section("Resumen visual"))
            outer.addWidget(self._resumen(data))
            outer.addWidget(self._detalle_cards(data))
            if data.get("sap"):
                outer.addWidget(_section("Avance de carga a SAP"))
                outer.addWidget(self._sap_kpis(data["sap"]))
                outer.addWidget(self._sap_resumen(data["sap"]))
            outer.addWidget(_section("Detalle de avance"))
            outer.addWidget(self._tabla(data))
        outer.addStretch(1)

        self.scroll.setWidget(root)

    def _banner(self) -> QWidget:
        es_prov = self.entidad == "proveedores"
        b = _Banner()
        h = QHBoxLayout(b); h.setContentsMargins(24, 14, 20, 14)
        left = QVBoxLayout(); left.setSpacing(3)
        t = QLabel("🧭  Gobernanza de Datos Maestros"); t.setObjectName("Title")
        sub = ("Depuración de proveedores · Sociedad ST · Migración SAP S/4HANA" if es_prov
               else "Depuración de materiales · Migración SAP S/4HANA")
        s = QLabel(sub); s.setObjectName("Subtitle")
        left.addWidget(t); left.addWidget(s)
        # Selector de entidad (Materiales | Proveedores)
        seg = QHBoxLayout(); seg.setSpacing(0); seg.setContentsMargins(0, 4, 0, 0)
        for nombre, etq in (("materiales", "Materiales"), ("proveedores", "Proveedores")):
            tb = QPushButton(etq)
            tb.setObjectName("SegOn" if nombre == self.entidad else "SegOff")
            tb.setCheckable(True); tb.setChecked(nombre == self.entidad)
            tb.setCursor(Qt.PointingHandCursor)
            tb.clicked.connect(lambda _=False, n=nombre: self._on_entidad(n))
            seg.addWidget(tb)
        seg.addStretch(1)
        left.addLayout(seg)
        h.addLayout(left); h.addStretch(1)

        right = QVBoxLayout(); right.setSpacing(8)
        pill = QLabel(f"Actualizado {self.actualizado}"); pill.setObjectName("Pill")
        pill.setAlignment(Qt.AlignRight)
        right.addWidget(pill, alignment=Qt.AlignRight)
        btns = QHBoxLayout(); btns.setSpacing(8)
        # Set de botones según entidad. Proveedores: foto/excels/importar/actualizar
        # (aún sin reporte). Materiales: foto/excels/actualizar/reporte.
        if es_prov:
            specs = [("foto", "▶  Correr foto", "Primary"), ("excels", "▶  Generar Excels", "Ghost"),
                     ("importar", "📥  Importar", "Ghost"), ("refresh", "🔄  Actualizar", "Ghost")]
        else:
            specs = [("foto", "▶  Correr foto", "Primary"), ("excels", "▶  Generar Excels", "Ghost"),
                     ("refresh", "🔄  Actualizar", "Ghost"), ("reporte", "📄  Reporte", "Ghost")]
        for name, etq, obj in specs:
            btn = QPushButton(etq); btn.setObjectName(obj)
            btn.setMinimumHeight(38)  # evita que el texto se recorte por DPI/escala
            btn.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
            cb = self.callbacks.get(name)
            if cb:
                btn.clicked.connect(cb)
            else:
                btn.setEnabled(False)
            btns.addWidget(btn)
        right.addLayout(btns)
        h.addLayout(right)
        return b

    def _kpis(self, d) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        doms = _orden_dominios(d.get("dominios", {}).keys())
        dom = d.get("dominios", {})

        def filas(fn):
            return [(dm, fn(dom[dm])) for dm in doms]

        tiles = [
            ("Total a revisar", filas(lambda x: _fmt(x["total"])), C["accent"], False),
            ("Ya decididos", filas(lambda x: _fmt(x["dec"])), C["green"], False),
            ("Pendientes", filas(lambda x: _fmt(x["pend"])), C["amber"], False),
            ("% Avance", filas(lambda x: f"{x['pct']:.1f}%"), C["accent"], True),
            ("Ya no aparecen", filas(lambda x: _fmt(x["salio"])), C["slate"], False),
        ]
        for lbl, fs, acc, hi in tiles:
            g.addWidget(KpiSplitTile(lbl, fs, acc, hi))
        return w

    def _progress(self, d) -> QWidget:
        titulo = ("Avance de decisiones por sociedad" if self.entidad == "proveedores"
                  else "Avance de decisiones por dominio")
        card = Card(titulo)
        dom = d.get("dominios", {})
        for dm in _orden_dominios(dom.keys()):
            x = dom[dm]
            card.add(stat_row(
                f"{dm}  ·  {_fmt(x['dec'])} / {_fmt(x['total'])}",
                f"{x['pct']:.1f}%", x["pct"], C["accent"]))
        if self.entidad == "proveedores" and "duplicados" in d:
            nota = QLabel(f"🔗  Duplicados ST ∩ RSS: {_fmt(d['duplicados'])} proveedores "
                          f"(mismo RFC en ambas sociedades · se deciden una sola vez)")
            nota.setObjectName("Muted")
            card.add(nota)
        card.v.addStretch(1)
        return card

    def _resumen(self, d) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        bk = d["buckets"]; fg = d["figuras"]; tot = max(d["tot"], 1)

        def pcts(v):
            return f"{100.0*v/tot:.1f}%"

        g.addWidget(_meter_card(
            "Avance global", f"{d['pct']:.1f}%", C["accent"], "decidido",
            [(C["accent"], d["dec"]), (C["gray"], d["pend"])], tot,
            [(C["accent"], "Decididos", _fmt(d["dec"]), pcts(d["dec"])),
             (C["gray"], "Pendientes", _fmt(d["pend"]), pcts(d["pend"]))]))

        vig, pod, rev = bk.get("VIGENTE", 0), bk.get("POR_DECIDIR", 0), bk.get("RE_REVISAR", 0)
        g.addWidget(_meter_card(
            "Clasificación de revisión", _fmt(d["tot"]), C["text"], "materiales",
            [(C["accent"], vig), (C["blue_soft"], pod), (C["slate"], rev)], tot,
            [(C["accent"], "Confirmado", _fmt(vig), pcts(vig)),
             (C["blue_soft"], "Por decidir", _fmt(pod), pcts(pod)),
             (C["slate"], "Cambió: re-revisar", _fmt(rev), pcts(rev))]))

        prod, noprod = fg.get("PRODUCTIVO", 0), fg.get("NO_PRODUCTIVO", 0)
        g.addWidget(_meter_card(
            "Por figura", str(len(fg)), C["text"], "figuras",
            [(C["green"], prod), (C["gray"], noprod)], tot,
            [(C["green"], "Productivo", _fmt(prod), pcts(prod)),
             (C["gray"], "No productivo", _fmt(noprod), pcts(noprod))]))
        return w

    def _detalle_cards(self, d) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        dec = max(d["dec"], 1)
        est = d["estados"]
        c1 = Card(f"Decisiones por estado")
        sub = QLabel(f"{_fmt(d['dec'])} decididos"); sub.setObjectName("Muted")
        c1.add(sub)
        c1.add(stat_row("Migrar", f"{_fmt(est['Migrar'])}   {100.0*est['Migrar']/dec:.1f}%",
                        100.0 * est["Migrar"] / dec, C["green"]))
        c1.add(stat_row("Descartar", f"{_fmt(est['Descartar'])}   {100.0*est['Descartar']/dec:.1f}%",
                        100.0 * est["Descartar"] / dec, C["red"]))
        c1.v.addStretch(1)
        g.addWidget(c1)

        c2 = Card("Avance por figura")
        for r in d["avance"]:
            fig = r["figura"].title().replace("_", " ")
            c2.add(stat_row(f"{r['dominio']} · {fig}",
                            f"{_fmt(r['decididos'])} / {_fmt(r['total'])}   {r['pct']:.0f}%",
                            r["pct"], C["accent"]))
        c2.v.addStretch(1)
        g.addWidget(c2)
        return w

    def _sap_kpis(self, s) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        cmp = s["cumplimiento"]
        tiles = [
            ("% en SAP", f"{s['pct']:.1f}%", "del universo maestro", C["accent"], True),
            ("En SAP", f"{_fmt(s['en_sap'])} / {_fmt(s['universo'])}", "materiales cargados", C["green"], False),
            ("Por cargar", _fmt(cmp["por_cargar"]), "decididos MIGRAR sin cargar", C["amber"], False),
            ("Contradicciones", _fmt(s["contradicciones"]), "en SAP pero se descartaron", C["red"], False),
            ("Fuera del universo", _fmt(s["huerfanos"]), "en SAP, fuera de lo gobernado", C["slate"], False),
        ]
        for lbl, val, sub, acc, hi in tiles:
            g.addWidget(KpiTile(lbl, val, sub, acc, hi))
        return w

    def _sap_resumen(self, s) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        universo = max(s["universo"], 1)
        resto = s["universo"] - s["en_sap"]

        g.addWidget(_meter_card(
            "Cobertura de carga", f"{s['pct']:.1f}%", C["green"], "en SAP",
            [(C["green"], s["en_sap"]), (C["gray"], resto)], universo,
            [(C["green"], "En SAP", _fmt(s["en_sap"]), f"{s['pct']:.1f}%"),
             (C["gray"], "Falta", _fmt(resto), f"{100.0*resto/universo:.1f}%")]))

        c2 = Card("Cobertura por dominio · figura")
        for r in s["por_dominio"]:
            fig = r["figura"].title().replace("_", " ")
            c2.add(stat_row(f"{r['dominio']} · {fig}",
                            f"{_fmt(r['en_sap'])} / {_fmt(r['universo'])}   {r['pct']:.0f}%",
                            r["pct"], C["green"]))
        c2.v.addStretch(1)
        g.addWidget(c2)

        cmp = s["cumplimiento"]
        c3 = Card("Comparación con las decisiones")
        sub = QLabel(f"{_fmt(cmp['migrar'])} decididos MIGRAR"); sub.setObjectName("Muted")
        c3.add(sub)
        c3.add(stat_row("Ya en SAP de lo decidido MIGRAR",
                        f"{_fmt(cmp['en_sap'])} / {_fmt(cmp['migrar'])}   {cmp['pct']:.0f}%",
                        cmp["pct"], C["accent"]))
        recon = s["recon"]; uni = max(s["universo"], 1)
        for lbl, key, color in (("Cargado sin decisión", "sin_decision", C["amber"]),
                                 ("Contradicciones", "contradicciones", C["red"])):
            val = s[key]
            c3.add(stat_row(lbl, f"{_fmt(val)}   {100.0*val/uni:.1f}%", 100.0 * val / uni, color))
        c3.v.addStretch(1)
        g.addWidget(c3)
        return w

    def _tabla(self, d) -> QWidget:
        cols = ["Dominio", "Figura", "Total", "Decididos", "Pendientes", "% Avance", "Migrar", "Descartar"]
        t = QTableWidget(len(d["avance"]), len(cols))
        t.setHorizontalHeaderLabels(cols)
        t.verticalHeader().setVisible(False)
        t.setAlternatingRowColors(True)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        t.setSelectionMode(QTableWidget.NoSelection)
        t.setFocusPolicy(Qt.NoFocus)
        t.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        t.setFixedHeight(46 + 34 * len(d["avance"]))
        apply_shadow(t)
        for i, r in enumerate(d["avance"]):
            vals = [r["dominio"], r["figura"].title().replace("_", " "), _fmt(r["total"]),
                    _fmt(r["decididos"]), _fmt(r["pendientes"]), f"{r['pct']:.1f}%",
                    _fmt(r["migrar"]), _fmt(r["descartar"])]
            for j, v in enumerate(vals):
                it = QTableWidgetItem(str(v))
                if j >= 2:
                    it.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                t.setItem(i, j, it)
        return t

    # ---- vistas específicas de PROVEEDORES ----
    def _resumen_prov(self, d) -> QWidget:
        w = QWidget(); g = QHBoxLayout(w); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        bk = d["buckets"]; est = d["estados"]; tot = max(d["tot"], 1)

        def pcts(v):
            return f"{100.0*v/tot:.1f}%"

        g.addWidget(_meter_card(
            "Avance global", f"{d['pct']:.1f}%", C["accent"], "decidido",
            [(C["accent"], d["dec"]), (C["gray"], d["pend"])], tot,
            [(C["accent"], "Decididos", _fmt(d["dec"]), pcts(d["dec"])),
             (C["gray"], "Pendientes", _fmt(d["pend"]), pcts(d["pend"]))]))

        vig, pod, rev = bk.get("VIGENTE", 0), bk.get("POR_DECIDIR", 0), bk.get("RE_REVISAR", 0)
        g.addWidget(_meter_card(
            "Clasificación de revisión", _fmt(d["tot"]), C["text"], "proveedores",
            [(C["accent"], vig), (C["blue_soft"], pod), (C["slate"], rev)], tot,
            [(C["accent"], "Confirmado", _fmt(vig), pcts(vig)),
             (C["blue_soft"], "Por decidir", _fmt(pod), pcts(pod)),
             (C["slate"], "Cambió: re-revisar", _fmt(rev), pcts(rev))]))

        mig, des = est["Migrar"], est["Descartar"]
        dec = max(d["dec"], 1)
        c = Card("Decisiones por estado")
        sub = QLabel(f"{_fmt(d['dec'])} decididos"); sub.setObjectName("Muted"); c.add(sub)
        c.add(stat_row("Migrar", f"{_fmt(mig)}   {100.0*mig/dec:.1f}%", 100.0*mig/dec, C["green"]))
        c.add(stat_row("Descartar", f"{_fmt(des)}   {100.0*des/dec:.1f}%", 100.0*des/dec, C["red"]))
        c.v.addStretch(1)
        g.addWidget(c)
        return w

    def _sap_prov(self, d) -> QWidget:
        s = d["sap"]; tot = max(d["tot"], 1)
        cont = QWidget(); v = QVBoxLayout(cont); v.setContentsMargins(0, 0, 0, 0); v.setSpacing(14)

        kp = QWidget(); g = QHBoxLayout(kp); g.setContentsMargins(0, 0, 0, 0); g.setSpacing(14)
        tiles = [
            ("Falta extender a FI 1200", _fmt(s.get("MIGRADO_FALTA_EXTENDER_1200", 0)), "ya es BP, extender a ST", C["amber"], True),
            ("Extendido a FI 1200", _fmt(s.get("MIGRADO_EXTENDIDO_1200", 0)), "BP completo en ST", C["green"], False),
            ("Por crear (BP nuevo)", _fmt(s.get("POR_CREAR", 0)), "decidido migrar, sin BP", C["accent"], False),
            ("Pendiente", _fmt(s.get("PENDIENTE", 0)), "sin decidir", C["slate"], False),
            ("Contradicción", _fmt(s.get("CONTRADICCION", 0)), "es BP y DESCARTAR", C["red"], False),
        ]
        for lbl, val, sub, acc, hi in tiles:
            g.addWidget(KpiTile(lbl, val, sub, acc, hi))
        v.addWidget(kp)

        c = Card("Observación de carga a SAP")
        orden = [("MIGRADO_FALTA_EXTENDER_1200", "Ya es BP · FALTA extender a FI 1200 (ST)", C["amber"]),
                 ("MIGRADO_EXTENDIDO_1200", "Ya es BP · extendido a FI 1200 (completo)", C["green"]),
                 ("POR_CREAR", "Por crear como BP nuevo", C["accent"]),
                 ("DESCARTADO_OK", "Descartado (sin actividad)", C["slate"]),
                 ("PENDIENTE", "Pendiente de decidir", C["muted"] if "muted" in C else C["slate"]),
                 ("CONTRADICCION", "Contradicción (es BP y se descartó)", C["red"])]
        for key, lbl, color in orden:
            val = s.get(key, 0)
            c.add(stat_row(lbl, f"{_fmt(val)}   {100.0*val/tot:.1f}%", 100.0*val/tot, color))
        c.v.addStretch(1)
        v.addWidget(c)
        return cont

    def _tabla_prov(self, d) -> QWidget:
        doms = _orden_dominios(d.get("dominios", {}).keys())
        cols = ["Sociedad", "Total", "Decididos", "Pendientes", "% Avance", "Migrar", "Descartar", "Salió"]
        t = QTableWidget(len(doms), len(cols))
        t.setHorizontalHeaderLabels(cols)
        t.verticalHeader().setVisible(False)
        t.setAlternatingRowColors(True)
        t.setEditTriggers(QTableWidget.NoEditTriggers)
        t.setSelectionMode(QTableWidget.NoSelection)
        t.setFocusPolicy(Qt.NoFocus)
        t.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        t.setFixedHeight(46 + 34 * max(len(doms), 1))
        apply_shadow(t)
        for i, dm in enumerate(doms):
            x = d["dominios"][dm]
            vals = [dm, _fmt(x["total"]), _fmt(x["dec"]), _fmt(x["pend"]), f"{x['pct']:.1f}%",
                    _fmt(x["migrar"]), _fmt(x["descartar"]), _fmt(x["salio"])]
            for j, val in enumerate(vals):
                it = QTableWidgetItem(str(val))
                if j >= 1:
                    it.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                t.setItem(i, j, it)
        return t
