extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"
const BUS_NAMES := ["Master", "Music", "Lobby", "SFX"]
const REMAPPABLE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump", "crouch", "sprint", "attack", "aim", "reload", "interact", "weapon1", "weapon2", "weapon3", "weapon4", "weapon_wheel", "push_to_talk", "help_call", "ping_mark", "exit"]
const FPS_LIMITS := [0, 30, 60, 90, 120, 144, 165, 240]
# Palabras que delatan unos audifonos en el nombre del dispositivo de salida.
const HEADPHONE_KEYWORDS := ["headphone", "headset", "auricular", "audifono", "audífono", "earphone", "earbud", "airpods", "bluetooth", "hands-free", "manos libres", "casque", "kopfh", "cuffie"]
const DEVICE_POLL_SECONDS := 2.0
signal audio_device_changed(device_name: String, is_headphones: bool)

var _panel: PanelContainer
var _fps_label: Label
var _values := {"Master": 0.8, "Music": 0.7, "Lobby": 0.7, "SFX": 0.8}
var mouse_sensitivity: float = 0.33
var controller_sensitivity: float = 2.0
var fps_limit: int = 0
var fps_counter_corner: int = 1
var performance_profile: int = 0
## Fondo de color plano y tonemap simple. Solo para quien lo pide en Rendimiento o tiene una
## GPU muy limitada: un usuario con un PC decente ve el juego con su cielo y su iluminacion.
var modo_plano: bool = false
var auto_sprint: bool = false
var double_tap_sprint: bool = true
var window_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN
var window_size: Vector2i = Vector2i(1920, 1080)
var render_scale: float = 1.0
var voice_enabled: bool = false
var voice_volume: float = 0.8
var voice_mode: int = 0
## Canal por el que sale tu voz: 0 = proximidad (solo te oyen los de al lado),
## 1 = equipo, 2 = todos. Lo aplica VoiceManager al enviar cada paquete.
var voice_channel: int = 0
## Asistencia de punteria en PC: 0 apagada, 1 suave, 2 media, 3 fuerte.
var aim_assist_level: int = 2
var _fps_refresh: float = 0.0
var _gpu_texto: String = ""
var _render_software := false
var audio_output_device: String = "Default"
## Microfono elegido (nombre del dispositivo de entrada). "Default" = el predeterminado del sistema.
var audio_input_device: String = "Default"
var _mic_option: OptionButton
var _mic_status: Label
var _mic_estado_grande: Label
var _mic_nivel: ProgressBar
var _mic_devices: PackedStringArray = PackedStringArray()
var _mic_sondeo: float = 0.0
var headphones_connected: bool = false
var _device_poll: float = 0.0
var _known_devices: PackedStringArray = PackedStringArray()
var _device_option: OptionButton
var _device_status: Label
var _waiting_action := ""
var _waiting_button: Button
var _remap_dialog: AcceptDialog


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var first_run: bool = not FileAccess.file_exists(SETTINGS_PATH)
	_load()
	if first_run:
		window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		_autodetect_profile()
	else:
		_migrar_rendimiento()
	_apply()
	_aplicar_microfono_guardado()
	_pedir_gpu_dedicada()
	# garantia final: pase lo que pase con el guardado, el juego abre a pantalla completa
	# salvo que el jugador la haya quitado a mano despues de la migracion.
	DisplayServer.window_set_mode(window_mode)
	_diagnostico_gpu()
	_create_fps_counter()
	_create_panel()


func _process(delta: float) -> void:
	_medir_nivel_microfono()
	_device_poll += delta
	if _device_poll >= DEVICE_POLL_SECONDS:
		_device_poll = 0.0
		_refresh_microphones()
		_refresh_audio_devices()
	if _fps_label == null:
		return
	# Actualizar el texto 5 veces por segundo en vez de en cada frame.
	_fps_refresh += delta
	if _fps_refresh < 0.2:
		return
	_fps_refresh = 0.0
	_fps_label.text = "FPS  %d%s" % [Engine.get_frames_per_second(), "  [SOFTWARE]" if _render_software else ""]


func toggle_settings() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_settings() -> void:
	if _panel:
		_panel.visible = false
	_waiting_action = ""


func _input(event: InputEvent) -> void:
	if not _waiting_action.is_empty():
		_capture_binding(event)
		return
	if _panel and _panel.visible and event.is_action_pressed("ui_cancel"):
		hide_settings()
		get_viewport().set_input_as_handled()


## Que GPU y que driver esta usando el juego de verdad. Se guarda en user://gpu.txt
## y se imprime: si los FPS son bajos con la GPU "sin usar", esto dice si se dibuja
## por software (llvmpipe, Microsoft Basic Render, GDI) o por la tarjeta real.
func _diagnostico_gpu() -> void:
	var adaptador := RenderingServer.get_video_adapter_name()
	var proveedor := RenderingServer.get_video_adapter_vendor()
	var api := RenderingServer.get_video_adapter_api_version()
	var metodo := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var driver := str(ProjectSettings.get_setting("rendering/gl_compatibility/driver.windows", "?"))
	var software := false
	for pista in ["llvmpipe", "software", "basic render", "gdi", "swiftshader", "softpipe"]:
		if adaptador.to_lower().contains(pista):
			software = true
	var texto := "GPU: %s\nProveedor: %s\nAPI: %s\nRenderer: %s | driver Windows: %s\nNucleos CPU: %d\nRAM: %.1f GB\nRENDER POR SOFTWARE: %s\nVersion: %s\n" % [
		adaptador, proveedor, api, metodo, driver, OS.get_processor_count(),
		float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
		"SI (la tarjeta grafica NO se esta usando)" if software else "no",
		str(ProjectSettings.get_setting("application/config/version", "?"))]
	# En release no se imprime nada: si alguien abre el juego desde una terminal,
	# no debe salir un chorro de diagnostico por consola.
	if OS.is_debug_build():
		print(texto)
	var f := FileAccess.open("user://gpu.txt", FileAccess.WRITE)
	if f:
		f.store_string(texto)
	_gpu_texto = adaptador
	_render_software = software


