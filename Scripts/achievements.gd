extends Node
## Logros con premio en monedas. Se guardan en disco y cada uno paga una sola vez.
##
## Los ids antiguos (primera_sangre, carnicero, exterminador, oleada_5/10/20,
## primera_partida, diez_partidas, comprador) NO se tocan: quien ya los tenia
## conserva el progreso y no cobra dos veces.

signal unlocked(id: String, nombre: String, premio: int, rareza: String, secreto: bool)

const SAVE := "user://achievements.cfg"

## Categorias que se pueden filtrar en la pantalla.
const CATS := [
	{"id": "combate", "nombre": "COMBATE"},
	{"id": "supervivencia", "nombre": "SUPERVIVENCIA"},
	{"id": "partidas", "nombre": "PARTIDAS"},
	{"id": "tienda", "nombre": "TIENDA"},
	{"id": "especial", "nombre": "ESPECIAL"},
]

## Rarezas: color y etiqueta. Se usa en la pantalla y en el aviso de la partida.
const RAREZAS := {
	"comun": {"nombre": "COMUN", "color": Color(0.66, 0.56, 0.5, 1.0)},
	"raro": {"nombre": "RARO", "color": Color(1.0, 0.42, 0.12, 1.0)},
	"epico": {"nombre": "EPICO", "color": Color(0.85, 0.25, 0.55, 1.0)},
	"legendario": {"nombre": "LEGENDARIO", "color": Color(1.0, 0.8, 0.3, 1.0)},
}

const LISTA := [
	# ---------------- COMBATE ----------------
	{"id": "primera_sangre", "nombre": "PRIMERA SANGRE", "desc": "Mata tu primer monstruo", "meta": 1, "premio": 50, "tipo": "kills", "cat": "combate", "rareza": "comun"},
	{"id": "verdugo", "nombre": "VERDUGO", "desc": "100 monstruos eliminados", "meta": 100, "premio": 120, "tipo": "kills", "cat": "combate", "rareza": "comun"},
	{"id": "carnicero", "nombre": "CARNICERO", "desc": "250 monstruos eliminados", "meta": 250, "premio": 200, "tipo": "kills", "cat": "combate", "rareza": "comun"},
	{"id": "exterminador", "nombre": "EXTERMINADOR", "desc": "1000 monstruos eliminados", "meta": 1000, "premio": 600, "tipo": "kills", "cat": "combate", "rareza": "raro"},
	{"id": "masacre", "nombre": "MASACRE", "desc": "2500 monstruos eliminados", "meta": 2500, "premio": 1500, "tipo": "kills", "cat": "combate", "rareza": "epico"},
	{"id": "genocidio", "nombre": "GENOCIDIO", "desc": "5000 monstruos eliminados", "meta": 5000, "premio": 3000, "tipo": "kills", "cat": "combate", "rareza": "legendario"},
	{"id": "cazador_alfa", "nombre": "CAZADOR DE ALFA", "desc": "Derriba tu primer monstruo de elite", "meta": 1, "premio": 150, "tipo": "elites", "cat": "combate", "rareza": "comun"},
	{"id": "rompejefes", "nombre": "ROMPEJEFES", "desc": "25 monstruos de elite derribados", "meta": 25, "premio": 900, "tipo": "elites", "cat": "combate", "rareza": "epico"},
	{"id": "tiro_limpio", "nombre": "TIRO LIMPIO", "desc": "50 muertes de un disparo en la cabeza", "meta": 50, "premio": 350, "tipo": "headshots", "cat": "combate", "rareza": "raro"},

	# ---------------- SUPERVIVENCIA ----------------
	{"id": "oleada_5", "nombre": "AGUANTE", "desc": "Llega a la oleada 5", "meta": 5, "premio": 150, "tipo": "oleada", "cat": "supervivencia", "rareza": "comun"},
	{"id": "oleada_10", "nombre": "VETERANO", "desc": "Llega a la oleada 10", "meta": 10, "premio": 400, "tipo": "oleada", "cat": "supervivencia", "rareza": "raro"},
	{"id": "oleada_15", "nombre": "DURO DE PELAR", "desc": "Llega a la oleada 15", "meta": 15, "premio": 700, "tipo": "oleada", "cat": "supervivencia", "rareza": "raro"},
	{"id": "oleada_20", "nombre": "INQUEBRANTABLE", "desc": "Llega a la oleada 20", "meta": 20, "premio": 900, "tipo": "oleada", "cat": "supervivencia", "rareza": "epico"},
	{"id": "oleada_30", "nombre": "LEYENDA DEL MATADERO", "desc": "Llega a la oleada 30", "meta": 30, "premio": 2200, "tipo": "oleada", "cat": "supervivencia", "rareza": "legendario"},
	{"id": "buen_samaritano", "nombre": "BUEN SAMARITANO", "desc": "Revive a un companero caido", "meta": 1, "premio": 150, "tipo": "revives", "cat": "supervivencia", "rareza": "comun"},
	{"id": "angel_guardia", "nombre": "ANGEL DE LA GUARDIA", "desc": "Revive 10 veces a tus companeros", "meta": 10, "premio": 800, "tipo": "revives", "cat": "supervivencia", "rareza": "epico"},

	# ---------------- PARTIDAS ----------------
	{"id": "primera_partida", "nombre": "BIENVENIDO", "desc": "Termina tu primera partida", "meta": 1, "premio": 50, "tipo": "partidas", "cat": "partidas", "rareza": "comun"},
	{"id": "diez_partidas", "nombre": "ADICTO", "desc": "Juega 10 partidas", "meta": 10, "premio": 300, "tipo": "partidas", "cat": "partidas", "rareza": "comun"},
	{"id": "veinticinco_partidas", "nombre": "HABITUAL", "desc": "Juega 25 partidas", "meta": 25, "premio": 700, "tipo": "partidas", "cat": "partidas", "rareza": "raro"},
	{"id": "cincuenta_partidas", "nombre": "SOLDADO VIEJO", "desc": "Juega 50 partidas", "meta": 50, "premio": 1400, "tipo": "partidas", "cat": "partidas", "rareza": "epico"},
	{"id": "trotamundos", "nombre": "TROTAMUNDOS", "desc": "Juega en los 3 mapas", "meta": 3, "premio": 500, "tipo": "mapas", "cat": "partidas", "rareza": "raro"},

	# ---------------- TIENDA ----------------
	{"id": "comprador", "nombre": "COLECCIONISTA", "desc": "Compra tu primera skin", "meta": 1, "premio": 100, "tipo": "compras", "cat": "tienda", "rareza": "comun"},
	{"id": "armario", "nombre": "ARMARIO LLENO", "desc": "Compra 4 skins", "meta": 4, "premio": 450, "tipo": "compras", "cat": "tienda", "rareza": "raro"},
	{"id": "pudiente", "nombre": "PUDIENTE", "desc": "Compra todas las skins", "meta": 7, "premio": 1200, "tipo": "compras", "cat": "tienda", "rareza": "epico"},

	# ---------------- ESPECIAL (secretos) ----------------
	{"id": "curioso", "nombre": "CURIOSO", "desc": "Abre la pantalla de logros", "meta": 1, "premio": 50, "tipo": "logros_vistos", "cat": "especial", "rareza": "comun", "secreto": true},
	{"id": "madrugador", "nombre": "MADRUGADOR", "desc": "Juega entre las 3 y las 5 de la manana", "meta": 1, "premio": 300, "tipo": "directo", "cat": "especial", "rareza": "raro", "secreto": true},
	{"id": "caidas", "nombre": "APRENDIZ DE CADAVER", "desc": "Cae 25 veces y sigue volviendo", "meta": 25, "premio": 600, "tipo": "muertes", "cat": "especial", "rareza": "epico", "secreto": true},
]

