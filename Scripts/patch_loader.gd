extends Node
## Primer autoload. Si hay un parche de contenido descargado y valido, lo monta
## y recarga la escena principal para que TODO (scripts, escenas, sonidos) salga
## ya parcheado. Asi una actualizacion solo descarga el contenido (.pck) y no el
## motor (.exe).

const PATCH_PATH := "user://patch/content.pck"
const PATCH_INFO := "user://patch/content.json"
const SENTINEL := "user://patch/.mounted_once"

static var mounted_version: String = ""


func _enter_tree() -> void:
	if OS.has_feature("editor") or not FileAccess.file_exists(PATCH_PATH):
		return
	var info = JSON.parse_string(FileAccess.get_file_as_string(PATCH_INFO)) if FileAccess.file_exists(PATCH_INFO) else null
	if not info is Dictionary:
		return
	# Un parche para otro motor no se monta: el .exe nuevo se descargo aparte.
	var engine_now := str(ProjectSettings.get_setting("application/config/engine_revision", "1"))
	if str(info.get("engine_revision", engine_now)) != engine_now:
		return
	# Un parche MAS VIEJO que el propio exe jamas se monta: pisaria los scripts nuevos con los
	# viejos y el juego se creeria desactualizado (bucle de "hay actualizacion"). Se borra.
	var version_exe := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if _es_mayor(version_exe, str(info.get("version", "0.0.0"))):
		print("[parche] %s es mas viejo que el exe %s: descartado" % [info.get("version", "?"), version_exe])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_INFO))
		return
	# Comprobacion de integridad en cada arranque: un parche corrupto jamas se monta.
	var expected := str(info.get("sha256", "")).to_lower()
	if expected != "" and FileAccess.get_sha256(PATCH_PATH).to_lower() != expected:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_PATH))
		return
	if ProjectSettings.load_resource_pack(PATCH_PATH, true):
		mounted_version = str(info.get("version", ""))
		print("[parche] contenido %s montado" % mounted_version)


## true si a es estrictamente mayor que b (formato x.y.z).
static func _es_mayor(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in 3:
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false
