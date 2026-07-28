extends Node
## Autoload. The single source of truth for "what island am I on, which
## villages exist, what has the player god been named." Systems read and
## write here rather than passing state through scenes, since the camera
## jumps from god-view to Sanctum-interior to duel arena without a loading
## screen and everything has to already agree on the world state.

signal village_registered(village: Village)
signal village_converted(village_id: StringName)
signal village_lost(village_id: StringName)
signal epithet_earned(epithet: String, reason: String)
signal devotion_changed(village_id: StringName, new_amount: float)

var villages: Dictionary = {} # StringName -> Village
var cultures: Dictionary = {} # StringName -> Culture
var current_island: StringName = &"ostrivka_alaas"

## The player god is never named by the designers. Mortals coin epithets as
## Naklon drifts and events land; this list IS the player's real scorecard.
var epithets: Array[String] = []

var avatar_species: StringName = &"" # &"otso", &"krukk", &"sarv" — chosen at game start
var relics_held: Array[StringName] = []
var scrolls_known: Array[StringName] = []

func _ready() -> void:
	_load_cultures()

func _load_cultures() -> void:
	for path in [
		"res://data/cultures/fenrayt.tres",
		"res://data/cultures/sankiln.tres",
		"res://data/cultures/raimborn.tres",
		"res://data/cultures/vainkeeper.tres",
	]:
		var c: Culture = load(path)
		if c:
			cultures[c.id] = c

func register_village(v: Village) -> void:
	villages[v.id] = v
	village_registered.emit(v)

func get_village(id: StringName) -> Village:
	return villages.get(id, null)

func add_devotion(village_id: StringName, amount: float) -> void:
	var v: Village = get_village(village_id)
	if v == null:
		return
	v.devotion = maxf(0.0, v.devotion + amount)
	devotion_changed.emit(village_id, v.devotion)

## Called whenever a village's faith_fraction crosses key thresholds so the
## rest of the game (missionary counts, ambient prayer sound, HUD-less
## visual glow on the village) can react without polling every frame.
func set_faith_fraction(village_id: StringName, fraction: float) -> void:
	var v: Village = get_village(village_id)
	if v == null:
		return
	var was_converted := v.is_fully_converted()
	v.faith_fraction = clampf(fraction, 0.0, 1.0)
	if v.is_fully_converted() and not was_converted:
		village_converted.emit(village_id)

func earn_epithet(text: String, reason: String) -> void:
	if text in epithets:
		return
	epithets.append(text)
	epithet_earned.emit(text, reason)
