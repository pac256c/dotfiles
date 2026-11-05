#!/usr/bin/env python3
import os, sqlite3, subprocess, glob
from datetime import datetime
from PyQt6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout,
                             QLineEdit, QPushButton, QScrollArea, QGridLayout,
                             QLabel, QComboBox, QFrame, QSizePolicy, QToolButton,
                             QMenu, QButtonGroup, QRadioButton)
from PyQt6.QtGui import QPixmap, QFont, QIcon
from PyQt6.QtCore import Qt, QSize, QPropertyAnimation, QEasingCurve, QRect

DB = os.path.expanduser("~/.local/share/lutris/pga.db")
BANNER_DIRS = [
    os.path.expanduser("~/.local/share/lutris/banners"),
    os.path.expanduser("~/.local/share/lutris/coverart"),
    os.path.expanduser("~/.cache/lutris/banners"),
    os.path.expanduser("~/.cache/lutris/coverart"),
]
ACCENT = "#c4366c"
BG = "#2b2b2b"
SIDEBAR_BG = "#232323"

def find_banner(game):
    for d in BANNER_DIRS:
        for ext in (".jpg", ".png", ".jpeg", ".webp"):
            for key in (str(game["id"]), game.get("slug") or "", game.get("name") or ""):
                if not key:
                    continue
                p = os.path.join(d, key + ext)
                if os.path.exists(p):
                    return p
    for d in BANNER_DIRS:
        for key in (game.get("slug") or "", game.get("name") or ""):
            if not key:
                continue
            for p in glob.glob(os.path.join(d, key + "*")):
                if os.path.isfile(p):
                    return p
    return None

def find_platform_icon(platform):
    if not platform:
        return None
    name = platform.lower().replace(" ", "").replace("/", "_")
    base = os.path.expanduser("~/.local/share/lutris/runtime/icons")
    for sub in ("hicolor/64x64/apps", "hicolor/48x48/apps", "hicolor/32x32/apps",
                "hicolor/scalable/apps", "hicolor/symbolic/apps", "icons"):
        for ext in (".png", ".svg"):
            for n in (name, name + "-symbolic", name.replace("_", "")):
                p = os.path.join(base, sub, n + ext)
                if os.path.exists(p):
                    return p
    for root, _, files in os.walk(base):
        for fn in files:
            if fn.lower().startswith(name) and fn.lower().endswith((".png", ".svg")):
                return os.path.join(root, fn)
    return None

def fmt_time(ts):
    if not ts:
        return "Never"
    try:
        return datetime.fromtimestamp(int(ts)).strftime("%b %-d, %Y")
    except Exception:
        return str(ts)

def fmt_playtime(hours):
    if not hours:
        return "0 min"
    mins = int(hours * 60)
    h, m = divmod(mins, 60)
    if h:
        return f"{h}h {m}m"
    return f"{m}m"

def load_games():
    if not os.path.exists(DB):
        return []
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        "SELECT id,name,slug,platform,runner,installed,installed_at,lastplayed,playtime FROM games WHERE installed=1"
    ).fetchall()
    con.close()
    return [dict(r) for r in rows]

