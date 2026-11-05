class_name LobbyAudio
extends RefCounted

const LOBBY_MUSIC_DIR := "res://Assets/Sounds/Music/Lobby"
const AUDIO_EXTS := ["ogg", "mp3", "wav"]


static func play_next(player: AudioStreamPlayer, last_path: String) -> String:
	if player == null:
		return last_path
	var tracks := collect_tracks(LOBBY_MUSIC_DIR)
	if tracks.is_empty():
		return last_path
	var choices := tracks.filter(func(path: String) -> bool: return path != last_path)
	var selected: String = choices.pick_random() if not choices.is_empty() else tracks[0]
	var stream := ResourceLoader.load(selected, "AudioStream", ResourceLoader.CACHE_MODE_REUSE) as AudioStream
	if stream == null:
		return last_path
	player.stream = stream
	player.play()
	return selected


static func collect_tracks(directory: String) -> Array[String]:
	var tracks: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return tracks
	for file_name in DirAccess.get_files_at(directory):
		var resolved := _resolve_audio_path(directory.path_join(file_name))
		if not resolved.is_empty() and resolved not in tracks:
			tracks.append(resolved)
	return tracks


static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D


static func change_scene(tree: SceneTree, path: String) -> void:
	if tree == null or path.is_empty():
		return
	if not ResourceLoader.exists(path):
		push_warning("No se pudo cargar la escena: %s" % path)
		return
	# Carga en segundo plano con pantalla propia: entrar a un mapa ya no congela el juego.
	var cargador := tree.root.get_node_or_null("Cargador")
	if cargador != null and cargador.has_method("cambiar"):
		cargador.cambiar(path)
		return
	tree.change_scene_to_file(path)


static func _resolve_audio_path(path: String) -> String:
	var candidate := path
	if candidate.ends_with(".import"):
		candidate = candidate.trim_suffix(".import")
	if candidate.get_extension().to_lower() not in AUDIO_EXTS:
		return ""
	if ResourceLoader.exists(candidate):
		return candidate
	return ""