func _create_fps_counter() -> void:
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.size = Vector2(170, 34)
	_apply_fps_counter_position()
	_fps_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 5)
	_fps_label.add_theme_font_size_override("font_size", 22)
	add_child(_fps_label)


func _create_panel() -> void:
	# Panel de ajustes con pestanas. Estilo carne/sangre/brasas de la intro:
	# fondo casi negro, bordes de metal oxidado, acentos naranja y rojo sangre.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -430.0
	_panel.offset_top = -330.0
	_panel.offset_right = 430.0
	_panel.offset_bottom = 330.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)

	# --- cabecera: logo del juego + subtitulo ---
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	root.add_child(header)
	var logo := TextureRect.new()
	var logo_tex: Texture2D = load("res://Assets/Brand/logo_title.png")
	logo.texture = logo_tex
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 86)
	header.add_child(logo)
	var sub := Label.new()
	sub.text = "AJUSTES  //  CONFIGURACION DEL SISTEMA"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.85, 0.42, 0.2))
	header.add_child(sub)
	root.add_child(_blood_divider())

	# --- pestanas ---
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", _tab_panel_style())
	tabs.add_theme_stylebox_override("tab_selected", _tab_style(true))
	tabs.add_theme_stylebox_override("tab_unselected", _tab_style(false))
	tabs.add_theme_stylebox_override("tab_hovered", _tab_style(true))
	tabs.add_theme_color_override("font_selected_color", Color(1.0, 0.82, 0.55))
	tabs.add_theme_color_override("font_unselected_color", Color(0.62, 0.5, 0.45))
	tabs.add_theme_color_override("font_hovered_color", Color(1.0, 0.7, 0.4))
	tabs.add_theme_font_size_override("font_size", 20)
	root.add_child(tabs)

	# AUDIO
	var audio := _new_tab(tabs, "AUDIO")
	_add_volume_control(audio, "VOLUMEN GENERAL", "Master")
	_add_volume_control(audio, "MUSICA DEL LOBBY", "Lobby")
	_add_volume_control(audio, "MUSICA DE PARTIDA", "Music")
	_add_volume_control(audio, "EFECTOS", "SFX")
	_add_audio_device_control(audio)

	# CONTROLES
	var controls := _new_tab(tabs, "CONTROLES")
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.05
	sensitivity.max_value = 1.0
	sensitivity.step = 0.01
	sensitivity.value = mouse_sensitivity
	sensitivity.value_changed.connect(_on_sensitivity_changed)
	controls.add_child(_labelled_control("SENSIBILIDAD DEL MOUSE", sensitivity))
	var controller := HSlider.new()
	controller.min_value = 0.5
	controller.max_value = 4.0
	controller.step = 0.05
	controller.value = controller_sensitivity
	controller.value_changed.connect(_on_controller_sensitivity_changed)
	controls.add_child(_labelled_control("SENSIBILIDAD DEL MANDO", controller))
	var autosprint := CheckButton.new()
	autosprint.text = "Correr automaticamente al avanzar"
	autosprint.button_pressed = auto_sprint
	autosprint.toggled.connect(_set_auto_sprint)
	controls.add_child(autosprint)
	var double_tap := CheckButton.new()
	double_tap.text = "Doble toque de avanzar para correr"
	double_tap.button_pressed = double_tap_sprint
	double_tap.toggled.connect(_set_double_tap_sprint)
	controls.add_child(double_tap)
	var remap := Button.new()
	remap.text = "CAMBIAR TECLAS Y BOTONES"
	remap.custom_minimum_size.y = 46
	_style_button(remap, false)
	remap.pressed.connect(_open_remap_dialog)
	controls.add_child(remap)

	# PANTALLA
	var screen := _new_tab(tabs, "PANTALLA")
	var display := OptionButton.new()
	display.add_item("Ventana")
	display.add_item("Pantalla completa")
	display.selected = 1 if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] else 0
	display.item_selected.connect(_set_display_mode)
	screen.add_child(_labelled_control("MODO DE PANTALLA", display))
	var resolution := OptionButton.new()
	resolution.add_item("1280 x 720")
	resolution.add_item("1600 x 900")
	resolution.add_item("1920 x 1080")
	resolution.selected = _resolution_index()
	resolution.item_selected.connect(_set_resolution)
	screen.add_child(_labelled_control("RESOLUCION", resolution))
	var fps := OptionButton.new()
	for value in ["Sin limite", "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "165 FPS", "240 FPS"]:
		fps.add_item(value)
	fps.selected = maxi(0, FPS_LIMITS.find(fps_limit))
	fps.item_selected.connect(_set_fps_limit)
	screen.add_child(_labelled_control("LIMITE DE FPS", fps))
	var fps_position := OptionButton.new()
	fps_position.add_item("Esquina superior izquierda")
	fps_position.add_item("Esquina superior derecha")
	fps_position.add_item("Esquina inferior izquierda")
	fps_position.add_item("Esquina inferior derecha")
	fps_position.selected = clampi(fps_counter_corner, 0, 3)
	fps_position.item_selected.connect(_set_fps_counter_corner)
	screen.add_child(_labelled_control("POSICION DEL CONTADOR FPS", fps_position))

	# RENDIMIENTO
	var perf := _new_tab(tabs, "RENDIMIENTO")
	var render_quality := OptionButton.new()
	render_quality.add_item("ALTA (100%)")
	render_quality.add_item("EQUILIBRADA (85%)")
	render_quality.add_item("RENDIMIENTO (70%)")
	render_quality.selected = _render_scale_index()
	render_quality.item_selected.connect(_set_render_scale)
	perf.add_child(_labelled_control("CALIDAD 3D", render_quality))
	var performance := OptionButton.new()
	performance.add_item("BAJO - equipos de 4 GB")
	performance.add_item("EQUILIBRADO")
	performance.add_item("ALTO")
	performance.selected = clampi(performance_profile, 0, 2)
	performance.item_selected.connect(_set_performance_profile)
	perf.add_child(_labelled_control("PERFIL DE RENDIMIENTO", performance))
	var plano_toggle := CheckButton.new()
	plano_toggle.text = "Modo maximo rendimiento (fondo plano, sin cielo)"
	plano_toggle.button_pressed = modo_plano
	plano_toggle.toggled.connect(_set_modo_plano)
	perf.add_child(plano_toggle)
	var aim_assist_option := OptionButton.new()
	aim_assist_option.add_item("APAGADA")
	aim_assist_option.add_item("SUAVE")
	aim_assist_option.add_item("MEDIA")
	aim_assist_option.add_item("FUERTE")
	aim_assist_option.selected = clampi(aim_assist_level, 0, 3)
	aim_assist_option.item_selected.connect(_set_aim_assist)
	perf.add_child(_labelled_control("ASISTENCIA DE PUNTERIA (PC)", aim_assist_option))
	var perf_note := Label.new()
	perf_note.text = "BAJO limita los enemigos a la vez. El modo maximo rendimiento quita el cielo y simplifica la luz (se aplica al entrar a un mapa): solo para equipos muy limitados."
	perf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_note.add_theme_font_size_override("font_size", 15)
	perf_note.modulate = Color(0.7, 0.6, 0.55)
	perf.add_child(perf_note)

	# VOZ
	var voice := _new_tab(tabs, "VOZ")
	_add_microphone_control(voice)
	var voice_enabled_toggle := CheckButton.new()
	voice_enabled_toggle.text = "Activar microfono en partidas online"
	voice_enabled_toggle.button_pressed = voice_enabled
	voice_enabled_toggle.toggled.connect(_set_voice_enabled)
	voice.add_child(voice_enabled_toggle)
	var voice_volume_slider := HSlider.new()
	voice_volume_slider.min_value = 0.0
	voice_volume_slider.max_value = 1.0
	voice_volume_slider.step = 0.01
	voice_volume_slider.value = voice_volume
	voice_volume_slider.value_changed.connect(_set_voice_volume)
	voice.add_child(_labelled_control("VOLUMEN DE MICROFONO", voice_volume_slider))
	var voice_mode_option := OptionButton.new()
	voice_mode_option.add_item("Pulsar para hablar")
	voice_mode_option.add_item("Microfono abierto")
	voice_mode_option.selected = clampi(voice_mode, 0, 1)
	voice_mode_option.item_selected.connect(_set_voice_mode)
	voice.add_child(_labelled_control("MODO DE MICROFONO", voice_mode_option))
	var voice_channel_option := OptionButton.new()
	voice_channel_option.add_item("Proximidad (solo los de al lado)")
	voice_channel_option.add_item("Equipo")
	voice_channel_option.add_item("Todos")
	voice_channel_option.selected = clampi(voice_channel, 0, 2)
	voice_channel_option.item_selected.connect(_set_voice_channel)
	voice.add_child(_labelled_control("CANAL DE VOZ", voice_channel_option))
	var voice_note := Label.new()
	voice_note.text = "La voz viaja comprimida (mu-law 8 kHz): 8 KB/s. En proximidad te oyen a menos de 24 m."
	voice_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice_note.add_theme_font_size_override("font_size", 15)
	voice_note.modulate = Color(0.7, 0.6, 0.55)
	voice.add_child(voice_note)

	# --- pie: aviso + volver + copyright ---
	root.add_child(_blood_divider())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var hint := Label.new()
	hint.text = "Se guarda solo.  Esc para volver."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate = Color(0.7, 0.6, 0.55)
	footer.add_child(hint)
	var close := Button.new()
	close.text = "VOLVER"
	close.custom_minimum_size = Vector2(190, 50)
	close.add_theme_font_size_override("font_size", 24)
	_style_button(close, true)
	close.pressed.connect(hide_settings)
	footer.add_child(close)
	var copyright := Label.new()
	copyright.text = "© 2026 xpe.nettt · Stealth Proyects"
	copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copyright.add_theme_font_size_override("font_size", 13)
	copyright.modulate = Color(0.5, 0.42, 0.4)
	root.add_child(copyright)
	_panel.visible = false


func _new_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	tabs.add_child(scroll)
	return box


func _blood_divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 3)
	line.color = Color(0.55, 0.07, 0.07, 0.9)
	return line