class GameCard(QWidget):
    def __init__(self, game, select_cb, parent=None):
        super().__init__(parent)
        self.game = game
        self.select_cb = select_cb
        self.selected = False
        self.setFixedSize(240, 180)
        v = QVBoxLayout(self)
        v.setContentsMargins(6, 6, 6, 6)
        v.setSpacing(4)
        self.art = QLabel()
        self.art.setFixedSize(228, 130)
        self.art.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.art.setStyleSheet("background:#3a3a3a; border-radius:6px;")
        self.art.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        bp = find_banner(game)
        if bp:
            pm = QPixmap(bp)
            if not pm.isNull():
                pm = pm.scaled(228, 130, Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                               Qt.TransformationMode.SmoothTransformation)
                self.art.setPixmap(pm)
        v.addWidget(self.art)
        self.name = QLabel(game["name"])
        self.name.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.name.setStyleSheet("color:#fcfcfc;")
        self.name.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        v.addWidget(self.name)
        self.setStyleSheet(f"QWidget {{ background:{BG}; border-radius:8px; }}")

    def set_selected(self, sel):
        self.selected = sel
        if sel:
            self.art.setStyleSheet(f"background:#3a3a3a; border:2px solid {ACCENT}; border-radius:6px;")
            self.name.setStyleSheet(f"color:{ACCENT}; font-weight:bold;")
        else:
            self.art.setStyleSheet("background:#3a3a3a; border-radius:6px;")
            self.name.setStyleSheet("color:#fcfcfc;")

    def mousePressEvent(self, e):
        if e.button() == Qt.MouseButton.LeftButton:
            self.select_cb(self.game, self)
        super().mousePressEvent(e)

    def mouseDoubleClickEvent(self, e):
        if e.button() == Qt.MouseButton.LeftButton:
            self.contract()
            subprocess.Popen(["lutris", f"lutris:rungameid/{self.game['id']}"])
        super().mouseDoubleClickEvent(e)

    def contract(self):
        orig = self.geometry()
        cx, cy = orig.center().x(), orig.center().y()
        w, h = int(orig.width()*0.9), int(orig.height()*0.9)
        shrunk = QRect(cx - w//2, cy - h//2, w, h)
        self._c1 = QPropertyAnimation(self, b"geometry")
        self._c1.setDuration(120)
        self._c1.setStartValue(orig)
        self._c1.setEndValue(shrunk)
        self._c1.setEasingCurve(QEasingCurve.Type.InOutQuad)
        self._c2 = QPropertyAnimation(self, b"geometry")
        self._c2.setDuration(120)
        self._c2.setStartValue(shrunk)
        self._c2.setEndValue(orig)
        self._c2.setEasingCurve(QEasingCurve.Type.InOutQuad)
        self._c1.finished.connect(self._c2.start)
        self._c1.start()

class DetailLine(QWidget):
    def __init__(self, title, parent=None):
        super().__init__(parent)
        v = QVBoxLayout(self)
        v.setContentsMargins(0, 0, 0, 0)
        v.setSpacing(0)
        self.title = QLabel(title)
        self.title.setStyleSheet("color:#aaa; font-size:10px; line-height:100%;")
        self.title.setFixedHeight(14)
        v.addWidget(self.title)
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(4)
        self.icon = QLabel()
        self.icon.hide()
        row.addWidget(self.icon)
        self.value = QLabel("")
        self.value.setStyleSheet("color:#fcfcfc; font-size:12px; line-height:100%; text-align:left;")
        self.value.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
        self.value.setFixedHeight(16)
        row.addWidget(self.value)
        v.addLayout(row)
        v.setAlignment(row, Qt.AlignmentFlag.AlignLeft)

    def set_value(self, text, icon=None):
        self.value.setText(text)
        if icon is not None:
            self.icon.setPixmap(icon)
            self.icon.show()
        else:
            self.icon.hide()


class CollapsibleSection(QWidget):
    def __init__(self, title, items, parent=None):
        super().__init__(parent)
        v = QVBoxLayout(self)
        v.setContentsMargins(0, 4, 0, 0)
        v.setSpacing(2)
        btn = QToolButton()
        btn.setText(title)
        btn.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        btn.setArrowType(Qt.ArrowType.DownArrow)
        btn.setCheckable(True)
        btn.setChecked(True)
        btn.setStyleSheet("QToolButton { border:none; color:#aaa; font-weight:bold; }")
        v.addWidget(btn)
        content = QWidget()
        cl = QVBoxLayout(content)
        cl.setContentsMargins(8, 0, 0, 0)
        cl.setSpacing(2)
        for it in items:
            lbl = QLabel(it)
            lbl.setStyleSheet("color:#fcfcfc; font-size:11px;")
            cl.addWidget(lbl)
        v.addWidget(content)
        def toggle():
            content.setVisible(btn.isChecked())
            btn.setArrowType(Qt.ArrowType.DownArrow if btn.isChecked() else Qt.ArrowType.RightArrow)
        btn.toggled.connect(lambda: toggle())
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)


