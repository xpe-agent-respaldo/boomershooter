extends SceneTree
func _scan(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		if f.ends_with(".tscn"): out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons": continue
		_scan(dir.path_join(sub), out)
func _init() -> void:
	var escenas: Array = []
	_scan("res://Scenes", escenas); _scan("res://Levels", escenas); _scan("res://Player", escenas)
	var mal := 0
	for p in escenas:
		var ps = load(p)
		if ps == null or not (ps is PackedScene):
			print("FALLA carga: ", p); mal += 1; continue
		var inst = ps.instantiate()
		if inst == null:
			print("FALLA instanciar: ", p); mal += 1; continue
		inst.free()
	print("ESCENAS: %d revisadas, %d con fallo" % [escenas.size(), mal])
	quit(1 if mal > 0 else 0)
