extends Node
## Actualizador remoto de Boomer Shooter.
##
## 1. Consulta update.json al arrancar.
## 2. Si hay version nueva (o la actual esta bloqueada) muestra un aviso propio.
## 3. "ACTUALIZAR" descarga el ejecutable nuevo EN SEGUNDO PLANO (con progreso),
##    comprueba su SHA-256 y, al reiniciar, un script auxiliar lo intercambia por
##    el actual y vuelve a abrir el juego. No se abre el navegador ni se
##    descarga nada a mano.

signal update_state_changed(state: String)

const MANIFEST_URL := "https://boomershooter.vercel.app/update.json"
const LOCAL_MANIFEST_PATH := "res://site/update.json"
const COPYRIGHT := "© 2026 xpe.nettt · Stealth Proyects"
const UPDATE_DIR := "user://update"
const FONT_PATH := "res://Assets/Fonts/Geizer.otf"

const COL_BG := Color(0.035, 0.022, 0.028, 0.985)
const COL_BLOOD := Color(0.72, 0.16, 0.1, 1.0)
const COL_ORANGE := Color(1.0, 0.45, 0.15, 1.0)
const COL_TEXT := Color(0.92, 0.82, 0.74, 1.0)
const COL_DIM := Color(0.62, 0.5, 0.45, 1.0)

## Se activa cuando el cliente esta por debajo de la version minima del manifiesto.
var blocks_game: bool = false

var _request: HTTPRequest
var _download: HTTPRequest
var _layer: CanvasLayer
var _manifest: Dictionary = {}
var _forced: bool = false
var _target_path: String = ""
var _progress: ProgressBar
var _status: Label
var _action_button: Button
var _later_button: Button
var _pulse_time: float = 0.0
var _title_label: Label
var _installing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	_request.request_completed.connect(_on_manifest_completed)
	add_child(_request)
	if OS.get_name() != "Web":
		_leer_resultado_anterior()
		_cleanup_old_update()
		await get_tree().create_timer(4.0).timeout
		_request.request(MANIFEST_URL)


func _process(delta: float) -> void:
	# Latido del titular: hace que el aviso no pase desapercibido.
	if _title_label == null or not is_instance_valid(_title_label):
		return
	_pulse_time += delta
	var k := 0.5 + 0.5 * sin(_pulse_time * 4.0)
	_title_label.add_theme_color_override("font_color", COL_ORANGE.lerp(Color(1.0, 0.12, 0.08), k))


func _on_manifest_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.has("version"):
		return
	handle_manifest(parsed)


## Decide entre bloqueo duro (por debajo del minimo) o aviso de version nueva.
func handle_manifest(manifest: Dictionary) -> void:
	_manifest = manifest
	var remote_version := str(manifest.get("version", ""))
	# Si el manifiesto no declara minimo, la version remota es el minimo.
	var minimum_version := str(manifest.get("minimum_version", remote_version))
	if _version_is_newer(minimum_version, _current_version()):
		blocks_game = true
		_forced = true
		_show_update_screen(remote_version)
		return
	if _version_is_newer(remote_version, _current_version()):
		_forced = false
		_show_update_screen(remote_version)


func _version_is_newer(remote: String, local: String) -> bool:
	var remote_parts := remote.trim_prefix("v").split(".")
	var local_parts := local.trim_prefix("v").split(".")
	for i in 3:
		var remote_number := int(remote_parts[i]) if i < remote_parts.size() else 0
		var local_number := int(local_parts[i]) if i < local_parts.size() else 0
		if remote_number != local_number:
			return remote_number > local_number
	return false


func _current_version() -> String:
	var patched := str(PatchLoader.mounted_version) if get_node_or_null("/root/PatchLoader") else ""
	if patched != "":
		return patched
	# La version real del build es la de ProjectSettings; el manifiesto local solo
	# es respaldo, porque se quedaba congelado y el cliente se creia viejo siempre.
	var project_version := str(ProjectSettings.get_setting("application/config/version", ""))
	if project_version != "":
		return project_version
	if not FileAccess.file_exists(LOCAL_MANIFEST_PATH):
		return "0.0.0"
	var local_manifest = JSON.parse_string(FileAccess.get_file_as_string(LOCAL_MANIFEST_PATH))
	if local_manifest is Dictionary:
		return str(local_manifest.get("version", "0.0.0"))
	return "0.0.0"


