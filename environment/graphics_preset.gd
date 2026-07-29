extends Node
class_name GraphicsPreset
## LOW / MEDIUM / HIGH graphics presets for TITHE & TERROR.
##
## Why this exists: the design brief asks for a AAA visual ceiling, and the
## machine this game is actually being played on (a Dell Latitude 5411 —
## integrated Intel graphics, no discrete GPU) cannot render one. Rather
## than quietly picking a side, this node makes the choice explicit and
## switchable: LOW is the default and is tuned for that laptop; HIGH turns
## the whole expensive stack the earlier art-direction passes built back on,
## so the AAA path still exists for hardware that can run it.
##
## Shape follows environment/naklon_environment_driver.gd exactly — a tiny,
## non-autoload, instantiable `Node` with an idempotent `_ready()`, no
## required scene wiring, and no exported NodePaths. Instance it anywhere in
## a scene (or add the script to a bare Node); one wrapper scene is provided
## at environment/graphics_preset.tscn.
##
## Public API:
##   apply(preset)          — apply a preset by enum value. Idempotent.
##   apply_current()        — re-apply whatever `preset` currently is.
##   cycle()                — LOW -> MEDIUM -> HIGH -> LOW, applies, returns
##                            the new preset. Wire this to a runtime key.
##   current()              — the preset in effect.
##   preset_name(preset)    — "Low"/"Medium"/"High", for a debug label.
##   preset_applied(preset) — signal, emitted after every successful apply.
##
## What it deliberately does NOT do: change `rendering/renderer/rendering_method`.
## That is read once at engine start and cannot be switched at runtime —
## see docs/systems/performance_lowspec.md for which renderer this project
## ships with and why.

signal preset_applied(preset: int)

enum Preset {
	## Integrated-GPU target. No SDFGI, no volumetric fog, no SSAO/SSIL, no
	## glow, no temporal AA, half-resolution 3D with a plain bilinear
	## upscale, one shadow split at 1024 with no soft filtering, and the
	## cheap water path (no screen/depth copies).
	LOW = 0,
	## An entry-level discrete GPU. Glow and a nicer shadow cascade come
	## back; the screen-space and voxel-GI passes stay off.
	MEDIUM = 1,
	## The full stack the art-direction pass authored: SDFGI, volumetric
	## fog, SSAO/SSIL, glow, four shadow splits with soft filtering, full
	## resolution, and the high-quality water path.
	HIGH = 2,
}

const ENVIRONMENT_PATH := "res://environment/world_environment.tres"
## Group used to find OceanSurface nodes without a NodePath — matches
## OceanSurface.GROUP_NAME (world/ocean/ocean_surface.gd).
const OCEAN_GROUP := &"ocean_surface"
## Group this node joins so other packages can find the active preset node.
const GROUP_NAME := &"graphics_preset"

## Exported as a plain int with an enum hint (rather than as the `Preset`
## type) so that `apply()` can take any int — from a key handler, a config
## file, a command-line flag — without a cast dance.
@export_enum("Low", "Medium", "High") var preset: int = 0
## Apply on _ready(). Turn off if something else owns the timing.
@export var apply_on_ready: bool = true
## Also retune any DirectionalLight3D found in the tree. Directional shadow
## split count is one of the single most expensive knobs in the whole
## renderer — four parallel splits means the entire shadow-casting scene is
## re-rendered four times per frame — and it lives on the light node, not in
## project settings, so a preset that ignored it would be leaving the
## biggest shadow lever untouched. Set false if a scene wants to own its own
## light setup.
@export var manage_directional_lights: bool = true

var _applied: int = -1

func _ready() -> void:
	add_to_group(GROUP_NAME)
	if apply_on_ready:
		# Deferred so that nodes built in their own _ready() (the ocean
		# builds its mesh and material there) already exist when we go
		# looking for them by group.
		apply_current.call_deferred()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func apply_current() -> void:
	apply(preset)

