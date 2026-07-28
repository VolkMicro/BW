extends Node3D
## Standalone demo bootstrap: registers one real Village (a damaged,
## partly-converted Fenrayt settlement) in GameState before the sibling
## Sanctum instance's own _ready() runs its culture-skin / hp-visual pass,
## so `godot --path . world/sanctum/sanctum_demo.tscn` shows a real,
## walkable Sanctum reacting to real Village/GameState/Naklon/Reach state —
## not a hand-tuned standalone mockup.
##
## Node _ready() order in Godot runs children before parents, so this
## script (on the scene root, the parent of the Sanctum instance) would
## normally run too late to matter for a first-frame skin — sanctum.gd
## handles that itself by listening for GameState.village_registered and
## re-applying its skin/hp visuals whenever a matching village shows up,
## which is exactly what happens here.

const DEMO_VILLAGE_ID := &"demo_fen_hollow"

func _ready() -> void:
	var v := Village.new()
	v.id = DEMO_VILLAGE_ID
	v.display_name = "Fen Hollow (demo)"
	v.culture_id = &"fenrayt"
	v.position_on_island = Vector2.ZERO
	v.population = 40
	v.children = 9
	v.devotion = 12.0
	v.faith_fraction = 0.45
	v.sanctum_built = true
	v.sanctum_hp = 62.0
	v.sanctum_hp_max = 100.0
	GameState.register_village(v)