# --------------------------------------------------------------------------
# Datos del manifiesto
# --------------------------------------------------------------------------

func _platform_url() -> String:
	return str(_manifest.get("linux_url", "")) if OS.get_name() == "Linux" else str(_manifest.get("windows_url", ""))


func _platform_sha256() -> String:
	var key := "linux_sha256" if OS.get_name() == "Linux" else "windows_sha256"
	return str(_manifest.get(key, "")).to_lower()


## Un parche solo existe para Windows/Linux y si el manifiesto lo declara para ESTE motor.
func _patch_available() -> bool:
	var patch = _manifest.get("patch", {})
	if not patch is Dictionary or str(patch.get("url", "")) == "":
		return false
	if str(patch.get("engine_revision", "")) != str(ProjectSettings.get_setting("application/config/engine_revision", "1")):
		return false
	# Solo se puede parchear desde versiones que el manifiesto declara compatibles.
	return _version_is_newer(str(patch.get("min_base", "0.0.0")), _current_version()) == false


func _download_size_text() -> String:
	var bytes := int(_manifest.get("patch", {}).get("size", 0)) if _patch_available() else _platform_size()
	return "%.0f MB" % (bytes / 1048576.0) if bytes > 0 else ""


func _platform_size() -> int:
	var key := "linux_size" if OS.get_name() == "Linux" else "windows_size"
	return int(_manifest.get(key, 0))


## Convierte las notas del manifiesto en lineas. Admite una lista JSON o texto con ";" / saltos.
static func parse_notes(raw) -> PackedStringArray:
	var lines := PackedStringArray()
	if raw is Array:
		for item in raw:
			var text := str(item).strip_edges()
			if text != "":
				lines.append(text)
		return lines
	var normalized := str(raw).replace(";", "\n").replace("\r", "")
	for part in normalized.split("\n"):
		var text := part.strip_edges()
		if text != "":
			lines.append(text)
	return lines


## True solo si la ruta es el ejecutable del juego (BoomerShooter.exe / boomershooter.*).
static func is_game_executable(path: String) -> bool:
	if path == "":
		return false
	var name := path.get_file().to_lower()
	return name.begins_with("boomershooter") and not name.contains("godot") and not name.ends_with(".new") and not name.ends_with(".new.exe")


## Puede actualizarse sin navegador: hay URL y la instalacion permite reemplazar el ejecutable.
func can_self_update() -> bool:
	if OS.has_feature("editor") or OS.get_name() == "Web":
		return false
	if _patch_available():
		return true
	if _platform_url() == "":
		return false
	return is_game_executable(OS.get_executable_path())


# --------------------------------------------------------------------------
# Pantalla de actualizacion
# --------------------------------------------------------------------------

func _label(text_value: String, size: int, color: Color, bold_font: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold_font and ResourceLoader.exists(FONT_PATH):
		label.add_theme_font_override("font", load(FONT_PATH))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text_value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_ALL
	var base := Color(0.55, 0.08, 0.05) if primary else Color(0.12, 0.07, 0.07)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var tint := base
		if state == "hover" or state == "focus":
			tint = base.lightened(0.18)
		elif state == "pressed":
			tint = base.darkened(0.2)
		elif state == "disabled":
			tint = Color(0.1, 0.08, 0.08)
		style.bg_color = tint
		style.border_color = COL_ORANGE if primary and state != "disabled" else Color(0.35, 0.16, 0.12)
		style.set_border_width_all(3)
		style.set_corner_radius_all(2)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.38, 0.36))
	return button


