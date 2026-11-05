extends Node
## Captura la pantalla de logros y el aviso en partida dentro de un SubViewport
## (la ventana real no se puede fotografiar cuando el motor corre sin pantalla).
## Uso: xvfb-run godot --path . tools/tests/captura_logros.tscn

const ANCHO := 1920
const ALTO := 1080

var _sv: SubViewport


func _ready() -> void:
	# Progreso de muestra: logros conseguidos, en curso y pendientes.
	Achievements.progreso = {"kills": 640, "oleada": 12, "partidas": 9, "elites": 3,
		"headshots": 27, "revives": 1, "compras": 2}
	Achievements.desbloqueados = {}
	Achievements.mapas_vistos = {"SpaceArena": true, "StormVillage": true}
	Achievements._comprobar()
	Achievements.mapa_jugado("SpaceArena")

	_sv = SubViewport.new()
	_sv.size = Vector2i(ANCHO, ALTO)
	# El proyecto escala la interfaz (1920x1080 logicos): se fija el mismo espacio
	# de coordenadas para que la captura salga 1:1 y no al doble.
	_sv.size_2d_override = Vector2i(ANCHO, ALTO)
	_sv.size_2d_override_stretch = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.disable_3d = true
	add_child(_sv)

	var escena: PackedScene = load("res://Levels/Achievements.tscn")
	var pantalla: Control = escena.instantiate()
	_sv.add_child(pantalla)
	await get_tree().process_frame
	# El motor hereda el escalado del proyecto y deja el Control al doble: se
	# fuerza el tamano logico antes de fotografiar.
	pantalla.size = Vector2(ANCHO, ALTO)
	await get_tree().process_frame

	# El aviso vive en un CanvasLayer del autoload (fuera del SubViewport): se crea
	# una copia dentro para poder fotografiar como queda dentro de la partida.
	var aviso := Node.new()
	aviso.set_script(load("res://Scripts/logro_aviso.gd"))
	aviso.name = "AvisoCaptura"
	_sv.add_child.call_deferred(aviso)

	await _esperar(1.4)
	print("sv hijos=", _sv.get_child_count(), " pantalla hijos=", pantalla.get_child_count(), " tam=", pantalla.size)
	_volcar(pantalla, 0)
	_guardar("logros.png")

	Achievements.soltar("masacre")
	await _esperar(1.0)
	_guardar("aviso_logro.png")
	print("capturas listas")
	get_tree().quit()


func _volcar(n: Node, nivel: int) -> void:
	if nivel > 2:
		return
	for h in n.get_children():
		if h is Control:
			print("  ".repeat(nivel), h.name, " rect=", (h as Control).get_global_rect(), " vis=", (h as Control).visible)
		elif h is CanvasLayer:
			print("  ".repeat(nivel), h.name, " (CanvasLayer)")
		_volcar(h, nivel + 1)


func _esperar(seg: float) -> void:
	var t := 0.0
	while t < seg:
		await get_tree().process_frame
		t += get_process_delta_time()


func _guardar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _sv.get_texture().get_image()
	var ruta := ProjectSettings.globalize_path("res://capturas")
	DirAccess.make_dir_recursive_absolute(ruta)
	var destino := ruta.path_join(nombre)
	print("captura ", destino, " -> ", img.save_png(destino))
