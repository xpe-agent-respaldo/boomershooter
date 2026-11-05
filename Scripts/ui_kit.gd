class_name UIKit
extends RefCounted
## Lenguaje visual unico de Boomer Shooter para TODOS los menus.
## Fondo a pantalla completa con viñeta, columnas alineadas a la izquierda,
## botones con barra lateral roja y tipografia Geizer. Nada de cajas centradas.

const FONT_PATH := "res://Assets/Fonts/Geizer.otf"
const COL_BLOOD := Color(0.72, 0.1, 0.07, 1.0)
const COL_EMBER := Color(1.0, 0.42, 0.12, 1.0)
const COL_BONE := Color(0.93, 0.86, 0.76, 1.0)
const COL_DIM := Color(0.6, 0.5, 0.45, 1.0)
const COL_PANEL := Color(0.03, 0.02, 0.025, 0.86)


static func font() -> Font:
	return load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null


static func label(text_value: String, size: int, color: Color = COL_BONE, use_font: bool = false) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if use_font and font():
		l.add_theme_font_override("font", font())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Fondo inmersivo: imagen a pantalla completa + viñeta + oscurecido. Devuelve el TextureRect para animarlo.
static func add_backdrop(root: Control, texture_path: String, dim: float = 0.45) -> TextureRect:
	var base := ColorRect.new()
	base.color = Color(0.01, 0.005, 0.005)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(base)
	var pic := TextureRect.new()
	pic.texture = load(texture_path)
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.pivot_offset = Vector2(960, 540)
	root.add_child(pic)
	# oscurecido general
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	# degradado lateral izquierdo: da lectura a la columna de opciones
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.92))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 512
	gt.height = 8
	var left := TextureRect.new()
	left.texture = gt
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.anchor_right = 0.62
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	# viñeta de bordes
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0))
	vg.set_color(1, Color(0, 0, 0, 0.78))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 1.0)
	vt.width = 512
	vt.height = 512
	var vig := TextureRect.new()
	vig.texture = vt
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	return pic


## Zoom lento y deriva del fondo para que el menu "respire".
static func animate_backdrop(pic: TextureRect) -> void:
	pic.scale = Vector2(1.04, 1.04)
	var tw := pic.create_tween().set_loops()
	tw.tween_property(pic, "scale", Vector2(1.10, 1.10), 14.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(pic, "position", Vector2(-26, -14), 14.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pic, "scale", Vector2(1.04, 1.04), 14.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(pic, "position", Vector2(0, 0), 14.0).set_trans(Tween.TRANS_SINE)


static func _box(color: Color, left_bar: Color = Color(0, 0, 0, 0), bar_width: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = left_bar
	s.border_width_left = bar_width
	s.content_margin_left = 22.0 + bar_width
	s.content_margin_right = 18.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	return s


## Boton de menu: plano, texto a la izquierda, barra roja y brillo al enfocar.
static func menu_button(title: String, subtitle: String = "", size: int = 38) -> Button:
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 74 if subtitle != "" else 56)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	if font():
		b.add_theme_font_override("font", font())
	b.add_theme_color_override("font_color", COL_BONE)
	b.add_theme_color_override("font_hover_color", Color(1, 0.8, 0.55))
	b.add_theme_color_override("font_focus_color", Color(1, 0.8, 0.55))
	b.add_theme_color_override("font_pressed_color", Color(1, 0.55, 0.3))
	b.add_theme_stylebox_override("normal", _box(Color(0.05, 0.03, 0.03, 0.55), Color(0.25, 0.08, 0.06), 4))
	b.add_theme_stylebox_override("hover", _box(Color(0.22, 0.05, 0.04, 0.82), COL_EMBER, 8))
	b.add_theme_stylebox_override("focus", _box(Color(0.22, 0.05, 0.04, 0.82), COL_EMBER, 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.38, 0.07, 0.05, 0.92), COL_EMBER, 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.04, 0.03, 0.03, 0.4), Color(0.15, 0.1, 0.1), 4))
	if subtitle != "":
		b.tooltip_text = subtitle
	return b


## Panel oscuro con borde fino rojo y esquina marcada.
static func panel(padding: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.border_color = Color(0.45, 0.09, 0.06, 1.0)
	s.set_border_width_all(2)
	s.border_width_top = 4
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding - 4
	s.content_margin_bottom = padding - 4
	p.add_theme_stylebox_override("panel", s)
	return p


static func divider() -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 2)
	d.color = Color(0.55, 0.08, 0.06, 0.8)
	return d


## Logo del juego sin efectos extra: solo el texto, sin goteos ni degradados.
static func logo(height: int = 130) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://Assets/Brand/logo_title.png")
	var tex: Texture2D = t.texture
	var ratio := float(tex.get_width()) / float(tex.get_height()) if tex else 5.5
	t.custom_minimum_size = Vector2(height * ratio, height)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return t