func _show_update_screen(new_version: String) -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 200
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Velo oscuro que bloquea todo lo de debajo.
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.0, 0.0, 0.88)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BLOOD
	style.set_border_width_all(4)
	style.border_width_top = 8
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.8, 0.05, 0.02, 0.35)
	style.shadow_size = 40
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var kicker := _label("// SISTEMA DE ACTUALIZACION", 14, COL_DIM)
	box.add_child(kicker)

	_title_label = _label("TU VERSION YA ES UN CADAVER." if _forced else "LLEGA SANGRE NUEVA.", 34, COL_ORANGE, true)
	box.add_child(_title_label)

	var subtitle := _label(
		"Esta version ya no puede jugar. Actualiza para volver a la arena." if _forced
		else "Hay una version nueva esperandote. Se instala sola y el juego se reinicia.", 17, COL_TEXT)
	box.add_child(subtitle)

	box.add_child(_divider())

	var versions := HBoxContainer.new()
	versions.add_theme_constant_override("separation", 14)
	versions.add_child(_label("v%s" % _current_version(), 26, COL_DIM, true))
	versions.add_child(_label(">>>", 26, COL_BLOOD, true))
	versions.add_child(_label("v%s" % new_version, 26, Color(1.0, 0.82, 0.55), true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	versions.add_child(spacer)
	if _forced:
		versions.add_child(_label("OBLIGATORIA", 16, Color(1.0, 0.2, 0.15), true))
	box.add_child(versions)

	var notes := parse_notes(_manifest.get("notes", "Consulta las novedades en la pagina oficial."))
	var notes_box := VBoxContainer.new()
	notes_box.add_theme_constant_override("separation", 6)
	notes_box.add_child(_label("QUE TRAE", 14, COL_DIM))
	var shown := 0
	for line in notes:
		if shown >= 6:
			break
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var bullet := ColorRect.new()
		bullet.color = COL_BLOOD
		bullet.custom_minimum_size = Vector2(10, 10)
		bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bullet)
		var text_label := _label(line, 16, COL_TEXT)
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_label)
		notes_box.add_child(row)
		shown += 1
	box.add_child(notes_box)

	box.add_child(_divider())

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.custom_minimum_size = Vector2(0, 26)
	_progress.show_percentage = true
	_progress.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.2, 0.08)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.06, 0.06)
	back.border_color = Color(0.35, 0.16, 0.12)
	back.set_border_width_all(2)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", back)
	box.add_child(_progress)

	_status = _label("", 15, COL_DIM)
	_status.visible = false
	box.add_child(_status)
	# Si el intento anterior fallo al reemplazar el ejecutable, se dice por que en vez de
	# volver a pedir la actualizacion como si nada.
	if ultimo_resultado.begins_with("FALLO"):
		_set_status("La ultima instalacion no pudo reemplazar el juego. Cierra el antivirus un momento, o descarga el .exe desde la web y sustituyelo a mano.", true)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var size_text := _download_size_text()
	_action_button = _button("ACTUALIZAR Y REINICIAR" + (" (%s)" % size_text if size_text != "" else ""), true)
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.pressed.connect(_on_action_pressed)
	buttons.add_child(_action_button)
	if not _forced:
		_later_button = _button("MAS TARDE", false)
		_later_button.custom_minimum_size = Vector2(170, 54)
		_later_button.pressed.connect(_close_screen)
		buttons.add_child(_later_button)
	else:
		var leave := _button("SALIR", false)
		leave.custom_minimum_size = Vector2(130, 54)
		leave.pressed.connect(func() -> void: get_tree().quit())
		buttons.add_child(leave)
	box.add_child(buttons)

	var foot := _label(COPYRIGHT, 12, Color(0.5, 0.42, 0.4))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)

	_action_button.grab_focus()
	update_state_changed.emit("shown")


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 3)
	line.color = Color(0.55, 0.07, 0.07, 0.9)
	return line


func _close_screen() -> void:
	if _layer:
		_layer.queue_free()
		_layer = null
	_title_label = null
	update_state_changed.emit("closed")


# --------------------------------------------------------------------------
# Descarga e instalacion
# --------------------------------------------------------------------------

