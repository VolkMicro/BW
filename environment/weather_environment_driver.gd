extends Node
class_name WeatherEnvironmentDriver
## Package Q — the first real visual consumer of `Weather.current`
## (`systems/weather/weather.gd`, package P). That file's own doc
## (`docs/systems/weather.md`, "Scoped out") states plainly: "No
## visual/audio consumer of `current` yet... nothing in world/,
## environment/, or audio/ currently reads Weather.current." This script
## is that consumer for `environment/`: it modulates the shared
## `environment/world_environment.tres` Environment resource's fog density,
## sky/ambient brightness, and fog light energy from `cloud_cover` /
## `precipitation` / `storm_intensity`, so overcast and storm weather reads
## as visibly darker and foggier, live, with zero polling — same shape as
## `shaders/naklon_shader_driver.gd` and `NaklonEnvironmentDriver` (see that
## script's header for the resource-loading rationale, which this one
## shares verbatim: `load()`ing the same .tres path returns the cached,
## already-live instance, no NodePath needed).
##
## Not an autoload (project.godot is foundation-owned), safe to instantiate
## more than once, idempotent `_ready()`.
##
## HOW THE TWO DRIVERS DIVIDE THE ENVIRONMENT (so they extend the same
## resource without fighting over a property):
##
##   NaklonEnvironmentDriver owns:  sky/ground colors, fog_light_color,
##     volumetric_fog_albedo, tonemap_white, adjustment_brightness/
##     contrast/saturation, glow_intensity, glow_hdr_threshold,
##     adjustment_color_correction. This is "what mood is this place in."
##
##   WeatherEnvironmentDriver (this script) owns: fog_density,
##     volumetric_fog_density, tonemap_exposure, ambient_light_energy,
##     background_energy_multiplier, fog_light_energy. This is "what's the
##     sky doing right now," layered ON TOP of Naklon's mood.
##
## The one property both conceptually touch — fog density — is handled by
## composition, not both writing the same field: NaklonEnvironmentDriver
## computes (but does not write) a Naklon-scaled BASE fog/volumetric-fog
## density and exposes it via `get_base_fog_density()` /
## `get_base_volumetric_fog_density()`. This script looks that instance up
## by group (`NaklonEnvironmentDriver.GROUP_NAME`, no hard NodePath) and
## multiplies its base by a weather factor before writing the final value.
## If no NaklonEnvironmentDriver instance is present in the tree (e.g. a
## test scene that only wants weather, not mood grading), this script
## falls back to the plain values already in world_environment.tres so it
## still works standalone.
##
## Everything here is driven by `Weather.weather_changed`, which
## `systems/weather/weather.gd` already throttles to at most once per
## `EMIT_INTERVAL` (1.5s) in procedural mode, or once per successful poll
## (900s) in real-feed mode — this script adds no extra throttling of its
## own and does not poll `Weather.current` in `_process()`.

## Must match NaklonEnvironmentDriver.GROUP_NAME. Referenced through the
## preloaded script class (below) rather than duplicated as a literal, so
## the two files can't drift apart.
const NaklonEnvironmentDriver = preload("res://environment/naklon_environment_driver.gd")

const ENVIRONMENT_PATH := "res://environment/world_environment.tres"

## Used only if no NaklonEnvironmentDriver instance is found in the tree —
## matches the values already checked into world_environment.tres, so the
## fallback reproduces "no Naklon layer active" rather than inventing a
## different baseline.
const FALLBACK_BASE_FOG_DENSITY := 0.0008
const FALLBACK_BASE_VOLUMETRIC_FOG_DENSITY := 0.015

## How long a weather shift takes to visually settle. Deliberately shorter
## than Weather's own 1.5s emit throttle so one shift is done settling
## before the next one typically arrives, rather than perpetually chasing
## a moving target. Set to 0.0 to snap instantly instead.
@export var ease_seconds: float = 1.2

var _environment: Environment
var _tween: Tween
var _last_gloom: float = 0.0
var _last_fog_multiplier: float = 1.0

