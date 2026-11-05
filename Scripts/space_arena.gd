extends Node3D

const SPACE_TRACK := preload("res://Assets/Sounds/Music/Maps/Arabesque.mp3")
const SPACE_AMBIENCE := preload("res://Assets/Sounds/SFX/Ambience/spaceship.wav")


func _ready() -> void:
	var music: AudioStreamPlayer = $Music
	music.stream = SPACE_TRACK
	music.play()
	var ambience := AudioStreamPlayer.new()
	ambience.stream = SPACE_AMBIENCE
	ambience.bus = &"SFX"
	ambience.volume_db = -18.0
	ambience.finished.connect(func(): ambience.play())
	add_child(ambience)
	ambience.play()

	var world: WorldEnvironment = $Environment/WorldEnvironment
	var runtime_environment: Environment = world.environment.duplicate()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.008, 0.012, 0.05, 1.0)
	material.sky_horizon_color = Color(0.08, 0.04, 0.18, 1.0)
	material.ground_bottom_color = Color(0.003, 0.003, 0.01, 1.0)
	material.ground_horizon_color = Color(0.025, 0.02, 0.07, 1.0)
	var sky := Sky.new()
	sky.sky_material = material
	runtime_environment.sky = sky
	runtime_environment.volumetric_fog_enabled = false
	world.environment = runtime_environment

	var light: DirectionalLight3D = $Environment/DirectionalLight3D
	light.light_color = Color(0.46, 0.55, 1.0, 1.0)
