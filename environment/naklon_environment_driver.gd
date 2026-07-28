extends Node
class_name NaklonEnvironmentDriver
## Package Q — drives the shared `environment/world_environment.tres`
## Environment resource's mood/grade from `Naklon.unit()`, the same way
## `shaders/naklon_shader_driver.gd` (package D) drives the `naklon_unit`
## global shader uniform: tiny, not an autoload (project.godot is
## foundation-owned; see docs/systems/OWNERSHIP.md), safe to instantiate
## more than once, idempotent `_ready()`.
##
## WHY THIS EXISTS: `environment/world_environment.tres` is one shared
## Environment RESOURCE (not a scene), referenced by whatever WorldEnvironment
## node(s) elsewhere in the project point at it. Resources are reference
## types in Godot, so mutating the loaded instance's properties at runtime
## is visible to every WorldEnvironment node using that same .tres path —
## nothing needs a NodePath into another package's scene tree. This script
## `load()`s the .tres directly (Godot's ResourceLoader caches by path, so
## this returns the *same* instance already wired into the running scene,
## not a second copy) and mutates it in place — extending it, never
## replacing it wholesale, per OWNERSHIP.md.
##
## HOW TO USE: add exactly one instance anywhere in a scene that has
## `environment/world_environment.tres` assigned to a WorldEnvironment node
## (see `environment/naklon_environment_driver.tscn` for a ready-made
## one-node wrapper, or add the script to a plain Node by hand). From then
## on it needs nothing else — it reacts to `Naklon.naklon_changed` on its
## own. Safe to also add `WeatherEnvironmentDriver` alongside it (see that
## script's header for how the two divide up which Environment properties
## each one writes, so they extend the same resource without fighting).
##
## MERCY/CRUELTY TARGET NUMBERS come from `docs/systems/art_direction.md`
## §4 (package D's handoff table) verbatim.
##
## DEVIATION FROM art_direction.md'S LITERAL FORMULA (documented, not
## silent): §4 states the blend as a straight two-point
## `lerp(mercy_value, cruelty_value, Naklon.unit())`. Applied literally,
## that discards whatever is actually sitting in the checked-in .tres at
## Naklon's neutral resting value (Naklon.value defaults to 0.0, i.e.
## unit() == 0.5) the instant this driver's `_ready()` runs, because the
## table's own "Baseline (current .tres, Naklon=0)" column is NOT the
## midpoint of its Mercy/Cruelty columns (e.g. sky_top_color's baseline
## (0.259, 0.443, 0.702) is nowhere near the mercy/cruelty midpoint
## (0.225, 0.325, 0.405) the literal formula would produce at unit 0.5).
## A player who has never acted (Naklon exactly neutral) would otherwise
## see the sky change the moment this script starts running, with no
## action of theirs behind it. Instead, this driver captures whatever is
## already in the .tres at `_ready()` as a live baseline anchor and does a
## PIECEWISE lerp: mercy -> baseline over unit [0, 0.5], baseline ->
## cruelty over unit [0.5, 1]. This still reaches exactly D's documented
## Mercy/Cruelty targets at the poles, and still reads as one continuous
## blend across the whole range, but keeps the neutral resting look
## exactly as already authored. Flagged here per the project's own norm of
## stating a divergence rather than leaving it for someone else to notice.
##
## PROPERTY OWNERSHIP SPLIT (see WeatherEnvironmentDriver's header for the
## other half): this script owns sky/fog COLOR and grading — everything
## that reads as "what mood is this place in" rather than "what's the
## weather doing right now": ProceduralSkyMaterial's four colors,
## `fog_light_color`, `volumetric_fog_albedo`, `tonemap_white`,
## `adjustment_brightness/contrast/saturation`, `glow_intensity`,
## `glow_hdr_threshold`, and (optional, see below) `adjustment_color_correction`.
## It also computes — but does NOT write directly to the Environment —
## Naklon-scaled BASE fog density values (`get_base_fog_density()`,
## `get_base_volumetric_fog_density()`), which `WeatherEnvironmentDriver`
## reads and multiplies by a weather factor, so the two scripts never both
## write `fog_density`/`volumetric_fog_density` and never fight.
## `sdfgi_*`, `ssao_*`, `ssil_enabled`, `tonemap_mode` are deliberately left
## untouched at every Naklon value, matching art_direction.md §4's own
## instruction that GI/AO quality shouldn't visibly degrade with mood.