## Idempotent: re-applying the preset already in effect still re-writes the
## same values, which is harmless (they are all plain property sets) and
## makes this safe to call from a menu, a key handler, or _ready() twice.
func apply(p: int) -> void:
	preset = clampi(p, int(Preset.LOW), int(Preset.HIGH))
	_apply_environment(preset)
	_apply_viewport(preset)
	_apply_shadows(preset)
	_apply_directional_lights(preset)
	_apply_water(preset)
	_applied = int(preset)
	preset_applied.emit(int(preset))

func cycle() -> int:
	apply((int(preset) + 1) % 3)
	return int(preset)

func current() -> int:
	return int(preset)

static func preset_name(p: int) -> String:
	match p:
		int(Preset.LOW):
			return "Low"
		int(Preset.MEDIUM):
			return "Medium"
		int(Preset.HIGH):
			return "High"
	return "Unknown"

# ---------------------------------------------------------------------------
# Environment resource
# ---------------------------------------------------------------------------

## Same trick the other two environment drivers use: ResourceLoader caches
## by path, so load() here returns the very same live Environment instance
## the WorldEnvironment node in the scene is already pointing at. Mutating
## it in place is visible immediately with no scene wiring.
func _apply_environment(p: int) -> void:
	var env: Environment = load(ENVIRONMENT_PATH) as Environment
	if env == null:
		return

	# Every one of SDFGI / volumetric fog / SSAO / SSIL / SSR is refused
	# outright by the engine on the Mobile renderer, with a warning per
	# property per apply ("SDFGI can only be enabled when using the Forward+
	# rendering backend" — verified by actually running this, see
	# docs/systems/performance_lowspec.md). Asking for them there would
	# produce five warnings every time a preset is applied and change
	# nothing, so HIGH only reaches for them on Forward+.
	var high: bool = p == int(Preset.HIGH) and _rendering_method() == "forward_plus"
	var medium_or_better: bool = p >= int(Preset.MEDIUM)

	# The two techniques integrated GPUs are worst at: SDFGI is real-time
	# 3D voxel cone tracing, volumetric fog is a raymarched froxel grid.
	# Both are HIGH-only, full stop — reducing their quality tiers was
	# already tried on this hardware and did nothing measurable
	# (docs/systems/performance_notes.md, round two).
	env.sdfgi_enabled = high
	env.volumetric_fog_enabled = high
	env.ssao_enabled = high
	env.ssil_enabled = high
	env.ssr_enabled = high

	# Glow is a mip-chain of blurs over the whole 3D buffer every frame.
	# Cheap on a discrete card, not cheap on shared memory bandwidth.
	env.glow_enabled = medium_or_better

	# Flat depth-based fog is a per-fragment lerp, not a raymarch. It stays
	# on at every preset — it is most of what makes the sea read as deep.
	env.fog_enabled = true

	# Colour grading is part of the tonemap pass that runs regardless, so
	# leaving it enabled costs a handful of ALU ops, not a pass.
	env.adjustment_enabled = true

	_apply_sky(env, p)

## The sky's radiance cubemap is what lights every surface here
## (ambient_light_source = 2) and what the ocean reflects
## (reflected_light_source = 2). Re-filtering it in REALTIME mode every
## frame is a genuine per-frame GPU cost for a sky that only changes when
## Naklon or the weather moves. INCREMENTAL spreads each refresh over
## several frames instead, which is exactly right for a slow mood-driven
## sky, and a 128px cubemap is plenty for a smooth procedural gradient.
func _apply_sky(env: Environment, p: int) -> void:
	var sky: Sky = env.sky
	if sky == null:
		return
	if p == int(Preset.HIGH):
		# REALTIME requires a 256px radiance size in Godot 4 — set the size
		# first so the mode is never briefly invalid.
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		sky.process_mode = Sky.PROCESS_MODE_REALTIME
	else:
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.radiance_size = Sky.RADIANCE_SIZE_128

# ---------------------------------------------------------------------------
# Viewport (resolution scale, AA)
# ---------------------------------------------------------------------------

