extends Resource
class_name Village
## Runtime state for one settlement: population, buildings, devotion, and
## the per-method conversion fatigue used by the Reach/Faith system
## (see systems/faith/reach.gd) so that repeating the same miracle on the
## same village stops working and the player has to vary their approach.

@export var id: StringName
@export var display_name: String
@export var culture_id: StringName
@export var position_on_island: Vector2
@export var population: int = 12
@export var children: int = 3
@export var devotion: float = 0.0 # spendable currency, produced by active prayer
@export var faith_fraction: float = 0.0 # 0..1, share of population that prays to the player god
@export var loyal_to_rival: bool = false # true once Louhi has taken this village
@export var sanctum_built: bool = false
@export var sanctum_hp: float = 100.0
@export var sanctum_hp_max: float = 100.0
@export var calling_stone_target: int = 0 # how many villagers the stone is currently set to summon to prayer
@export var jobs: Dictionary = {
	"fishing": 0,
	"field": 0,
	"woodcutting": 0,
	"building": 0,
	"family": 0,
	"idle": 0,
}
@export var buildings: Array[StringName] = [] # e.g. &"gathering_house", &"storehouse", &"workyard", &"wonder_*"
@export var wonders: Array[StringName] = []

## Conversion-method fatigue: method_id -> {"uses": int, "fatigue": float 0..1, "last_use_t": float}
## Fatigue rises when a method is used on this village and decays slowly
## over time even when unused (see Reach.decay_fatigue).
@export var method_fatigue: Dictionary = {}

func is_fully_converted() -> bool:
	return faith_fraction >= 0.999 and not loyal_to_rival