## Group name other scripts (WeatherEnvironmentDriver, or any future
## consumer) can look this instance up by, via
## `get_tree().get_first_node_in_group(NaklonEnvironmentDriver.GROUP_NAME)`,
## without a hard NodePath dependency.
const GROUP_NAME := &"naklon_environment_driver"

const ENVIRONMENT_PATH := "res://environment/world_environment.tres"

## Optional continuous 1D-LUT color grade on top of the brightness/contrast/
## saturation sliders above, using package D's `NaklonLutBlend` helper and
## `materials/luts/naklon_lut_*.png`. OFF by default: it depends on
## `Environment.adjustment_use_1d_color_correction`, a property this pass
## could NOT confirm exists under that exact name via static inspection of
## the installed Godot 4.3.1 binary (stripped, no editor doc data available
## in this no-GPU sandbox — see docs/systems/performance_notes.md for the
## full account). The write is done defensively (dynamic `Object.set()`, see
## `_apply_lut()`) so a wrong name fails gracefully — at worst an engine
## warning in the console, never a GDScript parse/runtime error — but it's
## left off by default until someone with real editor access can verify
## it. Flip to `true` once that's confirmed.
@export var use_lut_grading: bool = false

## How long a mood shift takes to visually settle once Naklon changes.
## Set to 0.0 to snap instantly instead (still correct, just less gentle).
@export var ease_seconds: float = 1.5

const NaklonLutBlend = preload("res://shaders/naklon_lut_blend.gd")

# --- Mercy/Cruelty targets — docs/systems/art_direction.md §4, verbatim ---

const MERCY_SKY_TOP := Color(0.34, 0.56, 0.72)
const CRUELTY_SKY_TOP := Color(0.11, 0.09, 0.09)
const MERCY_SKY_HORIZON := Color(0.86, 0.87, 0.78)
const CRUELTY_SKY_HORIZON := Color(0.46, 0.29, 0.26)
const MERCY_GROUND_BOTTOM := Color(0.24, 0.29, 0.19)
const CRUELTY_GROUND_BOTTOM := Color(0.05, 0.04, 0.04)
const MERCY_GROUND_HORIZON := Color(0.86, 0.87, 0.78)
const CRUELTY_GROUND_HORIZON := Color(0.46, 0.29, 0.26)
const MERCY_FOG_LIGHT_COLOR := Color(0.82, 0.85, 0.74)
const CRUELTY_FOG_LIGHT_COLOR := Color(0.36, 0.22, 0.19)
const MERCY_VOLUMETRIC_FOG_ALBEDO := Color(0.95, 0.97, 0.90)
const CRUELTY_VOLUMETRIC_FOG_ALBEDO := Color(0.5, 0.4, 0.38)
const MERCY_FOG_DENSITY := 0.0005
const CRUELTY_FOG_DENSITY := 0.0020
const MERCY_VOLUMETRIC_FOG_DENSITY := 0.010
const CRUELTY_VOLUMETRIC_FOG_DENSITY := 0.030
const MERCY_TONEMAP_WHITE := 5.0
const CRUELTY_TONEMAP_WHITE := 8.5
const MERCY_ADJUSTMENT_BRIGHTNESS := 1.04
const CRUELTY_ADJUSTMENT_BRIGHTNESS := 0.92
const MERCY_ADJUSTMENT_CONTRAST := 0.97
const CRUELTY_ADJUSTMENT_CONTRAST := 1.16
const MERCY_ADJUSTMENT_SATURATION := 1.08
const CRUELTY_ADJUSTMENT_SATURATION := 0.72
const MERCY_GLOW_INTENSITY := 0.48
const CRUELTY_GLOW_INTENSITY := 0.78
const MERCY_GLOW_HDR_THRESHOLD := 1.2
const CRUELTY_GLOW_HDR_THRESHOLD := 0.85

var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _tween: Tween

# Live baseline anchors, captured once from whatever world_environment.tres
# already contains at _ready() — see the "DEVIATION" note above.
var _baseline_sky_top: Color
var _baseline_sky_horizon: Color
var _baseline_ground_bottom: Color
var _baseline_ground_horizon: Color
var _baseline_fog_light_color: Color
var _baseline_volumetric_fog_albedo: Color
var _baseline_fog_density: float
var _baseline_volumetric_fog_density: float
var _baseline_tonemap_white: float
var _baseline_adjustment_brightness: float
var _baseline_adjustment_contrast: float
var _baseline_adjustment_saturation: float
var _baseline_glow_intensity: float
var _baseline_glow_hdr_threshold: float

