extends Control
## Pantalla de logros. Mismo lenguaje visual que el resto de menus: fondo con
## viñeta, tipografia Geizer, paneles oscuros con borde rojo y acentos en ascua.
##
## Arriba: progreso total. Debajo: filtros por categoria y una rejilla de dos
## columnas con todos los logros (los secretos se tapan hasta conseguirlos).

const FONT_PATH := "res://Assets/Fonts/Geizer.otf"

## Etiqueta de una linea. UIKit.label activa autowrap y, dentro de un contenedor,
## el ancho de calculo es 0: la altura minima se dispara y la pantalla se sale.
## Aqui el texto es corto, asi que se recorta con puntos suspensivos si no cabe.
func _txt(texto: String, tam: int, color: Color, fuente: bool = false) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	if fuente and ResourceLoader.exists(FONT_PATH):
		l.add_theme_font_override("font", load(FONT_PATH))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


var _filtro: String = ""
var _grid: GridContainer
var _filtros: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Achievements.suma("logros_vistos")

	var pic := UIKit.add_backdrop(self, "res://Assets/Images/menu_bg.png", 0.42)
	UIKit.animate_backdrop(pic)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_cabecera())
	root.add_child(_barra_total())
	root.add_child(_fila_filtros())

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_grid)
	root.add_child(scroll)

	root.add_child(_pie())
	_rellenar()


# --------------------------------------------------------------------------
# Cabecera y progreso
# --------------------------------------------------------------------------

func _cabecera() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var tit := _txt("LOGROS", 40, UIKit.COL_EMBER, true)
	head.add_child(tit)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)

	var der := VBoxContainer.new()
	der.add_theme_constant_override("separation", 0)
	der.alignment = BoxContainer.ALIGNMENT_CENTER
	var cont := _txt("%d / %d CONSEGUIDOS" % [Achievements.conseguidos(), Achievements.total()], 18, UIKit.COL_BONE, true)
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(cont)
	var monedas := _txt("+%d MONEDAS GANADAS" % Achievements.premio_total(), 13, UIKit.COL_EMBER)
	monedas.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(monedas)
	head.add_child(der)
	return head


func _barra_total() -> Control:
	var barra := ProgressBar.new()
	barra.max_value = float(Achievements.total())
	barra.value = float(Achievements.conseguidos())
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(0, 10)
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.1, 0.06, 0.06, 0.9)
	fondo.border_color = Color(0.35, 0.12, 0.09, 1.0)
	fondo.set_border_width_all(1)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = UIKit.COL_BLOOD
	relleno.border_color = UIKit.COL_EMBER
	relleno.set_border_width_all(0)
	barra.add_theme_stylebox_override("background", fondo)
	barra.add_theme_stylebox_override("fill", relleno)
	return barra


func _fila_filtros() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	fila.add_child(_tab("", "TODOS"))
	for c in Achievements.CATS:
		fila.add_child(_tab(str(c["id"]), str(c["nombre"])))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(sp)
	return fila


func _tab(id: String, texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 14)
	if ResourceLoader.exists(FONT_PATH):
		b.add_theme_font_override("font", load(FONT_PATH))
	b.add_theme_color_override("font_color", UIKit.COL_DIM)
	b.add_theme_color_override("font_hover_color", UIKit.COL_BONE)
	b.add_theme_color_override("font_focus_color", UIKit.COL_EMBER)
	b.add_theme_color_override("font_pressed_color", UIKit.COL_EMBER)
	_pintar_tab(b, false)
	b.pressed.connect(func() -> void:
		_filtro = id
		for clave in _filtros.keys():
			_pintar_tab(_filtros[clave], str(clave) == id)
		_rellenar()
	)
	_filtros[id] = b
	return b


func _pintar_tab(b: Button, activo: bool) -> void:
	for estado in ["normal", "hover", "focus", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.22, 0.05, 0.04, 0.85) if activo else Color(0.05, 0.03, 0.03, 0.55)
		s.border_color = UIKit.COL_EMBER if activo else Color(0.25, 0.08, 0.06, 1.0)
		s.border_width_left = 3
		s.set_border_width_all(1)
		s.border_width_left = 4 if activo else 2
		s.content_margin_left = 12.0
		s.content_margin_right = 14.0
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
		b.add_theme_stylebox_override(estado, s)


# --------------------------------------------------------------------------
# Rejilla de logros
# --------------------------------------------------------------------------

func _rellenar() -> void:
	for hijo in _grid.get_children():
		hijo.queue_free()
	for a in Achievements.de_categoria(_filtro):
		_grid.add_child(_tarjeta(a))


func _tarjeta(a: Dictionary) -> Control:
	var hecho: bool = Achievements.esta(str(a["id"]))
	var secreto: bool = bool(a.get("secreto", false))
	var oculto: bool = secreto and not hecho
	var color: Color = Achievements.color_rareza(a) if hecho or not secreto else UIKit.COL_DIM

	var panel := UIKit.panel(14)
	panel.custom_minimum_size = Vector2(0, 92)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if hecho:
		var st: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
		st.border_color = color
		panel.add_theme_stylebox_override("panel", st)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var izq := VBoxContainer.new()
	izq.add_theme_constant_override("separation", 3)
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(izq)

	var titulo := _txt("???" if oculto else str(a["nombre"]), 18, color, true)
	izq.add_child(titulo)

	var desc := "Logro secreto. Sigue jugando y aparecera." if oculto else str(a["desc"])
	izq.add_child(_txt(desc, 12, UIKit.COL_DIM))

	var barra := ProgressBar.new()
	barra.max_value = 1.0
	barra.value = 1.0 if hecho else Achievements.avance(a)
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(0, 6)
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.1, 0.06, 0.06, 0.95)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = color
	barra.add_theme_stylebox_override("background", fondo)
	barra.add_theme_stylebox_override("fill", relleno)
	izq.add_child(barra)

	var der := VBoxContainer.new()
	der.add_theme_constant_override("separation", 2)
	der.alignment = BoxContainer.ALIGNMENT_CENTER
	der.custom_minimum_size = Vector2(104, 0)
	h.add_child(der)

	var estado := "CONSEGUIDO" if hecho else ("???" if oculto else Achievements.texto_avance(a))
	var col_estado: Color = UIKit.COL_EMBER if hecho else UIKit.COL_DIM
	var l_estado := _txt(estado, 13, col_estado, true)
	l_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(l_estado)

	var l_rareza := _txt(Achievements.nombre_rareza(a) if not oculto else "SECRETO", 10, color)
	l_rareza.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(l_rareza)

	var l_premio := _txt("+%d" % int(a["premio"]), 15, UIKit.COL_EMBER if not oculto else UIKit.COL_DIM)
	l_premio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(l_premio)
	return panel


# --------------------------------------------------------------------------
# Pie
# --------------------------------------------------------------------------

func _pie() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 16)
	var back := UIKit.menu_button("VOLVER", "", 22)
	back.custom_minimum_size = Vector2(220, 48)
	back.pressed.connect(func() -> void: LobbyAudio.change_scene(get_tree(), "res://Levels/MainMenu.tscn"))
	fila.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(sp)
	var nota := _txt("Cada logro paga monedas una sola vez  ·  © 2026 xpe.nettt · Stealth Proyects", 11, UIKit.COL_DIM)
	nota.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(nota)
	return fila