func _on_action_pressed() -> void:
	if _installing:
		return
	if not can_self_update():
		# Instalacion que no se puede reemplazar sola (editor, carpeta de solo lectura...).
		var url := _platform_url()
		if url != "":
			OS.shell_open(url)
		get_tree().quit()
		return
	_start_download()


func _set_status(text_value: String, is_error: bool = false) -> void:
	if _status:
		_status.visible = true
		_status.text = text_value
		_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2) if is_error else COL_DIM)


func _start_download() -> void:
	_installing = true
	_action_button.disabled = true
	if _later_button:
		_later_button.disabled = true
	_progress.visible = true
	_progress.value = 0.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DIR))
	var file_name := "BoomerShooter.new.exe" if OS.get_name() == "Windows" else "boomershooter.new"
	if _patch_available():
		file_name = "content.pck.part"
	_target_path = ProjectSettings.globalize_path(UPDATE_DIR).path_join(file_name)
	if FileAccess.file_exists(_target_path):
		DirAccess.remove_absolute(_target_path)
	_download = HTTPRequest.new()
	_download.download_file = _target_path
	_download.use_threads = true
	_download.timeout = 0.0
	_download.request_completed.connect(_on_download_completed)
	add_child(_download)
	var err := _download.request(str(_manifest["patch"]["url"]) if _patch_available() else _platform_url())
	if err != OK:
		_fail("No se pudo iniciar la descarga (error %d)." % err)
		return
	_set_status("Descargando actualizacion...")
	var tick := Timer.new()
	tick.wait_time = 0.15
	tick.autostart = true
	tick.timeout.connect(_update_progress)
	add_child(tick)


func _update_progress() -> void:
	if _download == null or not is_instance_valid(_download):
		return
	var done := _download.get_downloaded_bytes()
	var total := _download.get_body_size()
	if total <= 0:
		total = _platform_size()
	if total > 0:
		_progress.value = clampf(float(done) / float(total) * 100.0, 0.0, 100.0)
		_set_status("Descargando... %.1f / %.1f MB" % [done / 1048576.0, total / 1048576.0])
	else:
		_set_status("Descargando... %.1f MB" % (done / 1048576.0))


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("La descarga fallo (codigo %d). Revisa tu conexion e intentalo de nuevo." % response_code)
		return
	_progress.value = 100.0
	_set_status("Comprobando integridad...")
	await get_tree().process_frame
	var expected := str(_manifest["patch"].get("sha256", "")).to_lower() if _patch_available() else _platform_sha256()
	if expected != "":
		var actual := FileAccess.get_sha256(_target_path).to_lower()
		if actual != expected:
			DirAccess.remove_absolute(_target_path)
			_fail("El archivo descargado esta corrupto. No se instalo nada.")
			return
	var expected_size := int(_manifest["patch"].get("size", 0)) if _patch_available() else _platform_size()
	if expected_size > 0:
		var file := FileAccess.open(_target_path, FileAccess.READ)
		var real_size := file.get_length() if file else 0
		if file:
			file.close()
		if real_size != expected_size:
			DirAccess.remove_absolute(_target_path)
			_fail("El archivo descargado esta incompleto. No se instalo nada.")
			return
	_set_status("Listo. Reiniciando...")
	await get_tree().create_timer(0.8).timeout
	if _patch_available():
		_install_patch_and_restart()
	else:
		_apply_and_restart()


func _fail(message: String) -> void:
	_installing = false
	if _download and is_instance_valid(_download):
		_download.queue_free()
	_set_status(message, true)
	_progress.visible = false
	_action_button.disabled = false
	_action_button.text = "REINTENTAR"
	if _later_button:
		_later_button.disabled = false


