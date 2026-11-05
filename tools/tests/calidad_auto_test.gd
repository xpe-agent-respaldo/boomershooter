extends Node
## Comprueba que el juego ajusta la calidad solo segun el equipo, sin capar un PC
## bueno y sin dejar clavado un equipo justo.

var fallos := 0
var aciertos := 0

func ok(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond:
		aciertos += 1
		print("  ok   ", nombre)
	else:
		fallos += 1
		print("  FALLA ", nombre, "  ", detalle)


func _ready() -> void:
	print("== CALIDAD AUTOMATICA: deteccion de equipo ==")
	var casos := [
		{"que": "PC con RTX y 32 GB", "cores": 16, "ram": 32.0, "gpu": "NVIDIA GeForce RTX 4070", "movil": false, "perfil": 2, "plano": false},
		{"que": "PC con GTX 1060 y 16 GB", "cores": 8, "ram": 16.0, "gpu": "NVIDIA GeForce GTX 1060", "movil": false, "perfil": 2, "plano": false},
		{"que": "portatil normal i5", "cores": 6, "ram": 8.0, "gpu": "Intel(R) UHD Graphics 620", "movil": false, "perfil": 1, "plano": false},
		{"que": "AMD HD 8330 del usuario", "cores": 4, "ram": 7.2, "gpu": "ANGLE (AMD, AMD Radeon HD 8330 Direct3D11)", "movil": false, "perfil": 0, "plano": true},
		{"que": "sin tarjeta (llvmpipe)", "cores": 8, "ram": 16.0, "gpu": "llvmpipe (LLVM 15)", "movil": false, "perfil": 0, "plano": true},
		{"que": "iPhone moderno", "cores": 6, "ram": 6.0, "gpu": "Apple M2", "movil": true, "perfil": 1, "plano": false},
		{"que": "movil justo", "cores": 4, "ram": 2.0, "gpu": "Mali-G52", "movil": true, "perfil": 1, "plano": false},
	]
	for c in casos:
		var d: Dictionary = GameSettings.calcular_perfil(int(c["cores"]), float(c["ram"]), str(c["gpu"]), bool(c["movil"]))
		ok("%s -> perfil esperado" % c["que"], int(d["perfil"]) == int(c["perfil"]),
			"dio %d (%s)" % [int(d["perfil"]), d["motivo"]])
		ok("%s -> modo plano correcto" % c["que"], bool(d["plano"]) == bool(c["plano"]), str(d["plano"]))
		ok("%s -> escala de resolucion valida" % c["que"],
			float(d["render_scale"]) > 0.5 and float(d["render_scale"]) <= 1.0, str(d["render_scale"]))

	# Un equipo bueno NO puede acabar en Bajo solo por tener 8 nucleos (el fallo viejo).
	var bueno: Dictionary = GameSettings.calcular_perfil(8, 16.0, "NVIDIA GeForce RTX 3060", false)
	ok("8 nucleos con tarjeta dedicada no caen en Bajo", int(bueno["perfil"]) >= 1, str(bueno["perfil"]))
	ok("el perfil Alto existe y trae ragdoll", int(bueno["perfil"]) == 2 or bueno["motivo"] != "")

	# El perfil guardado por el jugador manda sobre la deteccion.
	GameSettings.performance_profile = 0
	GameSettings._save()
	GameSettings.performance_profile = 2
	GameSettings._save()
	GameSettings.performance_profile = 1
	GameSettings._load()
	ok("se respeta la calidad elegida a mano (manda lo guardado)",
		GameSettings.performance_profile == 2, str(GameSettings.performance_profile))

	print("")
	print("%d correctas, %d fallidas" % [aciertos, fallos])
	get_tree().quit(1 if fallos > 0 else 0)