func _tab_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.022, 0.03, 0.9)
	style.border_color = Color(0.32, 0.13, 0.1, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	return style


func _tab_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.06, 0.05, 1.0) if selected else Color(0.07, 0.05, 0.06, 1.0)
	style.border_color = Color(1.0, 0.4, 0.15, 1.0) if selected else Color(0.28, 0.14, 0.12, 1.0)
	style.set_border_width_all(2)
	style.border_width_bottom = 0
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _style_button(button: Button, primary: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		var base := Color(0.32, 0.07, 0.05) if primary else Color(0.12, 0.07, 0.07)
		if state == "hover":
			base = base.lightened(0.18)
		elif state == "pressed":
			base = base.darkened(0.25)
		style.bg_color = base
		style.border_color = Color(1.0, 0.4, 0.14) if primary else Color(0.5, 0.25, 0.18)
		style.set_border_width_all(2)
		style.set_corner_radius_all(2)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.66))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.85))


func _add_section_title(parent: VBoxContainer, text_value: String) -> void:
	var title := Label.new()
	title.text = text_value
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	title.add_theme_font_size_override("font_size", 20)
	parent.add_child(title)


func _add_volume_control(parent: VBoxContainer, title: String, bus_name: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var readout := Label.new()
	readout.text = "%d%%" % roundi(float(_values[bus_name]) * 100.0)
	readout.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	head.add_child(readout)
	row.add_child(head)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = _values[bus_name]
	slider.tooltip_text = "%s: %d%%" % [title, roundi(slider.value * 100.0)]
	slider.value_changed.connect(func(value: float):
		readout.text = "%d%%" % roundi(value * 100.0)
		_set_volume(bus_name, value, slider, title))
	row.add_child(slider)
	parent.add_child(row)


## Pide a Windows la grafica dedicada para este juego. La primera vez que se escribe la preferencia
## hay que relanzar el juego (Windows solo la lee al arrancar); se hace una unica vez y se recuerda
## en el archivo de ajustes para no entrar nunca en un bucle de relanzamientos.
func _pedir_gpu_dedicada() -> void:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	if bool(config.get_value("gpu", "relanzado", false)):
		return
	var resultado := GpuPreferida.aplicar()
	if resultado == "aplicada":
		config.set_value("gpu", "relanzado", true)
		config.save(SETTINGS_PATH)
		OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
		get_tree().quit()
	elif resultado == "ya_estaba":
		config.set_value("gpu", "relanzado", true)
		config.save(SETTINGS_PATH)


## Devuelve true si el nombre del dispositivo parece unos audifonos.
static func is_headphone_name(device_name: String) -> bool:
	var lowered := device_name.to_lower()
	for keyword in HEADPHONE_KEYWORDS:
		if lowered.contains(keyword):
			return true
	return false


## ---------- MICROFONO ----------
## Estado visible (ACTIVADO / DESACTIVADO), lista de micrófonos detectados con su nombre real,
## deteccion en caliente y un medidor de nivel para comprobar que el micro suena.

func _add_microphone_control(parent: VBoxContainer) -> void:
	_mic_estado_grande = Label.new()
	_mic_estado_grande.add_theme_font_size_override("font_size", 26)
	parent.add_child(_mic_estado_grande)
	_mic_option = OptionButton.new()
	_mic_option.item_selected.connect(_on_microphone_selected)
	parent.add_child(_labelled_control("MICROFONO", _mic_option))
	_mic_status = Label.new()
	_mic_status.add_theme_font_size_override("font_size", 14)
	_mic_status.add_theme_color_override("font_color", Color(0.9, 0.78, 0.66))
	_mic_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_mic_status)
	_mic_nivel = ProgressBar.new()
	_mic_nivel.min_value = 0.0
	_mic_nivel.max_value = 1.0
	_mic_nivel.custom_minimum_size = Vector2(0, 14)
	_mic_nivel.show_percentage = false
	parent.add_child(_labelled_control("NIVEL (habla para probarlo)", _mic_nivel))
	_rebuild_microphone_list()


