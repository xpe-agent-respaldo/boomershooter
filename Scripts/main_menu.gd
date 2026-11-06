class_name MainMenu
extends Control
## Menu principal. Se construye por codigo con UIKit para compartir el mismo
## lenguaje visual con Lobby, Arena y Ajustes.

const BACKDROP := "res://Assets/Images/menu_bg.png"

var online_button: Button
var version_label: Label

var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	if online_button:
		online_button.grab_focus()
	_intro_animation()


func _build() -> void:
	var pic := UIKit.add_backdrop(self, BACKDROP, 0.28)
	UIKit.animate_backdrop(pic)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	# cabecera: logo + ajustes
	var head := HBoxContainer.new()
	root.add_child(head)
	var logo := UIKit.logo(120)
	head.add_child(logo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var settings := UIKit.menu_button("AJUSTES", "", 24)
	settings.custom_minimum_size = Vector2(190, 52)
	settings.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	settings.pressed.connect(func() -> void: GameSettings.toggle_settings())
	head.add_child(settings)

	# cuerpo: columna de modos a la izquierda, panel de novedades a la derecha
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 56)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)

	left.add_child(UIKit.label("// SELECCIONA MODO", 16, UIKit.COL_DIM))
	online_button = _mode("01  ONLINE", "Salas publicas, cooperativo y escuadrones", func() -> void:
		LobbyAudio.change_scene(get_tree(), "res://Levels/Lobby.tscn"))
	left.add_child(online_button)
	left.add_child(_mode("02  ARENA", "Entrena offline contra oleadas", func() -> void:
		LobbyAudio.change_scene(get_tree(), "res://Levels/ArenaSelect.tscn")))
	left.add_child(_mode("03  TIENDA", "Skins del personaje con monedas", func() -> void:
		LobbyAudio.change_scene(get_tree(), "res://Levels/Shop.tscn")))
	left.add_child(_mode("04  LOGROS", "Objetivos y premios en monedas", func() -> void:
		LobbyAudio.change_scene(get_tree(), "res://Levels/Achievements.tscn")))
	left.add_child(UIKit.divider())
	var exit := UIKit.menu_button("SALIR", "", 26)
	exit.pressed.connect(func() -> void: get_tree().quit())
	left.add_child(exit)
	_buttons = [online_button]

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grow)

	var news := UIKit.panel(22)
	news.custom_minimum_size = Vector2(380, 0)
	news.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 10)
	news.add_child(nv)
	nv.add_child(UIKit.label("ESTADO DEL SERVIDOR", 15, UIKit.COL_DIM))
	nv.add_child(UIKit.label("EN LINEA", 30, UIKit.COL_EMBER, true))
	nv.add_child(UIKit.divider())
	for line in ["Coop por oleadas: elites, hordas y jefes", "Alertas de equipo: H ayuda, G marcar", "Logros y ranking en tu cuenta"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.color = UIKit.COL_BLOOD
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var t := UIKit.label(line, 17)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		nv.add_child(row)
	body.add_child(news)

	# pie
	var foot := HBoxContainer.new()
	root.add_child(foot)
	var copy := UIKit.label("© 2026 xpe.nettt · Stealth Proyects", 16, UIKit.COL_DIM)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(copy)
	version_label = UIKit.label("", 16, UIKit.COL_DIM)
	foot.add_child(version_label)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	version_label.text = "v" + version if version != "" else ""



func _mode(title: String, subtitle: String, action: Callable) -> Button:
	var b := UIKit.menu_button(title, subtitle, 44)
	b.custom_minimum_size = Vector2(0, 92)
	b.text = "%s\n%s" % [title, subtitle]
	b.add_theme_font_size_override("font_size", 40)
	b.pressed.connect(action)
	return b


## Entrada: el contenido aparece desde la izquierda con un ligero desfase.
func _intro_animation() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.6)

