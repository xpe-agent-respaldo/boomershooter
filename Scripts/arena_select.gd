extends Control

@onready var map_option: OptionButton = %MapOption
@onready var preview: TextureRect = %Preview
@onready var briefing: Label = %Briefing

const LEVELS := [
	"res://Levels/RecyclingPlant.tscn",
	"res://Levels/StormVillage.tscn",
	"res://Levels/SpaceArena.tscn"
]
# Orden = LEVELS. La planta usa una captura generada del propio mapa; la aldea y la
# luna usan las referencias: aldea de tejados rojos y picos oscuros con cielo violeta.
const PREVIEWS := [
	"res://Assets/Maps/Previews/recycling_plant.png",
	"res://Assets/Maps/References/village_scenery_idea.png",
	"res://Assets/Maps/References/2_fog_dwell_peaks.png"
]
const BRIEFINGS := [
	"Patio expuesto, pasarela de dos accesos, compactadoras y tuneles de mantenimiento. Aprende a rotar, no a quedarte quieto.",
	"Casas, patios traseros, escondites y rutas elevadas bajo una tormenta. La visibilidad es poder, pero cada ventana tiene dos angulos.",
	"Un puesto abandonado sobre roca lunar. Los corredores estrechos favorecen la escopeta; el exterior abierto exige precision."
]


func _ready() -> void:
	map_option.item_selected.connect(_select_map)
	_select_map(map_option.selected)


func _select_map(index: int) -> void:
	var safe_index := clampi(index, 0, LEVELS.size() - 1)
	if preview:
		preview.texture = LobbyAudio.load_texture(PREVIEWS[safe_index])
	if briefing:
		briefing.text = BRIEFINGS[safe_index]


func _on_play_pressed() -> void:
	LobbyAudio.change_scene(get_tree(), LEVELS[clampi(map_option.selected if map_option else 0, 0, LEVELS.size() - 1)])


func _on_back_pressed() -> void:
	LobbyAudio.change_scene(get_tree(), "res://Levels/MainMenu.tscn")