func _aplicar_microfono_guardado() -> void:
	var lista := AudioServer.get_input_device_list()
	if audio_input_device != "Default" and lista.has(audio_input_device):
		AudioServer.input_device = audio_input_device
	elif audio_input_device != "Default":
		# el micro guardado ya no esta conectado: se vuelve al predeterminado sin romper nada
		AudioServer.input_device = "Default"


## Medidor: lee el pico del bus de voz (que ya captura el micro mientras se transmite).
func _medir_nivel_microfono() -> void:
	var visible_ahora := _mic_nivel != null and is_instance_valid(_mic_nivel) and _mic_nivel.is_visible_in_tree()
	VoiceManager.probar_microfono(visible_ahora)
	if not visible_ahora:
		return
	var objetivo := VoiceManager.nivel_microfono()
	_mic_nivel.value = lerpf(_mic_nivel.value, objetivo, 0.35)


func _rebuild_microphone_list() -> void:
	_mic_devices = AudioServer.get_input_device_list()
	if _mic_option == null:
		return
	_mic_option.clear()
	var elegido := 0
	var actual := AudioServer.input_device
	for i in _mic_devices.size():
		var nombre := _mic_devices[i]
		var mostrado := nombre if nombre != "Default" else "Predeterminado del sistema"
		_mic_option.add_item(mostrado, i)
		if nombre == actual:
			elegido = i
	if _mic_devices.size() > 0:
		_mic_option.select(elegido)
	_update_microphone_status()


func _on_microphone_selected(index: int) -> void:
	if index < 0 or index >= _mic_devices.size():
		return
	audio_input_device = _mic_devices[index]
	AudioServer.input_device = audio_input_device
	_update_microphone_status()
	_save()


## True si hay al menos un micrófono real y el jugador lo tiene activado en el juego.
func microphone_available() -> bool:
	for n in AudioServer.get_input_device_list():
		if n != "Default" or AudioServer.get_input_device_list().size() > 1:
			return true
	return false


