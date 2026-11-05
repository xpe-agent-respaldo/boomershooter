extends Control
## Pantalla de logros: progreso, premio y estado de cada uno.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var pic := UIKit.add_backdrop(self, "res://Assets/Images/menu_bg.png", 0.32)
	UIKit.animate_backdrop(pic)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UIKit.label("LOGROS", 40, UIKit.COL_EMBER, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var hechos := 0
	for a in Achievements.LISTA:
		if Achievements.esta(str(a["id"])):
			hechos += 1
	head.add_child(UIKit.label("%d / %d" % [hechos, Achievements.LISTA.size()], 22, UIKit.COL_EMBER))
	root.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 8)
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lista)

	for a in Achievements.LISTA:
		lista.add_child(_fila(a))

	var back := UIKit.menu_button("VOLVER", "", 22)
	back.custom_minimum_size = Vector2(240, 50)
	back.pressed.connect(func() -> void: LobbyAudio.change_scene(get_tree(), "res://Levels/MainMenu.tscn"))
	root.add_child(back)


func _fila(a: Dictionary) -> Control:
	var hecho: bool = Achievements.esta(str(a["id"]))
	var panel := UIKit.panel(12)
	panel.custom_minimum_size = Vector2(0, 74)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	panel.add_child(h)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)

	var titulo := UIKit.label(str(a["nombre"]), 19, UIKit.COL_EMBER if hecho else UIKit.COL_BONE, true)
	v.add_child(titulo)
	v.add_child(UIKit.label(str(a["desc"]), 13, UIKit.COL_DIM))

	var barra := ProgressBar.new()
	barra.max_value = 1.0
	barra.value = 1.0 if hecho else Achievements.avance(a)
	barra.show_percentage = false
	barra.custom_minimum_size = Vector2(0, 8)
	v.add_child(barra)

	var estado := "CONSEGUIDO" if hecho else Achievements.texto_avance(a)
	var col := UIKit.COL_EMBER if hecho else UIKit.COL_DIM
	h.add_child(UIKit.label(estado, 15, col))
	h.add_child(UIKit.label("+%d" % int(a["premio"]), 17, UIKit.COL_EMBER))
	return panel