## Baselines captured from the .tres at _ready(), BEFORE this driver writes
## anything. Fog already worked this way (see _base_fog_density()); these
## four did not — they were written as hard absolutes (ambient 1.0 clear /
## 0.45 storm, exposure 1.0 / 0.5, and so on), which silently overrode
## whatever exposure the .tres was authored with the moment this node
## entered the tree. That made the checked-in ambient_light_energy dead
## weight: editing it changed nothing at runtime, which is exactly the kind
## of "the file says one thing, the game does another" trap that cost a
## long debugging session once terrain lighting was fixed and the scene
## turned out to be badly overexposed. Now gloom SCALES the authored
## values, so the .tres stays the single place exposure is tuned.
var _base_ambient_energy: float = 1.0
var _base_tonemap_exposure: float = 1.0
var _base_bg_energy: float = 1.0
var _base_fog_light_energy: float = 1.0


func _ready() -> void:
	_environment = load(ENVIRONMENT_PATH)
	if _environment == null:
		push_warning("WeatherEnvironmentDriver: could not load %s" % ENVIRONMENT_PATH)
		return
	_base_ambient_energy = _environment.ambient_light_energy
	_base_tonemap_exposure = _environment.tonemap_exposure
	_base_bg_energy = _environment.background_energy_multiplier
	_base_fog_light_energy = _environment.fog_light_energy
	# Weather is an autoload; it already emitted once from its own _ready()
	# before this node's _ready() can possibly run (autoloads initialize
	# ahead of the main scene tree), so that first emit would otherwise be
	# missed — apply the already-current state directly instead of waiting
	# for the next signal, exactly the pattern naklon_shader_driver.gd uses
	# for Naklon.
	_apply(Weather.current, false)
	if not Weather.weather_changed.is_connected(_on_weather_changed):
		Weather.weather_changed.connect(_on_weather_changed)


## Re-apply on a slow timer as well as on weather_changed.
##
## The daylight factor below moves continuously, and weather_changed only
## fires every 1.5 s on the procedural path and every FIFTEEN MINUTES on the
## real-weather feed. Driving the sky off the signal alone would leave it
## frozen at dawn brightness for a quarter of an hour.
const DAY_REAPPLY_INTERVAL := 1.0
var _reapply_accum: float = 0.0

func _process(delta: float) -> void:
	_reapply_accum += delta
	if _reapply_accum < DAY_REAPPLY_INTERVAL:
		return
	_reapply_accum = 0.0
	_apply(Weather.current, true)


func _exit_tree() -> void:
	if Weather.weather_changed.is_connected(_on_weather_changed):
		Weather.weather_changed.disconnect(_on_weather_changed)
	if _tween and _tween.is_valid():
		_tween.kill()


func _on_weather_changed(state: Dictionary) -> void:
	_apply(state, true)


