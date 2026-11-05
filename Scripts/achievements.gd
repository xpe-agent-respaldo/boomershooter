extends Node
## Logros con premio en monedas. Se guardan en disco y cada uno paga una sola vez.

signal unlocked(id: String, nombre: String, premio: int)

const SAVE := "user://achievements.cfg"

const LISTA := [
	{"id": "primera_sangre", "nombre": "PRIMERA SANGRE", "desc": "Mata tu primer monstruo", "meta": 1, "premio": 50, "tipo": "kills"},
	{"id": "carnicero", "nombre": "CARNICERO", "desc": "250 monstruos eliminados", "meta": 250, "premio": 200, "tipo": "kills"},
	{"id": "exterminador", "nombre": "EXTERMINADOR", "desc": "1000 monstruos eliminados", "meta": 1000, "premio": 600, "tipo": "kills"},
	{"id": "oleada_5", "nombre": "AGUANTE", "desc": "Llega a la oleada 5", "meta": 5, "premio": 150, "tipo": "oleada"},
	{"id": "oleada_10", "nombre": "VETERANO", "desc": "Llega a la oleada 10", "meta": 10, "premio": 400, "tipo": "oleada"},
	{"id": "oleada_20", "nombre": "INQUEBRANTABLE", "desc": "Llega a la oleada 20", "meta": 20, "premio": 900, "tipo": "oleada"},
	{"id": "primera_partida", "nombre": "BIENVENIDO", "desc": "Termina tu primera partida", "meta": 1, "premio": 50, "tipo": "partidas"},
	{"id": "diez_partidas", "nombre": "ADICTO", "desc": "Juega 10 partidas", "meta": 10, "premio": 300, "tipo": "partidas"},
	{"id": "comprador", "nombre": "COLECCIONISTA", "desc": "Compra tu primera skin", "meta": 1, "premio": 100, "tipo": "compras"},
]

var progreso: Dictionary = {}
var desbloqueados: Dictionary = {}


func _ready() -> void:
	load_data()


func _de(tipo: String) -> int:
	return int(progreso.get(tipo, 0))


func suma(tipo: String, cantidad: int = 1) -> void:
	progreso[tipo] = _de(tipo) + cantidad
	_comprobar()
	save_data()


func marca(tipo: String, valor: int) -> void:
	if valor > _de(tipo):
		progreso[tipo] = valor
		_comprobar()
		save_data()


func _comprobar() -> void:
	for a in LISTA:
		var id: String = a["id"]
		if desbloqueados.get(id, false):
			continue
		if _de(str(a["tipo"])) >= int(a["meta"]):
			desbloqueados[id] = true
			Shop.add_coins(int(a["premio"]))
			unlocked.emit(id, str(a["nombre"]), int(a["premio"]))
	save_data()


func esta(id: String) -> bool:
	return desbloqueados.get(id, false)


func avance(a: Dictionary) -> float:
	var v := float(_de(str(a["tipo"])))
	return clampf(v / float(a["meta"]), 0.0, 1.0)


func texto_avance(a: Dictionary) -> String:
	return "%d / %d" % [mini(_de(str(a["tipo"])), int(a["meta"])), int(a["meta"])]


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("logros", "progreso", progreso)
	cfg.set_value("logros", "desbloqueados", desbloqueados)
	cfg.save(SAVE)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) != OK:
		return
	var p = cfg.get_value("logros", "progreso", {})
	var d = cfg.get_value("logros", "desbloqueados", {})
	progreso = p if p is Dictionary else {}
	desbloqueados = d if d is Dictionary else {}
