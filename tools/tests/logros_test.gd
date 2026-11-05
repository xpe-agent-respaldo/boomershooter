extends Node
## Pruebas de la version 1.2.7:
##  * los logros (lista, ids antiguos, progreso guardado, pantalla y aviso)
##  * el actualizador ya no abre ninguna ventana de consola
##  * los ganchos de logros siguen puestos en el codigo del juego
##
## Uso: godot --headless --path . tools/tests/logros_test.tscn

var fallos: int = 0
var aciertos: int = 0


func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


func _ready() -> void:
	print("== LOGROS: lista ==")
	_probar_lista()
	print("== LOGROS: progreso y guardado ==")
	_probar_progreso()
	print("== LOGROS: aviso en partida ==")
	await _probar_aviso()
	print("== LOGROS: pantalla ==")
	await _probar_pantalla()
	print("== ACTUALIZADOR: sin ventana de consola ==")
	_probar_actualizador()
	print("== GANCHOS en el codigo del juego ==")
	_probar_ganchos()
	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)


# --------------------------------------------------------------------------

const IDS_ANTIGUOS := ["primera_sangre", "carnicero", "exterminador", "oleada_5",
	"oleada_10", "oleada_20", "primera_partida", "diez_partidas", "comprador"]


func _probar_lista() -> void:
	var vistos := {}
	var dup := 0
	for a in Achievements.LISTA:
		var id := str(a["id"])
		if vistos.has(id):
			dup += 1
		vistos[id] = true
	ok("sin ids duplicados", dup == 0, "duplicados=%d" % dup)
	ok("hay 25 logros o mas", Achievements.LISTA.size() >= 25, "total=%d" % Achievements.LISTA.size())
	var faltan := []
	for id in IDS_ANTIGUOS:
		if not vistos.has(id):
			faltan.append(id)
	ok("conserva los 9 ids antiguos", faltan.is_empty(), str(faltan))
	var sin_cat := 0
	var sin_rareza := 0
	for a in Achievements.LISTA:
		if str(a.get("cat", "")) == "":
			sin_cat += 1
		if not Achievements.RAREZAS.has(str(a.get("rareza", ""))):
			sin_rareza += 1
	ok("todos tienen categoria", sin_cat == 0, "%d sin categoria" % sin_cat)
	ok("todos tienen rareza valida", sin_rareza == 0, "%d sin rareza" % sin_rareza)
	var secretos := 0
	for a in Achievements.LISTA:
		if bool(a.get("secreto", false)):
			secretos += 1
	ok("hay logros secretos", secretos >= 2, "secretos=%d" % secretos)
	var metas_malas := 0
	for a in Achievements.LISTA:
		if int(a["meta"]) <= 0:
			metas_malas += 1
	ok("todas las metas son positivas", metas_malas == 0, "%d malas" % metas_malas)


func _probar_progreso() -> void:
	# Estado inicial limpio para que el test no dependa de la partida del usuario.
	Achievements.progreso = {}
	Achievements.desbloqueados = {}
	Achievements.mapas_vistos = {}
	ok("empieza sin logros", Achievements.conseguidos() == 0)

	var emitidos := []
	var captura := func(id: String, _n: String, _p: int, _r: String, _s: bool) -> void: emitidos.append(id)
	Achievements.unlocked.connect(captura)

	Achievements.marca("oleada", 10)
	ok("oleada 10 desbloquea AGUANTE y VETERANO",
		Achievements.esta("oleada_5") and Achievements.esta("oleada_10"))
	ok("oleada 10 no desbloquea INQUEBRANTABLE", not Achievements.esta("oleada_20"))
	ok("la senal avisa al desbloquear", emitidos.has("oleada_10"), str(emitidos))

	Achievements.suma("kills", 1000)
	ok("1000 bajas desbloquean CARNICERO y EXTERMINADOR",
		Achievements.esta("carnicero") and Achievements.esta("exterminador"))
	ok("1000 bajas no desbloquean MASACRE", not Achievements.esta("masacre"))

	Achievements.suma("partidas", 1)
	ok("la primera partida ya se puede conseguir (antes era imposible)", Achievements.esta("primera_partida"))

	Achievements.mapa_jugado("SpaceArena")
	Achievements.mapa_jugado("SpaceArena")
	Achievements.mapa_jugado("StormVillage")
	ok("contar mapas no repite el mismo mapa", Achievements._de("mapas") == 2, "mapas=%d" % Achievements._de("mapas"))
	Achievements.mapa_jugado("RecyclingPlant")
	ok("los 3 mapas desbloquean TROTAMUNDOS", Achievements.esta("trotamundos"))
	Achievements.mapa_jugado("TestLevel")
	ok("los mapas de prueba no cuentan", Achievements._de("mapas") == 3, "mapas=%d" % Achievements._de("mapas"))

	var coins_antes := Shop.coins
	Achievements.suma("kills", 10)  # ninguno nuevo
	ok("no paga dos veces el mismo logro", Shop.coins == coins_antes)
	ok("el premio se cobra en monedas", coins_antes > 0)

	# Guardado real en disco y recarga.
	Achievements.save_data()
	var copia := Achievements.desbloqueados.duplicate(true)
	var copia_mapa := Achievements.mapas_vistos.duplicate(true)
	Achievements.desbloqueados = {}
	Achievements.mapas_vistos = {}
	Achievements.load_data()
	var mismos := true
	for id in copia.keys():
		if not Achievements.esta(str(id)):
			mismos = false
	ok("el progreso sobrevive al guardado", mismos and Achievements.desbloqueados.size() == copia.size())
	ok("los mapas vistos sobreviven al guardado", Achievements.mapas_vistos.size() == copia_mapa.size())

	Achievements.soltar("caidas")
	ok("un secreto se puede soltar desde codigo", Achievements.esta("caidas"))
	Achievements.unlocked.disconnect(captura)