var progreso: Dictionary = {}
var desbloqueados: Dictionary = {}
var mapas_vistos: Dictionary = {}


func _ready() -> void:
	load_data()


func _de(tipo: String) -> int:
	if tipo == "mapas":
		return mapas_vistos.size()
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


## Un mapa distinto cuenta una sola vez. Se llama al terminar una partida.
func mapa_jugado(nombre: String) -> void:
	var limpio := nombre.strip_edges()
	if limpio == "" or limpio.begins_with("Test") or mapas_vistos.get(limpio, false):
		return
	mapas_vistos[limpio] = true
	progreso["mapas"] = mapas_vistos.size()
	_comprobar()
	save_data()


## Desbloquea un logro concreto sin pasar por un contador (los secretos).
func soltar(id: String) -> void:
	for a in LISTA:
		if str(a["id"]) == id:
			_desbloquear(a)
			save_data()
			return


func _comprobar() -> void:
	for a in LISTA:
		if str(a["tipo"]) == "directo":
			continue
		if desbloqueados.get(str(a["id"]), false):
			continue
		if _de(str(a["tipo"])) >= int(a["meta"]):
			_desbloquear(a)
	save_data()


func _desbloquear(a: Dictionary) -> void:
	var id: String = str(a["id"])
	if desbloqueados.get(id, false):
		return
	desbloqueados[id] = true
	Shop.add_coins(int(a["premio"]))
	unlocked.emit(id, str(a["nombre"]), int(a["premio"]), str(a.get("rareza", "comun")), bool(a.get("secreto", false)))


func esta(id: String) -> bool:
	return desbloqueados.get(id, false)


func avance(a: Dictionary) -> float:
	var v := float(_de(str(a["tipo"])))
	return clampf(v / float(a["meta"]), 0.0, 1.0)


func texto_avance(a: Dictionary) -> String:
	return "%d / %d" % [mini(_de(str(a["tipo"])), int(a["meta"])), int(a["meta"])]


func color_rareza(a: Dictionary) -> Color:
	var r: Dictionary = RAREZAS.get(str(a.get("rareza", "comun")), RAREZAS["comun"])
	return r["color"]


func nombre_rareza(a: Dictionary) -> String:
	var r: Dictionary = RAREZAS.get(str(a.get("rareza", "comun")), RAREZAS["comun"])
	return str(r["nombre"])


func total() -> int:
	return LISTA.size()


func conseguidos() -> int:
	var n := 0
	for a in LISTA:
		if esta(str(a["id"])):
			n += 1
	return n


func premio_total() -> int:
	var n := 0
	for a in LISTA:
		if esta(str(a["id"])):
			n += int(a["premio"])
	return n


func de_categoria(cat: String) -> Array:
	var out := []
	for a in LISTA:
		if cat == "" or str(a.get("cat", "combate")) == cat:
			out.append(a)
	return out


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("logros", "progreso", progreso)
	cfg.set_value("logros", "desbloqueados", desbloqueados)
	cfg.set_value("logros", "mapas", mapas_vistos)
	cfg.save(SAVE)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) != OK:
		return
	var p = cfg.get_value("logros", "progreso", {})
	var d = cfg.get_value("logros", "desbloqueados", {})
	var m = cfg.get_value("logros", "mapas", {})
	progreso = p if p is Dictionary else {}
	desbloqueados = d if d is Dictionary else {}
	mapas_vistos = m if m is Dictionary else {}
	# Respaldo: si "mapas" se guardo como numero en una version anterior, se reconstruye.
	if progreso.has("mapas") and not progreso["mapas"] is int:
		progreso.erase("mapas")