## Modo parche: coloca el .pck verificado y relanza el MISMO ejecutable (no se reemplaza nada).
func _install_patch_and_restart() -> void:
	var patch_dir := ProjectSettings.globalize_path("user://patch")
	DirAccess.make_dir_recursive_absolute(patch_dir)
	var final_pck := patch_dir.path_join("content.pck")
	if FileAccess.file_exists(final_pck):
		DirAccess.remove_absolute(final_pck)
	if DirAccess.rename_absolute(_target_path, final_pck) != OK:
		_fail("No se pudo guardar el parche.")
		return
	var info := {
		"version": str(_manifest.get("version", "")),
		"sha256": str(_manifest["patch"].get("sha256", "")),
		"engine_revision": str(_manifest["patch"].get("engine_revision", "1")),
	}
	var file := FileAccess.open(patch_dir.path_join("content.json"), FileAccess.WRITE)
	if file == null:
		_fail("No se pudo guardar el parche.")
		return
	file.store_string(JSON.stringify(info))
	file.close()
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_user_args())
	get_tree().quit()


## Escribe el script de relevo, lo lanza y cierra el juego para que pueda reemplazarse.
func _apply_and_restart() -> void:
	var current := OS.get_executable_path()
	# Defensa final: jamas sobrescribir un ejecutable que no sea el propio juego
	# (por ejemplo el editor de Godot o un lanzador). can_self_update() ya lo
	# comprueba, pero se repite aqui porque este es el unico paso destructivo.
	if not is_game_executable(current):
		_fail("Esta instalacion no se puede actualizar sola. Descarga la nueva version desde la web.")
		var url := _platform_url()
		if url != "":
			OS.shell_open(url)
		return
	if OS.get_name() == "Windows":
		var script_path := ProjectSettings.globalize_path(UPDATE_DIR).path_join("apply_update.cmd")
		var file := FileAccess.open(script_path, FileAccess.WRITE)
		if file == null:
			_fail("No se pudo preparar la instalacion.")
			return
		file.store_string(build_windows_script(current, _target_path))
		file.close()
		_lanzar_oculto_windows(script_path)
	else:
		var script_path := ProjectSettings.globalize_path(UPDATE_DIR).path_join("apply_update.sh")
		var file := FileAccess.open(script_path, FileAccess.WRITE)
		if file == null:
			_fail("No se pudo preparar la instalacion.")
			return
		file.store_string(build_unix_script(current, _target_path))
		file.close()
		OS.create_process("/bin/sh", [script_path])
	get_tree().quit()


## Lanza el .cmd SIN ventana. Un `start /min` seguia mostrando la consola y el juego,
## al reabrirse desde ella, heredaba ese CMD (los jugadores veian una ventana negra con
## los mensajes del motor). WScript.Shell.Run con estilo 0 la crea oculta de verdad.
func _lanzar_oculto_windows(script_path: String) -> void:
	var vbs_path := script_path.get_basename() + ".vbs"
	var file := FileAccess.open(vbs_path, FileAccess.WRITE)
	if file != null:
		file.store_string(build_windows_launcher(vbs_path.get_file(), script_path))
		file.close()
		if OS.create_process("wscript.exe", [vbs_path]) > 0:
			return
	# Respaldo: si wscript no esta disponible, se usa cmd oculto por consola propia.
	OS.create_process("cmd.exe", ["/c", "start", "\"\"", "/min", script_path])


## VBS de una linea: ejecuta el .cmd con la ventana oculta (0) y sin esperar.
static func build_windows_launcher(vbs_name: String, cmd_path: String) -> String:
	var base := cmd_path.get_base_dir().replace("/", "\\")
	return "\r\n".join([
		"' Lanzador silencioso del actualizador de Boomer Shooter.",
		"DIM q, shell, cmd" ,
		"q = Chr(34)",
		"Set shell = CreateObject(\"WScript.Shell\")",
		"shell.CurrentDirectory = \"%s\"" % base,
		"shell.Run \"cmd /c \" & q & q & \"%s\" & q & q, 0, False" % cmd_path.replace("/", "\\"),
		"",
	])