func _probar_aviso() -> void:
	# Se vacia lo que haya en pantalla para mirar un aviso concreto.
	for h in LogroAviso._caja.get_children():
		h.free()
	LogroAviso._cola.clear()
	LogroAviso._mostrando = false
	await get_tree().process_frame

	Achievements.soltar("cazador_alfa")
	await get_tree().process_frame
	await get_tree().process_frame
	ok("el aviso aparece al conseguir un logro", LogroAviso._caja.get_child_count() == 1,
		"%d avisos" % LogroAviso._caja.get_child_count())
	var panel: Control = LogroAviso._caja.get_child(0) if LogroAviso._caja.get_child_count() > 0 else null
	ok("el aviso es un panel con texto", panel != null and _textos(panel).length() > 0, "")
	if panel != null:
		var t := _textos(panel)
		ok("el aviso no tapa el contador de KILLS", LogroAviso._caja.offset_top >= 80.0,
			"offset_top=%.0f" % LogroAviso._caja.offset_top)
		ok("el aviso dice el nombre del logro", t.contains("CAZADOR DE ALFA"), t)
		ok("el aviso dice el premio", t.contains("+150"), t)
		ok("el aviso ignora el raton", panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# Dos logros seguidos no se pisan: el segundo espera en cola.
	Achievements.soltar("rompejefes")
	await get_tree().process_frame
	ok("los avisos seguidos se encolan", LogroAviso._caja.get_child_count() == 1 and LogroAviso._cola.size() == 1,
		"en pantalla=%d en cola=%d" % [LogroAviso._caja.get_child_count(), LogroAviso._cola.size()])


func _textos(nodo: Node) -> String:
	var out := ""
	if nodo is Label:
		out += (nodo as Label).text + " | "
	for h in nodo.get_children():
		out += _textos(h)
	return out


func _probar_pantalla() -> void:
	var escena: PackedScene = load("res://Levels/Achievements.tscn")
	ok("la escena de logros carga", escena != null)
	if escena == null:
		return
	# Dentro de un SubViewport de 1920x1080 para medir la maquetacion de verdad.
	var sv := SubViewport.new()
	sv.size = Vector2i(1920, 1080)
	add_child(sv)
	var inst: Control = escena.instantiate()
	sv.add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	ok("la pantalla ocupa todo el alto", inst.size.y == 1080.0, "%.0f" % inst.size.y)
	var grid: GridContainer = inst._grid
	ok("la pantalla se construye sin errores", grid != null)
	if grid == null:
		return
	ok("hay una tarjeta por logro", grid.get_child_count() == Achievements.LISTA.size(),
		"%d de %d" % [grid.get_child_count(), Achievements.LISTA.size()])
	ok("la rejilla tiene dos columnas", grid.columns == 2)
	ok("las tarjetas llevan la fuente del juego", _usa_geizer(grid), "")
	inst._filtro = "combate"
	inst._rellenar()
	await get_tree().process_frame
	ok("el filtro de categoria reduce la lista",
		grid.get_child_count() == Achievements.de_categoria("combate").size(),
		"%d tarjetas" % grid.get_child_count())
	inst._filtro = "especial"
	inst._rellenar()
	await get_tree().process_frame
	ok("la categoria especial (secretos) tiene tarjetas", grid.get_child_count() >= 2,
		"%d tarjetas" % grid.get_child_count())
	var textos := _textos(inst)
	ok("los secretos sin conseguir se tapan con ???", texto_tapado(textos), "")

	# La pantalla debe caber en 1920x1080: nin rejilla fuera ni textos cortados.
	var fuera := []
	var cortados := _textos_cortados(inst)
	for tarjeta in grid.get_children():
		var r: Rect2 = (tarjeta as Control).get_global_rect()
		if r.position.x < 0 or r.position.y < 0 or r.end.x > 1920.5 or r.end.y > 1080.5:
			fuera.append(str((tarjeta as Control).name))
	ok("todas las tarjetas caben en pantalla", fuera.is_empty(), str(fuera))
	ok("ningun texto queda cortado", cortados.is_empty(), str(cortados))
	var alto_total := 0.0
	for tarjeta in grid.get_children():
		alto_total += (tarjeta as Control).size.y
	ok("las tarjetas no se estiran de mas", alto_total / maxf(1.0, grid.get_child_count()) < 200.0,
		"alto medio %.0f" % (alto_total / maxf(1.0, grid.get_child_count())))
	inst.queue_free()
	sv.queue_free()
	await get_tree().process_frame


## Etiquetas cuyo texto no cabe en su caja (se verian con puntos suspensivos).
func _textos_cortados(nodo: Node) -> Array:
	var malos := []
	if nodo is Label:
		var l := nodo as Label
		var f: Font = l.get_theme_font("font")
		var tam: int = l.get_theme_font_size("font_size")
		if f != null and l.text != "":
			var ancho := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
			if ancho > l.size.x + 2.0:
				malos.append("%s (%.0f > %.0f)" % [l.text, ancho, l.size.x])
	for h in nodo.get_children():
		malos.append_array(_textos_cortados(h))
	return malos


func texto_tapado(textos: String) -> bool:
	return textos.contains("???")


func _usa_geizer(nodo: Node) -> bool:
	if nodo is Label:
		var f = (nodo as Label).get_theme_font("font")
		return f != null and String(f.resource_path).ends_with("Geizer.otf")
	for h in nodo.get_children():
		if _usa_geizer(h):
			return true
	return false


func _probar_actualizador() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://export_presets.cfg")
	ok("export_presets.cfg se puede leer", err == OK)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok("el .exe de Windows ya no lleva consola (export_console_wrapper=0)",
		not presets.contains("debug/export_console_wrapper=1"), "")

	var cmd := "C:/Users/marti/AppData/Roaming/Godot/app_userdata/Boomer Shooter/update/apply_update.cmd"
	var vbs: String = load("res://Scripts/update_manager.gd").build_windows_launcher("apply_update.vbs", cmd)
	print("---- VBS generado ----")
	print(vbs)
	print("----------------------")
	ok("el lanzador oculto crea un WScript.Shell", vbs.contains("CreateObject(\"WScript.Shell\")"))
	ok("el lanzador pide ventana oculta (estilo 0)", vbs.contains(", 0, False"))
	ok("el lanzador usa rutas de Windows", vbs.contains("\\update\\apply_update.cmd"), "")
	ok("el lanzador no usa 'start /min'", not vbs.contains("/min"))
	ok("las comillas del .cmd van escapadas con Chr(34)", vbs.contains("q = Chr(34)"))

	var script: String = load("res://Scripts/update_manager.gd").build_windows_script(
		"C:/Juegos/BoomerShooter.exe", "C:/Users/marti/AppData/Roaming/Godot/app_userdata/Boomer Shooter/update/descarga.exe")
	ok("el .cmd sigue esperando a que el juego cierre", script.contains(":wait") and script.contains("copy /y"))
	ok("el .cmd reabre el juego al terminar", script.contains("start \"\" \"%CUR%\""))


func _probar_ganchos() -> void:
	var esperados := {
		"Scenes/Enemies/Enemy.gd": ["Achievements.suma(\"kills\")", "Achievements.suma(\"headshots\")", "Achievements.suma(\"elites\")"],
		"Scripts/UI.gd": ["Achievements.suma(\"partidas\")", "Achievements.mapa_jugado(", "Achievements.soltar(\"madrugador\")"],
		"Scripts/SpawnManager.gd": ["Achievements.marca(\"oleada\"", "set_meta(\"elite\", true)"],
		"Scripts/team_alerts.gd": ["Achievements.suma(\"revives\")"],
		"Scripts/shop.gd": ["Achievements.suma(\"compras\")"],
		"Scripts/ach_screen.gd": ["Achievements.suma(\"logros_vistos\")"],
	}
	for ruta in esperados.keys():
		var texto := FileAccess.get_file_as_string("res://" + str(ruta))
		for trozo in esperados[ruta]:
			ok("%s contiene %s" % [ruta, trozo], texto.contains(str(trozo)), "")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	ok("el aviso de logros es autoload", proj.contains("LogroAviso=\"*res://Scripts/logro_aviso.gd\""))
	ok("la version del proyecto es 1.2.7", proj.contains("config/version=\"1.2.7\""))
	ok("el sonido del aviso existe", FileAccess.file_exists("res://Assets/Sounds/SFX/logro.wav"))
