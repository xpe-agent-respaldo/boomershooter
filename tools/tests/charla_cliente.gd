extends Node
func _ready():
	var chat = get_node("/root/GameChat")
	chat.receive_bot_message("[url=http://x]Malo[/url]", "Hola [b]Ana[/b], [color=red]ojo[/color].", "pandilla")
	chat.receive_bot_message("Chato", "Te vimos entrar hace rato, Ana.", "pandilla")
	var linea0: String = chat._lines[0]
	print("L0=", linea0)
	# lo unico con corchetes reales debe ser MI etiqueta de color y los escapes [lb]/[rb]
	var sin_escapes: String = linea0.replace("[lb]", "").replace("[rb]", "").replace("[color=#ff6b5b]", "").replace("[/color]", "")
	print("CORCHETES_SUELTOS=", sin_escapes.count("["), " | hay [url=", "[url" in sin_escapes, " | hay [b]=", "[b]" in sin_escapes)
	var rt := RichTextLabel.new(); rt.bbcode_enabled = true; add_child(rt); rt.text = linea0
	print("TEXTO_VISIBLE=", rt.get_parsed_text())
	print("LINEAS=", chat._lines.size(), " PANEL_VISIBLE=", chat._panel.visible)
	# la senal llega de punta a punta
	OnlineManager.bot_dijo.emit("Lata", "Uno de La Chatarra para Ana.", "pandilla")
	var net = load("res://Scripts/network_game.gd").new()
	add_child(net)
	OnlineManager.bot_dijo.emit("Fierro", "Pandilla, a formar.", "amigo")
	print("TRAS_SENAL=", chat._lines.size(), " ULTIMA=", chat._lines[-1])
	get_tree().quit()
