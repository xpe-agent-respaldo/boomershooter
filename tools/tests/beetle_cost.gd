extends Node3D
func _ready() -> void:
	var suelo := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(200,1,200); cs.shape = bx; suelo.add_child(cs); suelo.position.y = -0.5; add_child(suelo)
	var ps: PackedScene = load("res://Scenes/Enemies/Beetle/Beetle.tscn")
	var n: int = int(OS.get_environment("N")) if OS.get_environment("N") != "" else 20
	for i in n:
		var b: Node3D = ps.instantiate(); add_child(b); b.position = Vector3(randf_range(-30,30), 1, randf_range(-30,30))
	for _f in 20: await get_tree().physics_frame
	var t: Array = []
	for _f in 120:
		var a := Time.get_ticks_usec(); await get_tree().physics_frame; t.append(Time.get_ticks_usec() - a)
	var tot := 0
	for v in t: tot += v
	print("escarabajos=", n, " frame fisica medio=", snappedf(tot / 120000.0, 0.01), " ms | cuerpos activos=", Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), " | pares=", Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	get_tree().quit()
