extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	var maps := {
		"recyclingplant": "res://Levels/RecyclingPlant.tscn",
		"stormvillage": "res://Levels/StormVillage.tscn",
		"spacearena": "res://Levels/SpaceArena.tscn",
	}
	for key in maps.keys():
		change_scene_to_file(maps[key])
		await create_timer(2.2).timeout
		var scene: Node = current_scene
		# ocultar HUD
		for c in scene.get_children():
			if c is CanvasLayer:
				c.visible = false
		var cam := Camera3D.new()
		cam.fov = 62.0
		scene.add_child(cam)
		cam.global_position = Vector3(26.0, 17.0, 26.0)
		cam.look_at(Vector3(0.0, 2.0, 0.0))
		cam.current = true
		await create_timer(0.7).timeout
		await process_frame
		var img: Image = root.get_texture().get_image()
		img.save_png("/app/conversations/6ae80d5d77225bda5991edda/shots/mapas/%s.png" % key)
		print("SAVED ", key)
	quit()