func _apply(state: Dictionary, animate: bool) -> void:
	if _environment == null:
		return

	var cloud := clampf(float(state.get("cloud_cover", 0.0)), 0.0, 1.0)
	var precip := clampf(float(state.get("precipitation", 0.0)), 0.0, 1.0)
	# storm_intensity ramps continuously ahead of the hard is_storm cut (see
	# weather.gd's own header comment), which is exactly what a continuous
	# visual blend wants — no boolean branch needed on is_storm here.
	var storm := clampf(float(state.get("storm_intensity", 0.0)), 0.0, 1.0)

	# Fog thickens with cloud cover, more with rain, most with storm
	# severity. Clamped to 5x so a worst-case blend never asks the
	# volumetric fog pass to integrate an absurd density.
	_last_fog_multiplier = clampf(1.0 + cloud * 1.2 + precip * 1.3 + storm * 2.0, 1.0, 5.0)
	# 0 = clear-sky brightness, 1 = darkest storm gloom. Deliberately one
	# shared factor across exposure/ambient/background/fog-light energy
	# rather than four independently tuned curves — keeps this script
	# small, and all four read as "the same overcast dimming" rather than
	# fighting each other.
	_last_gloom = clampf(cloud * 0.55 + storm * 0.45, 0.0, 1.0)

	var base_fog := _base_fog_density()
	var base_vfog := _base_volumetric_fog_density()

	var target_fog_density := base_fog * _last_fog_multiplier
	var target_vfog_density := base_vfog * _last_fog_multiplier
	# Each is the AUTHORED baseline scaled by gloom, not a hard absolute —
	# see the _base_* declarations above for why that distinction matters.
	# DAYLIGHT, layered under the gloom. 1 in full day, 0 at night.
	#
	# environment/day_cycle_driver.gd already swings the sun, but the sky and
	# the ambient term are the Environment's, not the light's, so without this
	# night was a dim island under a bright blue midday sky.
	#
	# It lives here rather than in the day cycle driver because these four
	# properties have exactly one owner (see the _base_* declarations above),
	# and two nodes writing the same Environment field would fight — the
	# already-fixed exposure bug in this file's history was that same mistake
	# in a smaller form.
	#
	# tonemap_exposure is deliberately NOT dimmed by night. The moonlight key
	# is already weak; crushing exposure on top of it takes the island from
	# "night" to "cannot see the island", which for a game played from 300 m
	# up is the whole screen.
	var daylight := smoothstep(-0.15, 0.35, sin(Weather.day_phase() * TAU))
	var night_ambient := lerpf(0.22, 1.0, daylight)
	var night_sky := lerpf(0.10, 1.0, daylight)

	var target_exposure := _base_tonemap_exposure * lerpf(1.0, 0.5, _last_gloom)
	var target_ambient := _base_ambient_energy * lerpf(1.0, 0.45, _last_gloom) * night_ambient
	var target_bg_energy := _base_bg_energy * lerpf(1.0, 0.5, _last_gloom) * night_sky
	var target_fog_light_energy := _base_fog_light_energy * lerpf(1.0, 0.4, _last_gloom) * night_sky

	if animate and ease_seconds > 0.0:
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(_environment, "fog_density", target_fog_density, ease_seconds)
		_tween.tween_property(_environment, "volumetric_fog_density", target_vfog_density, ease_seconds)
		_tween.tween_property(_environment, "tonemap_exposure", target_exposure, ease_seconds)
		_tween.tween_property(_environment, "ambient_light_energy", target_ambient, ease_seconds)
		_tween.tween_property(_environment, "background_energy_multiplier", target_bg_energy, ease_seconds)
		_tween.tween_property(_environment, "fog_light_energy", target_fog_light_energy, ease_seconds)
	else:
		_environment.fog_density = target_fog_density
		_environment.volumetric_fog_density = target_vfog_density
		_environment.tonemap_exposure = target_exposure
		_environment.ambient_light_energy = target_ambient
		_environment.background_energy_multiplier = target_bg_energy
		_environment.fog_light_energy = target_fog_light_energy


func _base_fog_density() -> float:
	var driver := get_tree().get_first_node_in_group(NaklonEnvironmentDriver.GROUP_NAME)
	if driver and driver.has_method("get_base_fog_density"):
		return driver.get_base_fog_density()
	return FALLBACK_BASE_FOG_DENSITY


func _base_volumetric_fog_density() -> float:
	var driver := get_tree().get_first_node_in_group(NaklonEnvironmentDriver.GROUP_NAME)
	if driver and driver.has_method("get_base_volumetric_fog_density"):
		return driver.get_base_volumetric_fog_density()
	return FALLBACK_BASE_VOLUMETRIC_FOG_DENSITY


## Read-only hooks for a future diegetic consumer (e.g. package R's
## MusicDirector ducking under a storm, or an ambience layer in audio/) that
## wants "how gloomy/foggy is it right now" without re-deriving it from
## Weather.current itself. Not called by anything in this package.
func get_gloom_factor() -> float:
	return _last_gloom


func get_fog_multiplier() -> float:
	return _last_fog_multiplier
