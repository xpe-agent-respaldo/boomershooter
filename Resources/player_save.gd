class_name PlayerSave
extends Resource

const MAX_HISTORY: int = 10

@export var kills: int = 0
@export var runs: int = 0
@export var run_history: Array[Dictionary] = []


# Record a completed run at the front of the history, keeping the newest entries
func add_run(time_seconds: float, run_kills: int) -> void:
	run_history.push_front({"time": time_seconds, "kills": run_kills})
	if run_history.size() > MAX_HISTORY:
		run_history.resize(MAX_HISTORY)

static func get_save_path() -> String:
	var SAVE_PATH: String = "user://player_save.res"
	return SAVE_PATH


static func load_player_data() -> PlayerSave:
	var save_path: String = get_save_path()
	if ResourceLoader.exists(save_path):
		var loaded: PlayerSave = ResourceLoader.load(save_path)
		if loaded is PlayerSave:
			return loaded
	# Si no existe el archivo se crea uno nuevo. Antes devolvia null y cualquier
	# nivel reventaba con "Invalid access to property 'runs' on Nil".
	var fresh: PlayerSave = PlayerSave.new()
	fresh.save_player_data(fresh)
	return fresh


func save_player_data(data: PlayerSave) -> void:
	print("Save player data")
	var SAVE_PATH: String = PlayerSave.get_save_path()
	var result: Error = ResourceSaver.save(data, SAVE_PATH, ResourceSaver.FLAG_COMPRESS)
	assert(result == OK)
