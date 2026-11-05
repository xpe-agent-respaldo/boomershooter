extends Resource
class_name WeaponData

@export var weapon_name: String = ""
@export var max_ammo: int
@export var max_mag: int
@export var fire_rate: int
@export var recoil: Vector3 = Vector3(0.05, 0.002, 0.0)
@export var pellet_count: int = 1
@export var spread_degrees: float = 0.0
@export_range(0.2, 1.0, 0.01) var ads_fov_multiplier: float = 0.7

var ammo: int
var mag: int

signal restored
signal reloaded
signal used
signal empty
signal weapon_ready
## Se emite cuando el cargador se vacia y aun queda reserva: el arma recarga sola.
signal needs_reload


func _init() -> void:
	call_deferred("ready")


func ready() -> void:
	reset()
	weapon_ready.emit()


func has_ammo() -> bool:
	return ammo > 0 || mag > 0


func should_reload() -> bool:
	return mag > 0 && ammo == 0


func use() -> void:
	if ammo > 0:
		ammo = max(0, ammo - 1)
		used.emit()
		# Al vaciar el cargador con reserva disponible, recarga automaticamente.
		# Antes habia que pulsar R a mano y el arma se quedaba muda sin avisar.
		if ammo == 0 and mag > 0:
			needs_reload.emit()
	elif should_reload() or ammo <= 0:
		empty.emit()


func reload() -> void:
	if ammo == max_ammo: return
	if mag == 0:
		# Sin reserva: al menos avisar, antes la tecla R no hacia nada.
		empty.emit()
		return
	mag = max(0, mag - (max_ammo - ammo))
	ammo = max_ammo
	reloaded.emit()


func restore() -> void:
	# ammo = max_ammo
	mag += max_ammo
	restored.emit()


func reset() -> void:
	ammo = max_ammo
	mag = max_mag * max_ammo
	restored.emit()
