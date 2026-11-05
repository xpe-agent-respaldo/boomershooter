extends Control
## Pantalla de tienda: skins del personaje con precio y estado.

var _wallet: Label
var _grid: GridContainer


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
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UIKit.label("TIENDA DE SKINS", 40, UIKit.COL_EMBER, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_wallet = UIKit.label("", 24, UIKit.COL_EMBER)
	head.add_child(_wallet)

	root.add_child(UIKit.label("Comprá una skin y se aplica al instante en tu personaje.", 17, UIKit.COL_DIM))
	root.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = _columns_for_width()
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)

	var back := UIKit.menu_button("VOLVER", "", 22)
	back.custom_minimum_size = Vector2(240, 50)
	back.pressed.connect(func() -> void: LobbyAudio.change_scene(get_tree(), "res://Levels/MainMenu.tscn"))
	root.add_child(back)

	_redraw()


## La rejilla se adapta al ancho: 4 columnas en pantalla normal, 3 si es estrecha.
func _columns_for_width() -> int:
	var w: int = int(get_viewport_rect().size.x)
	if w < 1100:
		return 3
	if w > 1700:
		return 5
	return 4


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _grid != null:
		_grid.columns = _columns_for_width()


func _redraw() -> void:
	if _grid == null:
		return
	_wallet.text = "%d MONEDAS" % Shop.coins
	for c in _grid.get_children():
		c.queue_free()
	for s in Shop.SKINS:
		_grid.add_child(_card(s))


func _card(s: Dictionary) -> Control:
	var id := str(s["id"])
	var panel := UIKit.panel(14)
	panel.custom_minimum_size = Vector2(200, 290)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(_visor_neko(s["color"]))
	var nombre := UIKit.label(str(s["name"]), 17, UIKit.COL_BONE, true)
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nombre)
	var d := UIKit.label(str(s["desc"]), 12, UIKit.COL_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(0, 38)
	v.add_child(d)

	var is_owned := Shop.is_owned(id)
	var is_on := Shop.equipped == id
	var text := "EQUIPADA" if is_on else ("EQUIPAR" if is_owned else "%d MONEDAS" % int(s["price"]))
	var b := UIKit.menu_button(text, "", 16)
	b.custom_minimum_size = Vector2(0, 38)
	if is_on:
		b.disabled = true
	b.pressed.connect(func() -> void:
		if Shop.is_owned(id):
			Shop.equip(id)
		else:
			Shop.buy(id)
		_redraw())
	v.add_child(b)
	return panel


## Visor 3D de la tarjeta: el Neko REAL con el tinte de la skin, girando despacio. Cada visor es un
## SubViewport propio con su luz y su camara, asi se ve exactamente lo que se compra.
func _visor_neko(color: Color) -> Control:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.custom_minimum_size = Vector2(0, 132)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(240, 264)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cont.add_child(vp)

	var pivote := Node3D.new()
	vp.add_child(pivote)
	var neko := BotLook.new()
	pivote.add_child(neko)
	neko.build(color)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.1)
	cam.fov = 38.0
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.9, 0))

	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-35, 30, 0)
	luz.light_energy = 1.4
	vp.add_child(luz)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.9
	amb.environment = env
	vp.add_child(amb)

	var giro := create_tween().set_loops()
	giro.tween_property(pivote, "rotation:y", TAU, 7.0).from(0.0)
	return cont
