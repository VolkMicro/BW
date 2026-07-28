extends Node
## Наклон (Tilt/Alignment). The single scalar that reshapes landscape,
## music, the Sanctum, villages, and the Hand. Range [-1, 1]:
## -1 = full Mercy, +1 = full Cruelty. Nothing forces the player toward
## either pole; the value only moves when the player acts.

signal naklon_changed(old_value: float, new_value: float)
signal pole_crossed(pole: int) # -1 entered mercy dominance, 1 entered cruelty dominance, 0 = back to neutral band

const NEUTRAL_BAND := 0.15
const DECAY_PER_SECOND := 0.0 # Naklon does not passively drift; only actions move it.

var value: float = 0.0:
	set(v):
		var old := value
		value = clampf(v, -1.0, 1.0)
		if not is_equal_approx(old, value):
			naklon_changed.emit(old, value)
			_check_pole(old, value)

var _last_pole: int = 0

func _check_pole(old: float, new: float) -> void:
	var new_pole := _pole_of(new)
	if new_pole != _last_pole:
		_last_pole = new_pole
		pole_crossed.emit(new_pole)

func _pole_of(v: float) -> int:
	if v > NEUTRAL_BAND:
		return 1
	if v < -NEUTRAL_BAND:
		return -1
	return 0

## Actions call this. `weight` lets big, deliberate acts (a sacrifice, a
## mass slaughter, a plague cured) move Naklon far more than small ones
## (one villager fed).
func shift(amount: float, weight: float = 1.0) -> void:
	value += amount * weight

func is_merciful() -> bool:
	return value < -NEUTRAL_BAND

func is_cruel() -> bool:
	return value > NEUTRAL_BAND

func is_neutral() -> bool:
	return not is_merciful() and not is_cruel()

## 0 at full mercy, 1 at full cruelty. Convenience for shader/material lerps.
func unit() -> float:
	return (value + 1.0) * 0.5
