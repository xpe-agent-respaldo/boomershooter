class_name WeaponManager

extends Node3D

signal weapon_equipped(index: int)

var weapons: Array[Node3D] = []
var current_index: int = 0

@onready var player: Player = get_tree().get_first_node_in_group("player")


# Collect child weapon scenes and equip the first one once the player is ready
func _ready() -> void:
	add_to_group("weapon_manager")
	for child: Node in get_children():
		if child is Node3D:
			weapons.append(child)

	# El nodo Player se registra en el grupo durante su propio _ready, que corre
	# despues del _ready de sus hijos: si aun no existe hay que esperar un frame.
	if player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		push_error("WeaponManager: no se encontro el Player en el grupo 'player'.")
		return
	if not player.is_node_ready():
		await player.ready
	# No esperamos la señal player_ready: como este nodo es hijo del Player, para
	# cuando llegamos aqui la señal ya pudo emitirse y el await no resolvia nunca
	# (el arma se quedaba invisible y sin datos). Un frame basta.
	await get_tree().process_frame
	equip(0)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon1"):
		equip(0)
	elif event.is_action_pressed("weapon2"):
		equip(1)
	elif event.is_action_pressed("weapon3"):
		equip(2)
	elif event.is_action_pressed("weapon4"):
		equip(3)


# Show only the selected weapon and hand its data to the player
func equip(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return

	current_index = index
	for i: int in weapons.size():
		weapons[i].visible = i == index

	player.set_weapon(weapons[index].weapon_data)
	weapon_equipped.emit(index)