func _apply_viewport(p: int) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return

	# FSR1 and FSR2 both hard-require the Forward+ renderer (the engine
	# rejects them with an error and silently keeps bilinear otherwise), and
	# FSR2 in particular is a multi-pass temporal upscaler that Godot's own
	# project-setting hint labels "Slow". On integrated graphics its cost
	# can rival the scene it is upscaling, so it is HIGH-only even on
	# Forward+ — and never used at all on the Mobile renderer.
	var forward_plus: bool = _rendering_method() == "forward_plus"

	match p:
		int(Preset.HIGH):
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if forward_plus else Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = false # FSR2 supersedes it; the engine would disable it anyway
			vp.use_debanding = true
			vp.mesh_lod_threshold = 1.0
		int(Preset.MEDIUM):
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			vp.use_debanding = false
			vp.mesh_lod_threshold = 2.0
		_:
			# LOW. Half-resolution 3D with a plain bilinear upscale: one
			# stretched blit, versus FSR2's seven-ish compute passes plus
			# motion vectors plus a history buffer. FXAA is kept because at
			# half resolution the edges need *something* and FXAA is a
			# single cheap full-screen pass.
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.5
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_taa = false
			vp.use_debanding = false
			vp.mesh_lod_threshold = 4.0

## Which renderer is in use.
##
## Godot 4.3 does NOT expose `get_current_rendering_method()` to GDScript
## (checked: it is a C++-side `OS` method with no script binding in 4.3, and
## calling it directly is a parse error), so in practice this always falls
## back to the project setting. The `has_method` probe is kept because 4.4+
## does bind it, and the bound version is strictly better: it reflects a
## `--rendering-method` command-line override and an engine-side fallback
## (e.g. a driver that cannot do Forward+ at all), which the project setting
## does not. Both are read through string-keyed calls so neither can turn
## into a parse error on either engine version.
##
## Practical consequence on 4.3: launching with `--rendering-method
## forward_plus` while project.godot says "mobile" will make this answer
## "mobile" and the HIGH preset will skip FSR2/SDFGI it could have used.
## That is a debug-launch-only mismatch, not something a player hits.
func _rendering_method() -> String:
	if OS.has_method("get_current_rendering_method"):
		return str(OS.call("get_current_rendering_method"))
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))

# ---------------------------------------------------------------------------
# Shadows
# ---------------------------------------------------------------------------

func _apply_shadows(p: int) -> void:
	match p:
		int(Preset.HIGH):
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.gi_set_use_half_resolution(false)
		int(Preset.MEDIUM):
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.gi_set_use_half_resolution(true)
		_:
			# 16-bit depth for the shadow atlas halves the bandwidth every
			# shadow write and read costs — on a bandwidth-bound integrated
			# GPU that matters more than the 1024 -> 2048 resolution step.
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.gi_set_use_half_resolution(true)

func _apply_directional_lights(p: int) -> void:
	if not manage_directional_lights:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var mode: int = DirectionalLight3D.SHADOW_ORTHOGONAL
	if p == int(Preset.HIGH):
		mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	elif p == int(Preset.MEDIUM):
		mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for light: DirectionalLight3D in _find_directional_lights(tree.current_scene):
		light.directional_shadow_mode = mode

func _find_directional_lights(root: Node) -> Array[DirectionalLight3D]:
	var found: Array[DirectionalLight3D] = []
	if root is DirectionalLight3D:
		found.append(root as DirectionalLight3D)
	for child: Node in root.get_children():
		found.append_array(_find_directional_lights(child))
	return found

# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------

## Found by group rather than NodePath so this node never has to know the
## scene layout. Called through `has_method` so a scene using a plain
## MeshInstance3D in that group doesn't error.
func _apply_water(p: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var want_high: bool = p == int(Preset.HIGH)
	for node: Node in tree.get_nodes_in_group(OCEAN_GROUP):
		if node.has_method("set_water_quality_high"):
			node.call("set_water_quality_high", want_high)