func _update_microphone_status() -> void:
	var lista := AudioServer.get_input_device_list()
	var hay_mic := lista.size() > 1 or (lista.size() == 1 and lista[0] != "Default")
	var activo := voice_enabled and hay_mic
	if _mic_estado_grande:
		if not hay_mic:
			_mic_estado_grande.text = "MICROFONO: NO DETECTADO"
			_mic_estado_grande.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
		elif activo:
			_mic_estado_grande.text = "MICROFONO: ACTIVADO"
			_mic_estado_grande.add_theme_color_override("font_color", Color(0.45, 0.9, 0.5))
		else:
			_mic_estado_grande.text = "MICROFONO: DESACTIVADO"
			_mic_estado_grande.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	if _mic_status:
		var en_uso := AudioServer.input_device
		var cuantos := maxi(0, lista.size() - (1 if lista.has("Default") else 0))
		if not hay_mic:
			_mic_status.text = "No se detecta ningun microfono. Conecta uno o revisa los permisos de Windows (Privacidad > Microfono)."
		else:
			_mic_status.text = "En uso: %s  |  Detectados: %d" % [en_uso if en_uso != "Default" else "Predeterminado del sistema", cuantos]


func _refresh_microphones() -> void:
	if AudioServer.get_input_device_list() != _mic_devices:
		_rebuild_microphone_list()
	else:
		_update_microphone_status()


func _add_audio_device_control(parent: VBoxContainer) -> void:
	_device_option = OptionButton.new()
	_device_option.item_selected.connect(_on_audio_device_selected)
	_device_status = Label.new()
	_device_status.add_theme_font_size_override("font_size", 14)
	_device_status.add_theme_color_override("font_color", Color(0.9, 0.78, 0.66))
	parent.add_child(_labelled_control("SALIDA DE AUDIO", _device_option))
	parent.add_child(_device_status)
	_rebuild_device_list()


func _rebuild_device_list() -> void:
	_known_devices = AudioServer.get_output_device_list()
	if _device_option == null:
		return
	_device_option.clear()
	var selected := 0
	for i in _known_devices.size():
		var name_i := _known_devices[i]
		var shown := name_i if name_i != "Default" else "Predeterminado del sistema"
		if is_headphone_name(name_i):
			shown += "  (audifonos)"
		_device_option.add_item(shown, i)
		if name_i == AudioServer.output_device:
			selected = i
	if _known_devices.size() > 0:
		_device_option.select(selected)
	_update_device_status()


func _on_audio_device_selected(index: int) -> void:
	if index < 0 or index >= _known_devices.size():
		return
	audio_output_device = _known_devices[index]
	AudioServer.output_device = audio_output_device
	_after_device_change()
	_save()


func _refresh_audio_devices() -> void:
	# Detecta conexion/desconexion en caliente comparando la lista de Godot.
	var current := AudioServer.get_output_device_list()
	if current != _known_devices:
		_rebuild_device_list()
	var active := AudioServer.output_device
	var now_headphones := is_headphone_name(active)
	if now_headphones != headphones_connected:
		_after_device_change()


func _after_device_change() -> void:
	var active := AudioServer.output_device
	headphones_connected = is_headphone_name(active)
	_update_device_status()
	audio_device_changed.emit(active, headphones_connected)


func _update_device_status() -> void:
	var active := AudioServer.output_device
	headphones_connected = is_headphone_name(active)
	if _device_status:
		_device_status.text = ("Audifonos detectados: " if headphones_connected else "Altavoces: ") + (active if active != "Default" else "Predeterminado del sistema")


func _labelled_control(title: String, control: Control) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.9, 0.78, 0.66))
	row.add_child(label)
	row.add_child(control)
	return row


func _set_display_mode(index: int) -> void:
	if index == 1:
		window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	else:
		window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(window_mode)
	_save()


func _set_resolution(index: int) -> void:
	var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
	if index >= 0 and index < sizes.size():
		window_size = sizes[index]
		DisplayServer.window_set_size(window_size)
	_save()


func _resolution_index() -> int:
	var current := DisplayServer.window_get_size()
	var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
	var nearest := 0
	for i in sizes.size():
		if sizes[i] == current:
			return i
		if sizes[i].distance_to(current) < sizes[nearest].distance_to(current):
			nearest = i
	return nearest


func _set_aim_assist(index: int) -> void:
	aim_assist_level = clampi(index, 0, 3)
	_save()


func _set_fps_limit(index: int) -> void:
	fps_limit = FPS_LIMITS[clampi(index, 0, FPS_LIMITS.size() - 1)]
	Engine.max_fps = fps_limit
	_save()


func _set_render_scale(index: int) -> void:
	render_scale = [1.0, 0.85, 0.70][clampi(index, 0, 2)]
	get_viewport().scaling_3d_scale = render_scale
	_save()


func _set_fps_counter_corner(index: int) -> void:
	fps_counter_corner = clampi(index, 0, 3)
	_apply_fps_counter_position()
	_save()


func _apply_fps_counter_position() -> void:
	if _fps_label == null:
		return
	match fps_counter_corner:
		0:
			_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_fps_label.position = Vector2(16, 16)
			_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		1:
			# Justo debajo del contador de KILLS (que ocupa los primeros 80 px).
			_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			_fps_label.position = Vector2(-186, 86)
			_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		2:
			_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			_fps_label.position = Vector2(16, -50)
			_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_:
			_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			_fps_label.position = Vector2(-186, -50)
			_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _set_modo_plano(value: bool) -> void:
	modo_plano = value
	_save()


