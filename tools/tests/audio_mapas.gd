extends Node
## Cuenta, en cada mapa, cuantos reproductores de audio suenan de verdad y por que bus.
## Si hay mas de una musica a la vez, se oye una mezcla rara.
func _ready() -> void:
	var yo := self
	get_parent().remove_child.call_deferred(yo)
	get_tree().root.add_child.call_deferred(yo)
	_correr.call_deferred()
func _reproductores(n: Node, out: Array) -> void:
	if n is AudioStreamPlayer and n.playing: out.append(n)
	elif n is AudioStreamPlayer3D and n.playing: out.append(n)
	for h in n.get_children(): _reproductores(h, out)
func _correr() -> void:
	var arbol := get_tree()
	await arbol.process_frame
	var malos := 0
	for m in ["RecyclingPlant", "StormVillage", "SpaceArena", "SnowFields"]:
		arbol.change_scene_to_file("res://Levels/%s.tscn" % m)
		for _i in 90: await arbol.process_frame
		var ps: Array = []
		_reproductores(arbol.root, ps)
		var musicas := 0
		var detalle := []
		for p in ps:
			var bus := str(p.bus)
			var nom := str(p.stream.resource_path.get_file()) if p.stream != null else "?"
			if bus == "Music": musicas += 1
			detalle.append("%s[%s]" % [nom, bus])
		var ok := musicas <= 1
		if not ok: malos += 1
		print("AUDIO ", "OK   " if ok else "FALLA", " ", m, " | musicas simultaneas=", musicas, " | ", ", ".join(detalle))
	print("AUDIO_MAPAS: ", "TODO OK" if malos == 0 else "%d MAPAS CON MUSICA DOBLE" % malos)
	arbol.quit(1 if malos > 0 else 0)