## Script .cmd: espera a que el juego cierre, copia el nuevo encima (con reintentos), abre y se borra.
static func build_windows_script(current_exe: String, new_exe: String) -> String:
	# el directorio se calcula ANTES de pasar a barras de Windows: get_base_dir() solo entiende "/"
	var dir := current_exe.get_base_dir().replace("/", "\\")
	var cur := current_exe.replace("/", "\\")
	var new := new_exe.replace("/", "\\")
	return "\r\n".join([
		"@echo off",
		"setlocal",
		"set \"CUR=%s\"" % cur,
		"set \"NEW=%s\"" % new,
		"set \"LOG=%s\\resultado_actualizacion.txt\"" % dir,
		"set /a TRIES=0",
		":wait",
		"set /a TRIES+=1",
		"if %TRIES% GTR 90 goto fail",
		"timeout /t 1 /nobreak >nul",
		# el exe en uso o bloqueado por el antivirus no se puede pisar: se reintenta
		"copy /y \"%NEW%\" \"%CUR%.nuevo\" >nul 2>&1",
		"if errorlevel 1 goto wait",
		"move /y \"%CUR%.nuevo\" \"%CUR%\" >nul 2>&1",
		"if errorlevel 1 goto wait",
		# verificacion: el exe instalado debe pesar lo mismo que el descargado
		"for %%A in (\"%NEW%\") do set SIZE_NEW=%%~zA",
		"for %%A in (\"%CUR%\") do set SIZE_CUR=%%~zA",
		"if not \"%SIZE_NEW%\"==\"%SIZE_CUR%\" goto wait",
		"del /f /q \"%NEW%\" >nul 2>&1",
		"echo OK %DATE% %TIME% instalado >> \"%LOG%\"",
		"start \"\" \"%CUR%\"",
		"goto end",
		":fail",
		# no se borra lo descargado: el juego puede reintentar sin volver a bajarlo
		"echo FALLO %DATE% %TIME% no se pudo reemplazar el ejecutable (cierra el antivirus o ejecuta como administrador) >> \"%LOG%\"",
		"start \"\" \"%CUR%\"",
		":end",
		"(goto) 2>nul & del \"%~f0\"",
		""])


static func build_unix_script(current_exe: String, new_exe: String) -> String:
	return "\n".join([
		"#!/bin/sh",
		"CUR='%s'" % current_exe.replace("'", "'\\''"),
		"NEW='%s'" % new_exe.replace("'", "'\\''"),
		"i=0",
		"while [ $i -lt 60 ]; do",
		"  sleep 1; i=$((i+1))",
		"  if cp -f \"$NEW\" \"$CUR.tmp\" 2>/dev/null && chmod +x \"$CUR.tmp\" && mv -f \"$CUR.tmp\" \"$CUR\"; then",
		"    rm -f \"$NEW\"; break",
		"  fi",
		"done",
		"\"$CUR\" &",
		"rm -f \"$0\"",
		""])


## Ultimo resultado del script de relevo ("OK ..." o "FALLO ..."). Se imprime en consola y,
## si fallo, se avisa en la pantalla de actualizacion en vez de pedirla otra vez sin explicacion.
var ultimo_resultado: String = ""

func _leer_resultado_anterior() -> void:
	var carpeta := OS.get_executable_path().get_base_dir()
	var ruta := carpeta.path_join("resultado_actualizacion.txt")
	if not FileAccess.file_exists(ruta):
		return
	var lineas := FileAccess.get_file_as_string(ruta).strip_edges().split("\n")
	if lineas.is_empty():
		return
	ultimo_resultado = str(lineas[lineas.size() - 1]).strip_edges()
	if OS.is_debug_build():
		print("[actualizacion] ultimo intento: ", ultimo_resultado)
	if ultimo_resultado.begins_with("OK"):
		# instalado bien: se limpia para no arrastrar el aviso
		DirAccess.remove_absolute(ruta)
		ultimo_resultado = ""


## Borra restos de una actualizacion anterior ya aplicada.
func _cleanup_old_update() -> void:
	var dir_path := ProjectSettings.globalize_path(UPDATE_DIR)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		# si el ultimo relevo fallo se conserva lo ya descargado para reintentar sin bajar 142 MB otra vez
		if ultimo_resultado.begins_with("FALLO") and not file_name.ends_with(".cmd") and not file_name.ends_with(".sh"):
			continue
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	# user://patch (el parche activo) NO se toca aqui.
