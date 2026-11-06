class_name EndScreen
extends CanvasLayer
## Pantalla de FINAL de partida. El servidor ya mandaba el resultado (victoria/derrota, oleada,
## bajas por jugador), pero el cliente lo ignoraba: la partida simplemente "se acababa" sin decir
## nada. Aqui se cuenta que paso: si se gano, por que se perdio, y que hizo cada uno.
##
## Se alimenta con el diccionario que manda el servidor, asi se prueba sin red.

const MOTIVOS := {
	"victory": "Habeis superado todas las oleadas.",
	"duel_won": "",
	"team_won": "",
	"team_wipe": "Todo el equipo ha caido.",
	"team_wipe_after_leave": "El equipo se quedo sin nadie en pie.",
	"empty": "La sala se quedo vacia.",
	"vote_close": "La sala se cerro por votacion.",
	"closed": "La partida ha terminado.",
}
const NOMBRES_MODO := {
	"coop_waves": "OLEADAS", "survival": "SUPERVIVENCIA", "horde": "HORDA",
	"boss_rush": "JEFES", "freestylers": "MATADERO", "duelo": "DUELO",
	"tdm": "DUELO POR EQUIPOS", "dominio": "DOMINAR EL PUNTO", "caliente": "PUNTO CALIENTE",
}
const MODOS_EQUIPOS := ["tdm", "dominio", "caliente"]

signal salir_pulsado
var _raiz: Control
var boton_salir: Button


