extends Node
class_name DayCycleDriver
## Moves the sun. Reads `Weather.day_phase()` and writes the scene's
## DirectionalLight3D — direction, colour, energy — every frame.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## The island had a fixed sun, so it was permanently early afternoon. That is
## not a lighting problem, it is a simulation one: Phase 2 is about villagers
## having a day — waking, working, going home, burning firewood against the
## cold — and none of that reads if the light never changes. The clock was
## already there (`Weather` has run a diurnal temperature curve since it was
## written); it was simply never connected to anything the player can see.
##
## ---------------------------------------------------------------------------
## THE BASIS TRAP — READ BEFORE EDITING
## ---------------------------------------------------------------------------
## A DirectionalLight3D shines along its own local **-Z**. Every `.tscn` in
## this project once shared a hand-authored sun basis whose -Z pointed UPWARD
## (Y = +0.52), so the entire island was lit from underneath and nobody could
## work out why it looked wrong. See docs/ROADMAP.md §3.
##
## This file does not hand-author a basis. It computes the direction the light
## TRAVELS (down from the sun toward the ground) and hands it to
## `Basis.looking_at()`, which is the engine's own way of aiming -Z. If you
## change this, verify the same way the original bug was found: check the sign
## of `light.global_transform.basis.z.y` — the sun's -Z must point DOWN while
## the sun is up, i.e. `basis.z.y` positive.
##
## ---------------------------------------------------------------------------
## NIGHT IS NOT BLACK
## ---------------------------------------------------------------------------
## This is a god game played from the air. A physically honest night would
## mean staring at an unreadable black shape for half of every ten-minute
## cycle, so night is lit by a cold, dim key from a fixed high angle — a moon
## in all but name. It reads as night without costing the player the ability
## to see their own island.

## Path to the DirectionalLight3D. Left empty, the first one found under the
## scene root is used, so a scene needs no wiring.
@export var sun_path: NodePath

@export_group("Day")
## Peak sun elevation, as a fraction of straight up. 1.0 would put the sun
## directly overhead at noon, which flattens all terrain relief into nothing —
## the shadows that make the island readable come from a lower angle.
@export_range(0.2, 1.0) var max_elevation: float = 0.72
@export var day_energy: float = 1.15
@export var day_color: Color = Color(1.0, 0.96, 0.89)
## Colour and energy at the horizon, blended in as the sun drops. Sunrise and
## sunset are the same colour here on purpose: the difference between morning
## and evening light is a refinement, and the island has bigger problems.
@export var horizon_color: Color = Color(1.0, 0.72, 0.45)

@export_group("Night")
@export var night_energy: float = 0.24
@export var night_color: Color = Color(0.62, 0.72, 1.0)
## How high the moon sits. Fixed — it does not track the sun's opposite,
## because a moon that sets as the sun rises would leave a genuinely black gap.
@export_range(0.2, 1.0) var moon_elevation: float = 0.55

var _sun: DirectionalLight3D = null

func _ready() -> void:
	_sun = _resolve_sun()
	if _sun == null:
		push_warning("DayCycleDriver: no DirectionalLight3D found; the sun will not move.")
		set_process(false)

func _process(_delta: float) -> void:
	if _sun == null:
		return
	var phase := Weather.day_phase()

	# Elevation: 0 at sunrise, 1 at noon, 0 at sunset, negative overnight.
	var elevation := sin(phase * TAU)
	# Azimuth sweeps a full circle over the day, so shadows rotate instead of
	# just growing and shrinking in place.
	var azimuth := phase * TAU

	var toward_sun: Vector3
	var energy: float
	var color: Color

	if elevation > 0.0:
		var angle := elevation * (PI * 0.5) * max_elevation
		toward_sun = Vector3(cos(azimuth) * cos(angle), sin(angle), sin(azimuth) * cos(angle))
		# Both colour and energy follow the same horizon blend, so low sun is
		# warm AND weak together — splitting them reads as a colour filter
		# rather than as a time of day.
		var high := clampf(elevation * 1.6, 0.0, 1.0)
		color = horizon_color.lerp(day_color, high)
		energy = lerpf(night_energy, day_energy, high)
	else:
		var angle := moon_elevation * (PI * 0.5)
		# The moon crosses the sky too, just on the other half of the circle.
		toward_sun = Vector3(cos(azimuth) * cos(angle), sin(angle), sin(azimuth) * cos(angle))
		color = night_color
		energy = night_energy

	# -Z is the direction light travels, so it is the direction AWAY from the
	# sun. See the basis note at the top of this file before touching this.
	_sun.global_transform.basis = Basis.looking_at(-toward_sun.normalized(), Vector3.UP)
	_sun.light_color = color
	_sun.light_energy = energy

func _resolve_sun() -> DirectionalLight3D:
	if not sun_path.is_empty():
		return get_node_or_null(sun_path) as DirectionalLight3D
	return _search(get_tree().current_scene if get_tree().current_scene != null else get_parent())

func _search(n: Node) -> DirectionalLight3D:
	if n == null:
		return null
	if n is DirectionalLight3D:
		return n
	for child in n.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null