# Naklon-scaled fog density "base" — read by WeatherEnvironmentDriver, never
# written directly to the Environment by this script (see property split
# note above).
var _base_fog_density: float
var _base_volumetric_fog_density: float


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_environment = load(ENVIRONMENT_PATH)
	if _environment == null:
		push_warning("NaklonEnvironmentDriver: could not load %s" % ENVIRONMENT_PATH)
		return
	if _environment.sky:
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
	if _sky_material == null:
		push_warning("NaklonEnvironmentDriver: world_environment.tres has no ProceduralSkyMaterial; sky colors will not be Naklon-reactive.")
	_capture_baseline()
	_apply(Naklon.unit(), false)
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)


func _exit_tree() -> void:
	if Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.disconnect(_on_naklon_changed)
	if _tween and _tween.is_valid():
		_tween.kill()


func _capture_baseline() -> void:
	if _sky_material:
		_baseline_sky_top = _sky_material.sky_top_color
		_baseline_sky_horizon = _sky_material.sky_horizon_color
		_baseline_ground_bottom = _sky_material.ground_bottom_color
		_baseline_ground_horizon = _sky_material.ground_horizon_color
	_baseline_fog_light_color = _environment.fog_light_color
	_baseline_volumetric_fog_albedo = _environment.volumetric_fog_albedo
	_baseline_fog_density = _environment.fog_density
	_baseline_volumetric_fog_density = _environment.volumetric_fog_density
	_baseline_tonemap_white = _environment.tonemap_white
	_baseline_adjustment_brightness = _environment.adjustment_brightness
	_baseline_adjustment_contrast = _environment.adjustment_contrast
	_baseline_adjustment_saturation = _environment.adjustment_saturation
	_baseline_glow_intensity = _environment.glow_intensity
	_baseline_glow_hdr_threshold = _environment.glow_hdr_threshold


func _on_naklon_changed(_old_value: float, _new_value: float) -> void:
	_apply(Naklon.unit(), true)


## Piecewise lerp: mercy -> baseline over unit [0, 0.5], baseline -> cruelty
## over unit [0.5, 1]. See the "DEVIATION" header note for why this isn't a
## plain two-point lerp.
func _mix_f(baseline: float, mercy: float, cruelty: float, unit: float) -> float:
	if unit <= 0.5:
		return lerpf(mercy, baseline, unit * 2.0)
	return lerpf(baseline, cruelty, (unit - 0.5) * 2.0)


func _mix_c(baseline: Color, mercy: Color, cruelty: Color, unit: float) -> Color:
	if unit <= 0.5:
		return mercy.lerp(baseline, unit * 2.0)
	return baseline.lerp(cruelty, (unit - 0.5) * 2.0)


