extends Node3D
## Cuenta nodos/cuerpos y tiempo de instanciar N escarabajos con el perfil indicado.
func _ready() -> void:
	GameSettings.performance_profile = int(OS.get_environment("PERFIL"))
	var n := 25
	var suelo := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(300,1,300); cs.shape = bx; suelo.add_child(cs); suelo.position.y = -0.5; add_child(suelo)
	var ps: PackedScene = load("res://Scenes/Enemies/Beetle/Beetle.tscn")
	var nodos_antes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var t0 := Time.get_ticks_usec()
	for i in n:
		var b: Node3D = ps.instantiate(); add_child(b); b.position = Vector3(randf_range(-40,40), 1, randf_range(-40,40))
	var t_inst := (Time.get_ticks_usec() - t0) / 1000.0
	for _f in 10: await get_tree().physics_frame
	var huesos := 0; var formas_activas := 0
	for b in get_children():
		for h in b.find_children("*", "PhysicalBone3D", true, false):
			huesos += 1
			for f in h.get_children():
				if f is CollisionShape3D and not f.disabled: formas_activas += 1
	var nodos_desp := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("perfil=", GameSettings.performance_profile, " enemigos=", n, " | instanciar=", snappedf(t_inst, 0.1), " ms | huesos fisicos=", huesos, " | formas activas=", formas_activas, " | nodos nuevos=", int(nodos_desp - nodos_antes))
	get_tree().quit()