func _set_performance_profile(index: int) -> void:
	performance_profile = clampi(index, 0, 2)
	match performance_profile:
		0:
			# BAJO ya no estrangula la GPU: resolucion nativa y sin tope. La CPU aguanta
			# (5 ms por frame medidos) y el juego casi no tiene sombras ni luces.
			render_scale = 1.0
			fps_limit = 0
		1:
			render_scale = 1.0
			fps_limit = 0
		2:
			render_scale = 1.0
			fps_limit = 0
	_apply()
	_save()


## La 1.2.0 baja el coste por defecto. Quien ya tenia guardado el perfil pesado de las
## versiones anteriores (escala 1.0 y mas de 90 fps) pasa una sola vez a Bajo; si luego
## sube la calidad a mano, se respeta porque la marca queda guardada.
func _migrar_rendimiento() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# 1.2.1: el juego abre siempre en pantalla completa (una sola vez, se puede cambiar luego)
	if int(cfg.get_value("display", "fullscreen_migrado", 0)) < 1:
		window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		cfg.set_value("display", "window_mode", window_mode)
		cfg.set_value("display", "fullscreen_migrado", 1)
		cfg.save(SETTINGS_PATH)
	if int(cfg.get_value("display", "perf_migrado", 0)) >= 3:
		return
	# 1.2.2: la GPU estaba al 4 % porque el juego la frenaba (60 fps y 65 % de resolucion).
	# Se libera una sola vez; si luego el jugador pone un tope a mano, se respeta.
	render_scale = 1.0
	fps_limit = 0
	print("Rendimiento: GPU liberada (sin tope de fps, resolucion nativa)")
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "fps_limit", fps_limit)
	cfg.set_value("display", "perf_migrado", 3)
	cfg.save(SETTINGS_PATH)


## Elige el perfil segun el equipo la primera vez que se abre el juego.
func _gpu_muy_limitada() -> bool:
	var g := RenderingServer.get_video_adapter_name().to_lower()
	if g == "":
		return false
	for pista in ["llvmpipe", "software", "basic render", "gdi", "swiftshader", "softpipe", "hd 8330", "hd 8250", "hd 8280", "hd 8210", "hd 7340", "hd 6310", "hd 6290", "gma ", "intel(r) hd graphics family"]:
		if g.contains(pista):
			return true
	return false


## Decide el perfil mirando la grafica, los nucleos y la RAM. Es una funcion pura
## para poder probarla con equipos simulados (ver tools/tests/calidad_auto_test.gd).
##
## Antes bastaba con tener 8 nucleos o menos para caer en "Bajo", asi que un PC
## normal quedaba capado y el perfil "Alto" no se alcanzaba nunca (y sin "Alto" no
## hay ragdoll). Ahora se mira la GPU primero y el resto despues.
static func calcular_perfil(cores: int, ram_gb: float, gpu: String, es_movil: bool) -> Dictionary:
	var g := gpu.to_lower()
	var software := false
	for pista in ["llvmpipe", "software", "basic render", "gdi", "swiftshader", "softpipe"]:
		if g.contains(pista):
			software = true
			break
	var muy_vieja := false
	for pista in ["hd 8330", "hd 8250", "hd 8280", "hd 8210", "hd 7340", "hd 6310", "hd 6290",
			"gma ", "hd graphics family", "hd graphics 2", "hd graphics 3", "hd graphics 4",
			"radeon hd 6", "radeon hd 7", "geforce 7", "geforce 8", "geforce 9", "gt 2", "gt 4"]:
		if g.contains(pista):
			muy_vieja = true
			break
	var dedicada := false
	for pista in ["rtx", "gtx", "geforce", "radeon rx", "radeon pro", "rx 4", "rx 5",
			"rx 6", "rx 7", "rx 9", "arc a", "quadro", "apple m", "radeon 7", "radeon 6"]:
		if g.contains(pista):
			dedicada = true
			break

	if software:
		return {"perfil": 0, "plano": true, "render_scale": 0.75, "fps_limit": 60,
			"motivo": "sin tarjeta grafica (render por software)"}
	if muy_vieja:
		return {"perfil": 0, "plano": true, "render_scale": 0.85, "fps_limit": 60,
			"motivo": "tarjeta grafica muy justa"}
	if es_movil:
		# Moviles modernos: pantalla pequena y GPU integrada decente.
		return {"perfil": 1, "plano": false, "render_scale": 1.0, "fps_limit": 60,
			"motivo": "movil o tableta"}
	if dedicada and cores >= 8 and ram_gb >= 12.0:
		return {"perfil": 2, "plano": false, "render_scale": 1.0, "fps_limit": 0,
			"motivo": "tarjeta dedicada y equipo sobrado"}
	if cores >= 6 and (ram_gb <= 0.0 or ram_gb >= 8.0):
		return {"perfil": 1, "plano": false, "render_scale": 1.0, "fps_limit": 0,
			"motivo": "equipo de gama media"}
	return {"perfil": 0, "plano": true, "render_scale": 0.9, "fps_limit": 60,
		"motivo": "equipo justo de CPU y RAM"}