func _apply(unit: float, animate: bool) -> void:
	if _environment == null:
		return

	var target_sky_top := _mix_c(_baseline_sky_top, MERCY_SKY_TOP, CRUELTY_SKY_TOP, unit)
	var target_sky_horizon := _mix_c(_baseline_sky_horizon, MERCY_SKY_HORIZON, CRUELTY_SKY_HORIZON, unit)
	var target_ground_bottom := _mix_c(_baseline_ground_bottom, MERCY_GROUND_BOTTOM, CRUELTY_GROUND_BOTTOM, unit)
	var target_ground_horizon := _mix_c(_baseline_ground_horizon, MERCY_GROUND_HORIZON, CRUELTY_GROUND_HORIZON, unit)
	var target_fog_light_color := _mix_c(_baseline_fog_light_color, MERCY_FOG_LIGHT_COLOR, CRUELTY_FOG_LIGHT_COLOR, unit)
	var target_volumetric_fog_albedo := _mix_c(_baseline_volumetric_fog_albedo, MERCY_VOLUMETRIC_FOG_ALBEDO, CRUELTY_VOLUMETRIC_FOG_ALBEDO, unit)
	var target_tonemap_white := _mix_f(_baseline_tonemap_white, MERCY_TONEMAP_WHITE, CRUELTY_TONEMAP_WHITE, unit)
	var target_adjustment_brightness := _mix_f(_baseline_adjustment_brightness, MERCY_ADJUSTMENT_BRIGHTNESS, CRUELTY_ADJUSTMENT_BRIGHTNESS, unit)
	var target_adjustment_contrast := _mix_f(_baseline_adjustment_contrast, MERCY_ADJUSTMENT_CONTRAST, CRUELTY_ADJUSTMENT_CONTRAST, unit)
	var target_adjustment_saturation := _mix_f(_baseline_adjustment_saturation, MERCY_ADJUSTMENT_SATURATION, CRUELTY_ADJUSTMENT_SATURATION, unit)
	var target_glow_intensity := _mix_f(_baseline_glow_intensity, MERCY_GLOW_INTENSITY, CRUELTY_GLOW_INTENSITY, unit)
	var target_glow_hdr_threshold := _mix_f(_baseline_glow_hdr_threshold, MERCY_GLOW_HDR_THRESHOLD, CRUELTY_GLOW_HDR_THRESHOLD, unit)

	# Not written to the Environment here — WeatherEnvironmentDriver reads
	# these and multiplies by its own weather factor.
	_base_fog_density = _mix_f(_baseline_fog_density, MERCY_FOG_DENSITY, CRUELTY_FOG_DENSITY, unit)
	_base_volumetric_fog_density = _mix_f(_baseline_volumetric_fog_density, MERCY_VOLUMETRIC_FOG_DENSITY, CRUELTY_VOLUMETRIC_FOG_DENSITY, unit)

	if animate and ease_seconds > 0.0:
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if _sky_material:
			_tween.tween_property(_sky_material, "sky_top_color", target_sky_top, ease_seconds)
			_tween.tween_property(_sky_material, "sky_horizon_color", target_sky_horizon, ease_seconds)
			_tween.tween_property(_sky_material, "ground_bottom_color", target_ground_bottom, ease_seconds)
			_tween.tween_property(_sky_material, "ground_horizon_color", target_ground_horizon, ease_seconds)
		_tween.tween_property(_environment, "fog_light_color", target_fog_light_color, ease_seconds)
		_tween.tween_property(_environment, "volumetric_fog_albedo", target_volumetric_fog_albedo, ease_seconds)
		_tween.tween_property(_environment, "tonemap_white", target_tonemap_white, ease_seconds)
		_tween.tween_property(_environment, "adjustment_brightness", target_adjustment_brightness, ease_seconds)
		_tween.tween_property(_environment, "adjustment_contrast", target_adjustment_contrast, ease_seconds)
		_tween.tween_property(_environment, "adjustment_saturation", target_adjustment_saturation, ease_seconds)
		_tween.tween_property(_environment, "glow_intensity", target_glow_intensity, ease_seconds)
		_tween.tween_property(_environment, "glow_hdr_threshold", target_glow_hdr_threshold, ease_seconds)
	else:
		if _sky_material:
			_sky_material.sky_top_color = target_sky_top
			_sky_material.sky_horizon_color = target_sky_horizon
			_sky_material.ground_bottom_color = target_ground_bottom
			_sky_material.ground_horizon_color = target_ground_horizon
		_environment.fog_light_color = target_fog_light_color
		_environment.volumetric_fog_albedo = target_volumetric_fog_albedo
		_environment.tonemap_white = target_tonemap_white
		_environment.adjustment_brightness = target_adjustment_brightness
		_environment.adjustment_contrast = target_adjustment_contrast
		_environment.adjustment_saturation = target_adjustment_saturation
		_environment.glow_intensity = target_glow_intensity
		_environment.glow_hdr_threshold = target_glow_hdr_threshold

	if use_lut_grading:
		_apply_lut(unit)


## Snapped, not tweened — matches naklon_lut_blend.gd's own guidance
## ("safe to call every time Naklon changes... do NOT call it from
## _process()"); a per-pixel CPU cross-fade every frame would be pointless
## work between two fixed 256x4 images, so this pops straight to the new
## blended LUT rather than interpolating it alongside the properties above.
func _apply_lut(unit: float) -> void:
	var tex: ImageTexture = NaklonLutBlend.blended(unit)
	_environment.adjustment_color_correction = tex
	# `adjustment_use_1d_color_correction` could not be confirmed as a real
	# Environment property via static inspection of the installed Godot
	# 4.3.1 binary in this no-GPU sandbox (see
	# docs/systems/performance_notes.md). Set through the dynamic,
	# string-keyed setter rather than direct dot-access so an incorrect
	# name fails gracefully (an engine warning at most) instead of a script error.
	_environment.set("adjustment_use_1d_color_correction", true)


## Read by WeatherEnvironmentDriver so the two scripts don't both write
## fog_density directly. Safe to call from anywhere; returns the last
## Naklon-scaled base (not weather-multiplied).
func get_base_fog_density() -> float:
	return _base_fog_density


func get_base_volumetric_fog_density() -> float:
	return _base_volumetric_fog_density