class Window(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("My Games")
        self.resize(1000, 640)
        self.games = load_games()
        self.selected_card = None
        self.selected_game = None
        self.current_category = "All Games"
        self.sort_mode = "Title"
        self.view_mode = "Grid"
        self.selected_filter = None

        main = QHBoxLayout(self)
        main.setContentsMargins(0, 0, 0, 0)
        main.setSpacing(0)

        # Sidebar
        sidebar = QWidget()
        sidebar.setFixedWidth(180)
        sidebar.setStyleSheet(f"background:{SIDEBAR_BG};")
        sv = QVBoxLayout(sidebar)
        sv.setContentsMargins(8, 8, 8, 8)
        sv.setSpacing(6)
        # top icons
        iconrow = QHBoxLayout()
        lutris_btn = QPushButton("Lutris")
        lutris_btn.setFlat(True)
        lutris_btn.setIcon(QIcon("/usr/share/icons/Tela/scalable/apps/lutris.svg"))
        lutris_btn.setIconSize(QSize(16,16))
        lutris_btn.clicked.connect(lambda: subprocess.Popen(["lutris"]))
        iconrow.addWidget(lutris_btn)
        iconrow.addStretch()
        dots_btn = QPushButton("⋮")
        dots_btn.setFlat(True)
        dots_btn.setFixedSize(28,28)
        menu = QMenu()
        sort_menu = menu.addMenu("Sort By")
        self._sort_actions = []
        for opt in ("Title", "Date installed", "Date played"):
            act = sort_menu.addAction(opt)
            act.setCheckable(True)
            act.setChecked(opt == self.sort_mode)
            act.triggered.connect(lambda checked, o=opt: self.set_sort(o))
            self._sort_actions.append((opt, act))
        view_menu = menu.addMenu("View")
        self._view_actions = []
        for opt in ("Grid", "List"):
            act = view_menu.addAction(opt)
            act.setCheckable(True)
            act.setChecked(opt == self.view_mode)
            act.triggered.connect(lambda checked, o=opt: self.set_view(o))
            self._view_actions.append((opt, act))
        dots_btn.setMenu(menu)
        iconrow.addWidget(dots_btn)
        sv.addLayout(iconrow)
        # Library subtitle
        lib_row = QHBoxLayout()
        lib_label = QLabel("Library")
        lib_label.setStyleSheet("color:#aaa; font-size:11px; font-weight:bold;")
        lib_row.addWidget(lib_label)
        line = QFrame()
        line.setFrameShape(QFrame.Shape.HLine)
        line.setStyleSheet("background:#444;")
        line.setFixedHeight(1)
        lib_row.addWidget(line, 1)
        sv.addLayout(lib_row)
        icons = {"All Games":"🎮", "Recent":"🕒", "Favorites":"★"}
        self.cat_buttons = {}
        for cat in ("All Games", "Recent", "Favorites"):
            icons = {"All Games":"🎮", "Recent":"🕒", "Favorites":"★"}
            btn = QPushButton(f"  {icons[cat]}  {cat}")
            btn.setCheckable(True)
            btn.setStyleSheet(f"QPushButton {{ text-align:left; border:none; outline:none; background:transparent; color:#fcfcfc; padding:6px 10px; border-radius:4px; }} QPushButton:hover {{ background: palette(highlight); color: palette(highlighted-text); }} QPushButton:checked {{ background:{ACCENT}; color:#fff; font-weight:bold; }}")
            btn.filter = None
            btn.category = cat
            btn.clicked.connect(lambda checked, c=cat, b=btn: (self.set_category(c), self.select_sidebar_button(b)))
            btn.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
            sv.addWidget(btn)
            self.cat_buttons[cat] = btn
        self.cat_buttons["All Games"].setChecked(True)
        # collapsible sections
        def distinct(col):
            vals = set()
            for g in self.games:
                v = g.get(col)
                if v:
                    vals.add(v)
            return sorted(vals)
        sections = {
            "Sources": ("📦", "service", distinct("service")),
            "Runners": ("▶", "runner", distinct("runner")),
            "Platforms": ("💻", "platform", distinct("platform")),
        }
        self.sidebar_buttons = []
        # library buttons already added; track them
        for btn in self.cat_buttons.values():
            self.sidebar_buttons.append(btn)
        for title, (icon, col, items) in sections.items():
            sec_row = QHBoxLayout()
            sec_btn = QToolButton()
            sec_btn.setText(title)
            sec_btn.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
            sec_btn.setArrowType(Qt.ArrowType.DownArrow)
            sec_btn.setCheckable(True)
            sec_btn.setChecked(True)
            sec_btn.setStyleSheet("QToolButton { border:none; color:#aaa; font-weight:bold; }")
            sec_row.addWidget(sec_btn)
            sec_line = QFrame()
            sec_line.setFrameShape(QFrame.Shape.HLine)
            sec_line.setStyleSheet("background:#444;")
            sec_line.setFixedHeight(1)
            sec_row.addWidget(sec_line, 1)
            sv.addLayout(sec_row)
            content = QWidget()
            cl = QVBoxLayout(content)
            cl.setContentsMargins(8, 0, 0, 0)
            cl.setSpacing(2)
            for it in items:
                ip = find_platform_icon(it)
                btn = QPushButton(it.capitalize() if isinstance(it, str) else str(it))
                if ip:
                    btn.setIcon(QIcon(ip))
                btn.setCheckable(True)
                btn.setStyleSheet(f"QPushButton {{ text-align:left; border:none; background:transparent; color:#fcfcfc; padding:6px; border-radius:4px; outline:none; }} QPushButton:hover {{ background: palette(highlight); color: palette(highlighted-text); }} QPushButton:checked {{ background:{ACCENT}; color:#fff; font-weight:bold; }}")
                btn.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
                btn.filter = (col, it)
                btn.clicked.connect(lambda checked, b=btn: self.select_sidebar_button(b))
                cl.addWidget(btn)
                self.sidebar_buttons.append(btn)
            sv.addWidget(content)
            def toggle(checked, c=content, b=sec_btn):
                c.setVisible(checked)
                b.setArrowType(Qt.ArrowType.DownArrow if checked else Qt.ArrowType.RightArrow)
            sec_btn.toggled.connect(toggle)
        sv.addStretch()
        main.addWidget(sidebar)

        # Main area
        main_area = QWidget()
        mv = QVBoxLayout(main_area)
        mv.setContentsMargins(8, 8, 8, 8)
        mv.setSpacing(8)
        # search bar
        search_row = QHBoxLayout()
        search_icon = QLabel()
        search_icon.setPixmap(QPixmap("/usr/share/icons/Tela/scalable/actions/edit-find.svg").scaled(16,16,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        search_row.addWidget(search_icon)
        self.search = QLineEdit()
        self.search.setPlaceholderText(f"Search Games ({len(self.games)})...")
        self.search.setStyleSheet("background:#3a3a3a; color:#fcfcfc; border:none; border-radius:6px; padding:6px;")
        self.search.textChanged.connect(self.refresh)
        search_row.addWidget(self.search, 1)
        reload_btn = QPushButton()
        reload_btn.setFlat(True)
        reload_btn.setIcon(self.style().standardIcon(self.style().StandardPixmap.SP_BrowserReload))
        reload_btn.clicked.connect(self.refresh_data)
        search_row.addWidget(reload_btn)
        mv.addLayout(search_row)
        # scroll grid
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.container = QWidget()
        self.grid = QGridLayout(self.container)
        self.grid.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        self.scroll.setWidget(self.container)
        self.scroll.viewport().installEventFilter(self)
        self.container.installEventFilter(self)
        mv.addWidget(self.scroll, 1)
        # bottom detail
        self.detail = QFrame()
        self.detail.setStyleSheet(f"QFrame {{ background:{BG}; border:none; }}")
        self.detail.hide()
        outer = QVBoxLayout(self.detail)
        outer.setContentsMargins(12, 4, 12, 4)
        outer.setSpacing(4)
        self.game_title = QLabel("")
        self.game_title.setStyleSheet("color:#fcfcfc; font-size:20px; font-weight:bold;")
        outer.addWidget(self.game_title)
        row = QHBoxLayout()
        row.setSpacing(24)
        self.play_btn = QPushButton("Play")
        self.play_btn.setFixedWidth(60)
        self.play_btn.setStyleSheet(f"background:{ACCENT}; color:#fff; border:none; padding:2px 8px; border-radius:6px; font-weight:bold; font-size:13px; QPushButton:pressed {{ background:#a02448; }}")
        self.play_btn.clicked.connect(self.play_selected)
        row.addWidget(self.play_btn, 0, Qt.AlignmentFlag.AlignVCenter)
        row.addSpacing(24)
        self.d_platform = DetailLine("Platform:")
        self.d_last = DetailLine("Last played:")
        self.d_time = DetailLine("Time played:")
        right = QHBoxLayout()
        right.setSpacing(12)
        right.addWidget(self.d_platform)
        div1 = QFrame(); div1.setFixedWidth(1); div1.setFixedHeight(40); div1.setStyleSheet("background:#555;")
        right.addWidget(div1)
        right.addWidget(self.d_last)
        div2 = QFrame(); div2.setFixedWidth(1); div2.setFixedHeight(40); div2.setStyleSheet("background:#555;")
        right.addWidget(div2)
        right.addWidget(self.d_time)
        row.addLayout(right)
        outer.addLayout(row)
        mv.addWidget(self.detail)
        main.addWidget(main_area, 1)

        self.refresh()

    def set_sort(self, mode):
        self.sort_mode = mode
        for opt, act in getattr(self, "_sort_actions", []):
            act.setChecked(opt == mode)
        self.refresh()

    def set_view(self, mode):
        self.view_mode = mode
        for opt, act in getattr(self, "_view_actions", []):
            act.setChecked(opt == mode)
        self.refresh()

    def select_sidebar_button(self, btn):
        for b in getattr(self, "sidebar_buttons", []):
            if b is not btn:
                b.setChecked(False)
        btn.setChecked(True)
        if getattr(btn, "filter", None):
            self.selected_filter = btn.filter
            self.current_category = None
        else:
            self.selected_filter = None
            if hasattr(btn, "category"):
                self.current_category = btn.category

    def set_category(self, cat):
        self.current_category = cat
        self.selected_filter = None
        for name, btn in self.cat_buttons.items():
            btn.setChecked(name == cat)
        self.refresh()

    def filtered_games(self):
        games = list(self.games)
        if self.selected_filter:
            col, val = self.selected_filter
            games = [g for g in games if g.get(col) == val]
        if self.current_category == "Recent":
            games.sort(key=lambda g: g.get("lastplayed") or 0, reverse=True)
            games = games[:15]
        elif self.current_category == "Favorites":
            games = []
        q = self.search.text().lower()
        games = [g for g in games if q in (g["name"] or "").lower()]
        if self.sort_mode == "Title":
            games.sort(key=lambda g: (g["name"] or "").lower())
        elif self.sort_mode == "Date installed":
            games.sort(key=lambda g: g["installed_at"] or 0, reverse=True)
        else:
            games.sort(key=lambda g: g["lastplayed"] or 0, reverse=True)
        return games

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            self.play_selected()
            return
        super().keyPressEvent(event)

    def jiggle_icon(self, row):
        lbl = getattr(row, "icon_label", None)
        if lbl is None:
            return
        orig = lbl.geometry()
        offsets = (-6, 6, -4, 4, -2, 2, 0)
        # chain animations
        self._jig = []
        cur = orig
        for off in offsets:
            nxt = QRect(orig.x()+off, orig.y(), orig.width(), orig.height())
            anim = QPropertyAnimation(lbl, b"geometry")
            anim.setDuration(60)
            anim.setStartValue(cur)
            anim.setEndValue(nxt)
            self._jig.append(anim)
            cur = nxt
        for i in range(len(self._jig)-1):
            self._jig[i].finished.connect(self._jig[i+1].start)
        self._jig[0].start()

    def refresh_data(self):
        self.games = load_games()
        self.search.setPlaceholderText(f"🔍 Search Games ({len(self.games)})...")
        self.refresh()

    def refresh(self):
        while self.grid.count():
            item = self.grid.takeAt(0)
            w = item.widget()
            if w:
                w.deleteLater()
        self.selected_card = None
        self.selected_game = None
        self.detail.hide()
        games = self.filtered_games()
        if self.view_mode == "List":
            for i, g in enumerate(games):
                roww = QWidget()
                rl = QHBoxLayout(roww)
                rl.setContentsMargins(4, 2, 4, 2)
                icon_lbl = QLabel()
                icon_lbl.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
                roww.icon_label = icon_lbl
                bp = find_banner(g)
                if bp:
                    pm = QPixmap(bp).scaled(32, 32, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
                    icon_lbl.setPixmap(pm)
                else:
                    icon_lbl.setText("🎮")
                rl.addWidget(icon_lbl)
                name_lbl = QLabel(g["name"])
                name_lbl.setStyleSheet("color:#fcfcfc;")
                name_lbl.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
                rl.addWidget(name_lbl)
                rl.addStretch()
                roww.setStyleSheet("QWidget { background:#2b2b2b; } QWidget:hover { background: palette(highlight); }")
                roww.installEventFilter(self)
                # store game on widget
                roww.game = g
                self.grid.addWidget(roww, i, 0)
        else:
            cols = 4
            for i, g in enumerate(games):
                card = GameCard(g, self.select_game, self.container)
                card.installEventFilter(self)
                self.grid.addWidget(card, i // cols, i % cols)

    def eventFilter(self, obj, event):
        if event.type() == event.Type.MouseButtonPress:
            if isinstance(obj, GameCard):
                self.select_game(obj.game, obj)
                return True
            if hasattr(obj, "game") and not isinstance(obj, GameCard):
                self.select_game(obj.game, obj)
                return True
            self._deselect()

        return super().eventFilter(obj, event)

    def _deselect(self):
        if self.selected_card:
            if hasattr(self.selected_card, "set_selected"):
                self.selected_card.set_selected(False)
            else:
                self.selected_card.setStyleSheet("QWidget { background:#2b2b2b; }")
            self.selected_card = None
            self.selected_game = None
            self._anim = QPropertyAnimation(self.detail, b"maximumHeight")
            self._anim.setDuration(150)
            self._anim.setStartValue(self.detail.height())
            self._anim.setEndValue(0)
            self._anim.setEasingCurve(QEasingCurve.Type.InCubic)
            self._anim.finished.connect(self.detail.hide)
            self._anim.start()

    def select_game(self, game, card):
        if self.selected_card and self.selected_card is not card:
            if hasattr(self.selected_card, "set_selected"):
                self.selected_card.set_selected(False)
            else:
                self.selected_card.setStyleSheet("QWidget { background:#2b2b2b; }")
        self.selected_card = card
        self.selected_game = game
        if hasattr(card, "set_selected"):
            card.set_selected(True)
        else:
            card.setStyleSheet("QWidget { background: palette(highlight); }")
        self.game_title.setText(game["name"])
        ip = find_platform_icon(game.get("platform"))
        if ip:
            pm = QPixmap(ip).scaled(16,16,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation)
            self.d_platform.set_value(game.get("platform") or "Unknown", pm)
        else:
            self.d_platform.set_value(game.get("platform") or "Unknown")
        self.d_last.set_value(fmt_time(game.get("lastplayed")))
        self.d_time.set_value(fmt_playtime(game.get("playtime")))
        self.detail.setMaximumHeight(0)
        self.detail.show()
        self._anim = QPropertyAnimation(self.detail, b"maximumHeight")
        self._anim.setDuration(180)
        self._anim.setStartValue(0)
        self._anim.setEndValue(120)
        self._anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._anim.start()

    def play_selected(self):
        g = self.selected_game
        if not g or not self.selected_card:
            return
        if hasattr(self.selected_card, "contract"):
            self.selected_card.contract()
        else:
            self.jiggle_icon(self.selected_card)
        subprocess.Popen(["lutris", f"lutris:rungameid/{g['id']}"])

if __name__ == "__main__":
    app = QApplication([])
    app.setWindowIcon(QIcon("/usr/share/icons/Tela/scalable/apps/kpat.svg"))
    w = Window()
    w.setWindowIcon(QIcon("/usr/share/icons/Tela/scalable/apps/kpat.svg"))
    w.show()
    app.exec()
