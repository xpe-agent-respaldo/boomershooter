extends Node
## La preferencia de GPU: argumentos correctos de reg, sin tocar nada fuera de Windows.
var fallos := 0
func _ok(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALLA ") + msg)
	if not cond: fallos += 1
func _ready() -> void:
	var a := GpuPreferida.argumentos_registro("C:\\Juegos\\BoomerShooter.exe")
	_ok(a[0] == "add" and a[1] == "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences", "escribe en la clave de preferencias de GPU del USUARIO (sin admin)")
	_ok("C:\\Juegos\\BoomerShooter.exe" in a, "la preferencia es para el .exe del juego")
	_ok(a[a.find("/d") + 1] == "GpuPreference=2;", "valor 2 = alto rendimiento (grafica dedicada)")
	_ok("/f" in a, "sobrescribe sin preguntar")
	if OS.get_name() != "Windows":
		_ok(GpuPreferida.aplicar() == "no_aplica", "fuera de Windows no hace nada")
	_ok(GpuPreferida.ruta_exe() == "", "el editor/Godot no se toca (no es el juego exportado)")
	print("GPU: ", "TODO BIEN" if fallos == 0 else "%d FALLOS" % fallos)
	get_tree().quit(0 if fallos == 0 else 1)