func _autodetect_profile() -> void:
	var cores: int = OS.get_processor_count()
	var ram_gb: float = 0.0
	if OS.has_method("get_memory_info"):
		var info: Dictionary = OS.get_memory_info()
		ram_gb = float(info.get("physical", 0)) / 1073741824.0
	var gpu := RenderingServer.get_video_adapter_name()
	var movil: bool = OS.has_feature("mobile") or OS.get_name() == "Web"
	var datos := calcular_perfil(cores, ram_gb, gpu, movil)

	performance_profile = int(datos["perfil"])
	modo_plano = bool(datos["plano"])
	render_scale = float(datos["render_scale"])
	fps_limit = int(datos["fps_limit"])
	_apply()
	_save()

	var nombre: String = ["BAJO", "MEDIO", "ALTO"][clampi(performance_profile, 0, 2)]
	print("Perfil de rendimiento: %s (%s) | %d nucleos, %.1f GB, %s" % [
		nombre, datos["motivo"], cores, ram_gb, gpu])
	_avisar_perfil(nombre, str(datos["motivo"]), cores, ram_gb)


## Aviso de una sola vez: "CALIDAD AJUSTADA A TU EQUIPO". Se va solo y no bloquea
## nada (raton ignorado), con la tipografia y los colores del juego.
func _avisar_perfil(nombre: String, motivo: String, cores: int, ram_gb: float) -> void:
	var capa := CanvasLayer.new()
	capa.layer = 101
	add_child(capa)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.offset_top = 88.0
	panel.offset_bottom = 88.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.02, 0.025, 0.92)
	st.border_color = Color(1.0, 0.42, 0.12, 1.0)
	st.set_border_width_all(1)
	st.border_width_left = 5
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 10.0
	st.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", st)
	capa.add_child(panel)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 1)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caja)
	var titulo := Label.new()
	titulo.text = "CALIDAD AJUSTADA A TU EQUIPO: " + nombre
	titulo.add_theme_font_size_override("font_size", 17)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	if ResourceLoader.exists("res://Assets/Fonts/Geizer.otf"):
		titulo.add_theme_font_override("font", load("res://Assets/Fonts/Geizer.otf"))
	caja.add_child(titulo)
	var detalle := Label.new()
	var ram := "%.0f GB" % ram_gb if ram_gb > 0.0 else "RAM desconocida"
	detalle.text = "%s · %d nucleos · %s. Puedes cambiarlo en AJUSTES." % [motivo, cores, ram]
	detalle.add_theme_font_size_override("font_size", 11)
	detalle.add_theme_color_override("font_color", Color(0.72, 0.62, 0.56))
	caja.add_child(detalle)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.35)
	tw.tween_interval(7.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		if is_instance_valid(capa):
			capa.queue_free()
	)



func _render_scale_index() -> int:
	if render_scale <= 0.72:
		return 2
	if render_scale <= 0.87:
		return 1
	return 0


func _on_sensitivity_changed(value: float) -> void:
	mouse_sensitivity = value
	_save()


func _on_controller_sensitivity_changed(value: float) -> void:
	controller_sensitivity = value
	_save()


func _set_auto_sprint(value: bool) -> void:
	auto_sprint = value
	_save()


func _set_double_tap_sprint(value: bool) -> void:
	double_tap_sprint = value
	_save()


func _set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	_update_microphone_status()
	VoiceManager.apply_settings()
	_save()


func _set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, 1.0)
	VoiceManager.apply_settings()
	_save()


func _set_voice_channel(index: int) -> void:
	voice_channel = clampi(index, 0, 2)
	VoiceManager.apply_settings()
	_save()


func _set_voice_mode(index: int) -> void:
	voice_mode = clampi(index, 0, 1)
	VoiceManager.apply_settings()
	_save()


func _set_volume(bus_name: String, value: float, slider: HSlider, title: String) -> void:
	_values[bus_name] = value
	slider.tooltip_text = "%s: %d%%" % [title, roundi(value * 100.0)]
	_apply()
	_save()


func _open_remap_dialog() -> void:
	if _remap_dialog:
		_remap_dialog.queue_free()
	_remap_dialog = AcceptDialog.new()
	_remap_dialog.title = "CAMBIAR CONTROLES"
	_remap_dialog.ok_button_text = "LISTO"
	_remap_dialog.dialog_text = "Haz clic en una accion y luego presiona una tecla o boton del mando."
	_remap_dialog.min_size = Vector2(560, 540)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	_remap_dialog.add_child(list)
	for action in REMAPPABLE_ACTIONS:
		var button := Button.new()
		button.text = "%s: %s" % [_action_name(action), _binding_label(action)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_begin_remap.bind(action, button))
		list.add_child(button)
	add_child(_remap_dialog)
	_remap_dialog.popup_centered()


func _begin_remap(action: String, button: Button) -> void:
	_waiting_action = action
	_waiting_button = button
	_waiting_button.text = "%s: PRESIONA UNA TECLA..." % _action_name(action)


func _capture_binding(event: InputEvent) -> void:
	var new_event
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_waiting_action = ""
			_open_remap_dialog()
			return
		new_event = InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	elif event is InputEventJoypadButton and event.pressed:
		new_event = InputEventJoypadButton.new()
		new_event.button_index = event.button_index
	else:
		return
	_replace_primary_binding(_waiting_action, new_event)
	_save()
	_waiting_action = ""
	get_viewport().set_input_as_handled()
	_open_remap_dialog()


func _replace_primary_binding(action: String, replacement: InputEvent) -> void:
	for current_event in InputMap.action_get_events(action):
		if replacement is InputEventKey and current_event is InputEventKey:
			InputMap.action_erase_event(action, current_event)
		elif replacement is InputEventJoypadButton and current_event is InputEventJoypadButton:
			InputMap.action_erase_event(action, current_event)
	InputMap.action_add_event(action, replacement)


