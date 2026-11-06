class_name GpuPreferida
extends RefCounted
## En portatiles con dos graficas (Intel + NVIDIA/AMD), Windows lanza los juegos con la integrada salvo
## que el .exe la pida. Godot con ANGLE (OpenGL sobre Direct3D) no la pide, y el juego iba lento.
## La forma que ofrece Windows es la preferencia por aplicacion (Configuracion > Pantalla > Graficos),
## que vive en HKCU\Software\Microsoft\DirectX\UserGpuPreferences. Se escribe una vez; no hace falta
## ser administrador. Solo vale desde el SIGUIENTE arranque, asi que se relanza el juego una vez.

const CLAVE := "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences"
const VALOR := "GpuPreference=2;"   # 2 = alto rendimiento (la dedicada)


## Argumentos de `reg add` para el ejecutable dado.
static func argumentos_registro(exe: String) -> PackedStringArray:
	return PackedStringArray(["add", CLAVE, "/v", exe, "/t", "REG_SZ", "/d", VALOR, "/f"])


## Ruta del .exe con barras de Windows, o "" si no es un ejecutable exportado.
static func ruta_exe() -> String:
	var ruta := OS.get_executable_path().replace("/", "\\")
	if not ruta.to_lower().ends_with(".exe"):
		return ""
	# El editor de Godot tambien es un .exe: no se toca su preferencia.
	if ruta.get_file().to_lower().begins_with("godot"):
		return ""
	return ruta


## Consulta la preferencia actual. Devuelve true si ya es alto rendimiento.
static func ya_aplicada(exe: String) -> bool:
	var salida: Array = []
	var code := OS.execute("reg", PackedStringArray(["query", CLAVE, "/v", exe]), salida, true, false)
	return code == 0 and salida.size() > 0 and str(salida[0]).contains(VALOR.trim_suffix(";"))


## Aplica la preferencia. Devuelve "aplicada" (hay que relanzar), "ya_estaba", "no_aplica" o "error".
static func aplicar() -> String:
	if OS.get_name() != "Windows":
		return "no_aplica"
	var exe := ruta_exe()
	if exe == "":
		return "no_aplica"
	if ya_aplicada(exe):
		return "ya_estaba"
	var salida: Array = []
	# open_console=false: sin ventana CMD (requisito del usuario).
	var code := OS.execute("reg", argumentos_registro(exe), salida, true, false)
	return "aplicada" if code == 0 else "error"