## Construye y muestra la pantalla. `yo` es el user_id local (para marcar la fila "TU").
func mostrar(resultado: Dictionary, yo: String = "") -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gano: bool = resultado.get("won", false) == true
	var modo: String = str(resultado.get("mode", ""))
	var razon: String = str(resultado.get("reason", "closed"))
	var es_duelo := modo == "duelo"
	var es_equipos := modo in MODOS_EQUIPOS

	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_raiz)
	var velo := ColorRect.new()
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.color = Color(0.0, 0.0, 0.0, 0.78)
	_raiz.add_child(velo)

	var centro := MarginContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right"]:
		centro.add_theme_constant_override("margin_" + lado, 510)
	centro.add_theme_constant_override("margin_top", 60)
	centro.add_theme_constant_override("margin_bottom", 60)
	_raiz.add_child(centro)
	var panel := UIKit.panel(30)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro.add_child(panel)
	# alto limitado al de la pantalla de diseno (1920x1080): el contenido sobrante se desplaza
	centro.custom_minimum_size = Vector2(0, 0)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	panel.add_child(caja)

	var color := UIKit.COL_EMBER if gano else UIKit.COL_BLOOD
	if es_equipos:
		var mio := _mi_equipo(resultado, yo)
		var gan := str(resultado.get("winner_team", ""))
		gano = (not gan.is_empty() and gan == mio)
		color = UIKit.COL_EMBER if gano else UIKit.COL_BLOOD
	var titulo := UIKit.label(_titulo_final(es_duelo, es_equipos, gano, resultado, yo), 76, color, true)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.name = "Titulo"
	caja.add_child(titulo)

	var sub := UIKit.label(_subtitulo(es_duelo, modo, razon, resultado), 24, UIKit.COL_BONE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.name = "Subtitulo"
	caja.add_child(sub)
	caja.add_child(UIKit.divider())

	if es_equipos:
		caja.add_child(_marcador_equipos(resultado))
	if not es_duelo and not es_equipos:
		var meta := int(resultado.get("wave_goal", 0))
		var oleada := int(resultado.get("wave_reached", 0))
		var progreso := "OLEADA %d" % oleada if meta <= 0 else "OLEADA %d DE %d" % [mini(oleada, meta), meta]
		var l := UIKit.label(progreso, 30, UIKit.COL_EMBER, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.name = "Progreso"
		caja.add_child(l)

	# El marcador puede tener hasta 40 filas: va en una zona con altura maxima y desplazable, asi el
	# boton de salir queda SIEMPRE a la vista (si no, en una sala llena el jugador no podria salir).
	var zona := ScrollContainer.new()
	zona.name = "ZonaMarcador"
	zona.custom_minimum_size = Vector2(0, 40)
	zona.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zona.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var tabla := _tabla(resultado, yo, es_duelo)
	tabla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zona.add_child(tabla)
	caja.add_child(zona)

	var mi_fila := _mi_fila(resultado, yo)
	if not mi_fila.is_empty() and not es_duelo and not es_equipos:
		var r := UIKit.label("TU RECOMPENSA: +%d" % int(mi_fila.get("rewards", 0)), 26, UIKit.COL_EMBER, true)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.name = "Recompensa"
		caja.add_child(r)

	boton_salir = UIKit.menu_button("VOLVER AL LOBBY", "", 30)
	boton_salir.custom_minimum_size = Vector2(0, 64)
	boton_salir.name = "BotonSalir"
	boton_salir.pressed.connect(func(): salir_pulsado.emit())
	caja.add_child(boton_salir)
	boton_salir.grab_focus()


func _titulo_final(es_duelo: bool, es_equipos: bool, gano: bool, res: Dictionary, yo: String) -> String:
	if es_equipos:
		if str(res.get("winner_team", "")).is_empty():
			return "FIN DE LA PARTIDA"
		return "VICTORIA" if gano else "DERROTA"
	return _titulo(es_duelo, gano, res, yo)


func _mi_equipo(res: Dictionary, yo: String) -> String:
	for p in res.get("players", []):
		if p is Dictionary and str(p.get("user_id", "")) == yo:
			return str(p.get("team", ""))
	return ""


## Marcador grande de equipos: ROJO 212  -  197 AZUL, con el ganador resaltado.
func _marcador_equipos(res: Dictionary) -> Control:
	var pts = res.get("team_points", {})
	var rojo := int(pts.get("rojo", 0)) if pts is Dictionary else 0
	var azul := int(pts.get("azul", 0)) if pts is Dictionary else 0
	var gan := str(res.get("winner_team", ""))
	var fila := HBoxContainer.new()
	fila.name = "MarcadorEquipos"
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 40)
	var l1 := UIKit.label("ROJO  %d" % rojo, 54, Color(0.92, 0.2, 0.15) if gan != "azul" else Color(0.45, 0.2, 0.18), true)
	var l2 := UIKit.label("%d  AZUL" % azul, 54, Color(0.3, 0.6, 1.0) if gan != "rojo" else Color(0.2, 0.3, 0.45), true)
	l1.name = "PuntosRojo"
	l2.name = "PuntosAzul"
	fila.add_child(l1)
	fila.add_child(l2)
	return fila


func _titulo(es_duelo: bool, gano: bool, res: Dictionary, yo: String) -> String:
	if es_duelo:
		var ganador := str(res.get("winner", ""))
		if ganador.is_empty():
			return "FIN DEL DUELO"
		return "VICTORIA" if (ganador == yo and not yo.is_empty()) else "DERROTA"
	return "VICTORIA" if gano else "DERROTA"


func _subtitulo(es_duelo: bool, modo: String, razon: String, res: Dictionary) -> String:
	var nombre: String = NOMBRES_MODO.get(modo, modo.to_upper())
	var detalle: String = str(res.get("winner_text", ""))
	if detalle.is_empty():
		detalle = str(MOTIVOS.get(razon, MOTIVOS["closed"]))
	return "%s  //  %s" % [nombre, detalle] if not detalle.is_empty() else nombre


## Jugadores humanos, ordenados por bajas (los bots no cuentan en el marcador).
func _humanos(res: Dictionary) -> Array:
	var lista: Array = []
	for p in res.get("players", []):
		if p is Dictionary and p.get("bot", false) != true:
			lista.append(p)
	lista.sort_custom(func(a, b): return int(a.get("kills", 0)) > int(b.get("kills", 0)))
	return lista


func _mi_fila(res: Dictionary, yo: String) -> Dictionary:
	for p in _humanos(res):
		if str(p.get("user_id", "")) == yo:
			return p
	return {}


func _tabla(res: Dictionary, yo: String, es_duelo: bool) -> Control:
	var grid := GridContainer.new()
	grid.name = "Marcador"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for cab in ["JUGADOR", "BAJAS", "DANO", "ESTADO" if not (es_duelo or str(res.get("mode", "")) in MODOS_EQUIPOS) else "RESULTADO"]:
		var c := UIKit.label(cab, 18, UIKit.COL_DIM)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cab == "JUGADOR" else 0
		grid.add_child(c)
	var ganador := str(res.get("winner", ""))
	for p in _humanos(res):
		var es_yo := str(p.get("user_id", "")) == yo and not yo.is_empty()
		var col := UIKit.COL_EMBER if es_yo else UIKit.COL_BONE
		var eqp := str(p.get("team", ""))
		if not eqp.is_empty():
			col = (Color(0.92, 0.2, 0.15) if eqp == "rojo" else Color(0.3, 0.6, 1.0)) if not es_yo else UIKit.COL_EMBER
		var nombre := str(p.get("username", "?")) + ("  (TU)" if es_yo else "")
		var nl := UIKit.label(nombre, 24, col)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(nl)
		grid.add_child(UIKit.label(str(int(p.get("kills", 0))), 24, col))
		grid.add_child(UIKit.label(str(int(p.get("damage_dealt", 0))), 24, col))
		var estado := ""
		if es_duelo:
			estado = "GANADOR" if str(p.get("user_id", "")) == ganador else ""
		elif str(res.get("winner_team", "")) != "":
			estado = "GANADOR" if eqp == str(res.get("winner_team", "")) else ""
		else:
			estado = "EN PIE" if p.get("alive", false) == true else "CAIDO"
		grid.add_child(UIKit.label(estado, 22, col))
	return grid