func _binding_label(action: String) -> String:
	if action == "crouch":
		return "C / Ctrl"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text_physical_keycode()
		if event is InputEventJoypadButton:
			return "Mando: %s" % event.as_text()
	return "Sin asignar"


func _action_name(action: String) -> String:
	var labels := {
		"move_forward": "Avanzar", "move_backward": "Retroceder", "move_left": "Mover izquierda", "move_right": "Mover derecha",
		"jump": "Saltar", "crouch": "Agacharse / deslizar", "sprint": "Correr", "attack": "Disparar", "aim": "Apuntar",
		"reload": "Recargar", "interact": "Interactuar", "weapon1": "Arma 1", "weapon2": "Arma 2", "weapon3": "Arma 3",
		"weapon4": "Francotirador", "weapon_wheel": "Rueda de armas", "push_to_talk": "Pulsar para hablar", "help_call": "Pedir ayuda", "ping_mark": "Marcar punto", "exit": "Pausa"
	}
	return labels.get(action, action)


func _apply() -> void:
	for bus_name in BUS_NAMES:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(_values[bus_name], 0.001)))
	if audio_output_device != "" and audio_output_device in AudioServer.get_output_device_list():
		AudioServer.output_device = audio_output_device
	headphones_connected = is_headphone_name(AudioServer.output_device)
	Engine.max_fps = fps_limit
	var viewport := get_viewport()
	if viewport:
		viewport.scaling_3d_scale = render_scale
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_mode(window_mode)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for bus_name in BUS_NAMES:
		_values[bus_name] = clampf(float(config.get_value("audio", bus_name, _values[bus_name])), 0.0, 1.0)
	audio_output_device = str(config.get_value("audio", "output_device", audio_output_device))
	audio_input_device = str(config.get_value("audio", "input_device", audio_input_device))
	mouse_sensitivity = clampf(float(config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.05, 1.0)
	controller_sensitivity = clampf(float(config.get_value("controls", "controller_sensitivity", controller_sensitivity)), 0.5, 4.0)
	auto_sprint = bool(config.get_value("controls", "auto_sprint", auto_sprint))
	double_tap_sprint = bool(config.get_value("controls", "double_tap_sprint", double_tap_sprint))
	fps_limit = int(config.get_value("display", "fps_limit", fps_limit))
	window_mode = int(config.get_value("display", "window_mode", window_mode))
	window_size = config.get_value("display", "window_size", window_size)
	render_scale = clampf(float(config.get_value("display", "render_scale", render_scale)), 0.6, 1.0)
	fps_counter_corner = clampi(int(config.get_value("display", "fps_counter_corner", fps_counter_corner)), 0, 3)
	performance_profile = clampi(int(config.get_value("display", "performance_profile", performance_profile)), 0, 2)
	modo_plano = bool(config.get_value("display", "modo_plano", modo_plano))
	aim_assist_level = clampi(int(config.get_value("controls", "aim_assist_level", aim_assist_level)), 0, 3)
	voice_enabled = bool(config.get_value("voice", "enabled", voice_enabled))
	voice_volume = clampf(float(config.get_value("voice", "volume", voice_volume)), 0.0, 1.0)
	voice_mode = clampi(int(config.get_value("voice", "mode", voice_mode)), 0, 1)
	voice_channel = clampi(int(config.get_value("voice", "channel", voice_channel)), 0, 2)
	for action in REMAPPABLE_ACTIONS:
		var binding = config.get_value("bindings", action, {})
		if binding is Dictionary:
			_restore_binding(action, binding)


func _restore_binding(action: String, binding: Dictionary) -> void:
	var kind := str(binding.get("kind", ""))
	if kind == "key":
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(binding.get("physical_keycode", 0))
		if key_event.physical_keycode != 0:
			_replace_primary_binding(action, key_event)
	elif kind == "joy_button":
		var joy_event := InputEventJoypadButton.new()
		joy_event.button_index = int(binding.get("button_index", 0))
		_replace_primary_binding(action, joy_event)


func _save() -> void:
	var config := ConfigFile.new()
	for bus_name in BUS_NAMES:
		config.set_value("audio", bus_name, _values[bus_name])
	config.set_value("audio", "output_device", audio_output_device)
	config.set_value("audio", "input_device", audio_input_device)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "controller_sensitivity", controller_sensitivity)
	config.set_value("controls", "auto_sprint", auto_sprint)
	config.set_value("controls", "double_tap_sprint", double_tap_sprint)
	config.set_value("display", "fps_limit", fps_limit)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "window_size", window_size)
	config.set_value("display", "render_scale", render_scale)
	config.set_value("display", "fps_counter_corner", fps_counter_corner)
	config.set_value("display", "performance_profile", performance_profile)
	config.set_value("display", "modo_plano", modo_plano)
	config.set_value("controls", "aim_assist_level", aim_assist_level)
	config.set_value("voice", "enabled", voice_enabled)
	config.set_value("voice", "volume", voice_volume)
	config.set_value("voice", "mode", voice_mode)
	config.set_value("voice", "channel", voice_channel)
	for action in REMAPPABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				config.set_value("bindings", action, {"kind": "key", "physical_keycode": event.physical_keycode})
				break
			if event is InputEventJoypadButton:
				config.set_value("bindings", action, {"kind": "joy_button", "button_index": event.button_index})
				break
	config.save(SETTINGS_PATH)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.022, 0.028, 0.985)
	style.border_color = Color(0.72, 0.16, 0.1, 1.0)
	style.set_border_width_all(4)
	style.border_width_top = 6
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	style.shadow_size = 24
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 14.0
	return style
