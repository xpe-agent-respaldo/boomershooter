extends Node
## Tienda de skins. Las monedas se guardan en user://shop.cfg para que no se
## pierdan al cerrar el juego. Cada skin es un tinte del personaje Neko.

signal changed

const SAVE_PATH := "user://shop.cfg"
const START_COINS := 500

const SKINS := [
	{"id": "neko_base",  "name": "NEKO CLASICA",  "price": 0,    "color": Color(0.95, 0.92, 0.86), "desc": "La original. Blanca y limpia."},
	{"id": "neko_fuego", "name": "NEKO DE FUEGO", "price": 250,  "color": Color(1.0, 0.35, 0.12),  "desc": "Arde. Deja estela de brasas."},
	{"id": "neko_hielo", "name": "NEKO GLACIAR",  "price": 250,  "color": Color(0.35, 0.85, 1.0),  "desc": "Fria al tacto, letal al disparo."},
	{"id": "neko_toxica","name": "NEKO TOXICA",   "price": 400,  "color": Color(0.45, 1.0, 0.35),  "desc": "Verde radiactivo. No preguntes."},
	{"id": "neko_sombra","name": "NEKO SOMBRA",   "price": 400,  "color": Color(0.45, 0.15, 0.75),  "desc": "Se mueve raro. Casi no se ve."},
	{"id": "neko_oro",   "name": "NEKO DE ORO",   "price": 900,  "color": Color(1.0, 0.78, 0.25),  "desc": "Para los que sobran monedas."},
	{"id": "neko_sangre","name": "NEKO SANGRE",   "price": 650,  "color": Color(0.85, 0.12, 0.18),  "desc": "El favorito de la casa."},
	{"id": "neko_hueso", "name": "NEKO HUESO",    "price": 650,  "color": Color(0.88, 0.88, 0.72),  "desc": "Hueso viejo, mirada nueva."},
]

var coins: int = START_COINS
var owned: Dictionary = {"neko_base": true}
var equipped: String = "neko_base"


func _ready() -> void:
	load_data()


func skin(id: String) -> Dictionary:
	for s in SKINS:
		if s["id"] == id:
			return s
	return SKINS[0]


func equipped_skin() -> Dictionary:
	return skin(equipped)


func equipped_color() -> Color:
	return equipped_skin()["color"]


func is_owned(id: String) -> bool:
	return owned.get(id, false)


func can_buy(id: String) -> bool:
	return not is_owned(id) and coins >= int(skin(id)["price"])


func buy(id: String) -> bool:
	if is_owned(id) or coins < int(skin(id)["price"]):
		return false
	coins -= int(skin(id)["price"])
	owned[id] = true
	equip(id)
	save_data()
	changed.emit()
	Achievements.suma("compras")
	return true


func equip(id: String) -> bool:
	if not is_owned(id):
		return false
	equipped = id
	save_data()
	changed.emit()
	return true


func add_coins(amount: int) -> void:
	coins = max(0, coins + amount)
	save_data()
	changed.emit()


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shop", "coins", coins)
	cfg.set_value("shop", "equipped", equipped)
	var ids: Array = []
	for k in owned:
		if owned[k]:
			ids.append(k)
	cfg.set_value("shop", "owned", ids)
	cfg.save(SAVE_PATH)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	coins = int(cfg.get_value("shop", "coins", START_COINS))
	equipped = str(cfg.get_value("shop", "equipped", "neko_base"))
	var ids = cfg.get_value("shop", "owned", ["neko_base"])
	owned = {}
	if ids is Array:
		for id in ids:
			owned[str(id)] = true
	owned["neko_base"] = true
