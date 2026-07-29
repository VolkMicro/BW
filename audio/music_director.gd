extends Node
## Autoload. MusicDirector — the adaptive audio system (package R).
##
## Two responsibilities:
##  1. A continuously-crossfaded two-layer music bed, `layers[&"prayer"]` /
##     `layers[&"infernal"]`, driven every frame by `Naklon.unit()`
##     (0.0 = full prayer/mercy, 1.0 = full infernal/cruelty) via an
##     **equal-power** crossfade over `AudioStreamPlayer.volume_db` — gains
##     follow cos/sin of `unit() * PI/2` rather than a linear `1-t`/`t` lerp,
##     so the combined perceived loudness stays constant across the whole
##     range instead of dipping in the middle the way a linear crossfade
##     would.
##  2. Two continuous ambient beds — `wind` (non-spatial) and `sea` (3D,
##     spatial) — modulated every tick by `Weather.current`
##     (systems/weather/weather.gd) so a storm forming/breaking is audible,
##     not only visible to whatever future VFX consumer reads the same
##     Dictionary (as of this pass, nothing in world/ or environment/ reads
##     it either — see docs/systems/weather.md's own "Scoped out"; this
##     package is the first live consumer).
##
##  3. **A one-shot SFX layer** for the things a player actually does —
##     the Hand grabbing and throwing, a rite being cast, thunder during a
##     storm — played through a small fixed pool of `AudioStreamPlayer3D`
##     voices (spatial, at the Hand's world position) plus one non-spatial
##     player for thunder. The emitters are found by walking the scene tree
##     for nodes that *have* the relevant signals, never by hardcoded
##     NodePath, because `audio/` may not edit `world/god_view.tscn` or the
##     packages that own the Hand / sigil caster (docs/systems/OWNERSHIP.md).
##
## HONESTY NORM — what's real vs. placeholder here (full account, including
## the exact searches performed and their results, in docs/systems/audio.md):
##
##  **Second sourcing pass (this one): all four continuous beds and all four
##  new SFX are now REAL, downloaded, CC0-licensed files**, obtained from
##  OpenGameArt.org — a source the first pass never tried. Each one's exact
##  source URL, author and licence is recorded in docs/systems/audio.md's
##  "Assets used" table for the CREDITS.md consolidation pass. The first
##  pass's dead ends (Kenney's entire Audio category = no ambient/music
##  packs; Freesound = 401 without an API key; Musopen = 403 on every
##  request) are still true and still recorded in the doc; they were simply
##  not the whole internet.
##
##  **The synthesized tones are kept as a fallback, not deleted.** If any bed's
##  .ogg is missing from the build, that single layer silently falls back to
##  its original `AudioStreamGenerator` synthesis rather than going silent or
##  crashing — `_layer_is_sourced` records which path each layer actually
##  took, and `_fill_all_generators()` early-outs entirely when (as in a
##  normal build) every bed is file-backed.
##
##  **What is NOT verified: how any of this actually SOUNDS.** This build
##  sandbox has no audio device, so every file here was chosen from its
##  title, its author's own description, its duration and its channel/rate
##  header — not by listening to it. Loudness trims
##  (`SOURCED_*_TRIM_DB`) are conservative first guesses, and the sea bed's
##  loop seam is unverified. Anyone with speakers should re-audition and
##  retune those constants; nothing here should be read as "mixed."
##
##  `res://audio/sfx/bong_001.ogg` remains the first pass's one real asset
##  (Kenney "Interface Sounds" pack, https://kenney.nl/assets/interface-sounds)
##  used as-is for the one-shot "rite bell" on `Naklon.pole_crossed`.
##  See docs/systems/audio.md "Assets used" for every CREDITS-ready row.

# --- Public state (kept from the original stub's documented contract) ------

var layers: Dictionary = {} # &"prayer" / &"infernal" -> AudioStreamPlayer

# --- Sourced audio (real CC0 files; synthesis below is the fallback) --------

## Every continuous bed's real, downloaded, CC0 file. All four came from
## OpenGameArt.org in this package's second sourcing pass; see
## docs/systems/audio.md "Assets used" for author/URL/licence per row.
## A missing file is NOT fatal — `_stream_for_layer()` falls back to that
## layer's original `AudioStreamGenerator` synthesis and warns.
const LAYER_ASSETS := {
	&"prayer": "res://audio/music/heavenly_loop.ogg",              # isaiah658, CC0
	&"infernal": "res://audio/music/dark_cavern_ambient_002.ogg",  # Paul Wortmann, CC0
	&"wind": "res://audio/music/wind_woosh_loop.ogg",              # SketchMan3, CC0
	&"sea": "res://audio/music/jasinski_beach_waves.ogg",          # jasinski (via qubodup), CC0
}

## Which layers ended up file-backed (true) vs. synthesized-fallback (false).
## Read by `_fill_all_generators()` (skip synthesis entirely when all four are
## sourced) and by `_trim_db()` (sourced files need a different trim than the
## hand-tuned synth amplitudes).
var _layer_is_sourced: Dictionary = {}

## Conservative loudness trims applied ONLY to file-backed layers. The
## synthesized amplitudes (PRAYER_AMPLITUDE etc.) were hand-tuned against each
## other; a real recording has whatever level its author mastered it at, which
## is generally much hotter. UNVERIFIED BY EAR — this sandbox has no audio
## device. Retune after an actual listen.
const SOURCED_MUSIC_TRIM_DB := -8.0
const SOURCED_WIND_TRIM_DB := -7.0
const SOURCED_SEA_TRIM_DB := -6.0

# --- Tuning: music synthesis -------------------------------------------------

const MIX_RATE := 44100.0
const GEN_BUFFER_LENGTH := 0.5 # seconds of generator ring-buffer lookahead

const MUSIC_MASTER := 0.8 # headroom so neither layer clips at full gain

const PRAYER_FREQ_ROOT := 220.0   # A3
const PRAYER_FREQ_FIFTH := 329.63 # E4 — perfect fifth above root
const PRAYER_FREQ_OCTAVE := 440.0 # A4
const PRAYER_LFO_HZ := 0.08       # slow "breathing" swell, not a static drone
const PRAYER_AMPLITUDE := 0.20

const INFERNAL_FREQ_ROOT := 55.0        # A1
const INFERNAL_FREQ_TRITONE := 77.78    # 55 * sqrt(2) — "diabolus in musica"
const INFERNAL_LFO_HZ := 0.05
const INFERNAL_GRIT := 0.05             # low-level noise mixed into the drone
const INFERNAL_AMPLITUDE := 0.24

# --- Tuning: ambience synthesis ---------------------------------------------

const WIND_MASTER := 0.5
const WIND_SPEED_REF := 8.0   # wind_speed at/above this reads as "full" wind gain
const WIND_GAIN_MIN := 0.12  # sea/wind bed is never fully silent, even dead calm
const WIND_FILTER_MIN := 0.04
const WIND_FILTER_RANGE := 0.35 # higher wind => brighter (less-filtered) noise

const SEA_MASTER := 0.55
const SEA_GAIN_BASE := 0.35
const SEA_WAVE_HZ := 0.12 # one slow surge-and-retreat cycle roughly every 8s
const SEA_FILTER_ALPHA := 0.05

const AMBIENCE_LERP_RATE := 0.6 # gain units/sec — smooths Weather's 1.5s emit cadence

## Placeholder anchor for the spatial sea layer: an arbitrary shoreline-ish
## offset from the island center, using the same Vector2(x,y) world ->
## Vector3(x,0,y) convention systems/weather/weather.gd and
## systems/faith/reach.gd already share (ISLAND_POS = Vector2.ZERO,
## SEA_RADIUS ~2600). audio/ does not own world/ocean's actual shoreline
## geometry, so this is deliberately approximate — see `set_sea_anchor()`
## and "Scoped out" in docs/systems/audio.md.
const SEA_PLACEHOLDER_POSITION := Vector3(0.0, 2.0, 120.0)

# --- Ducking (optional Voices/Louhi reaction) -------------------------------

signal ducked(active: bool) # for any future consumer that wants to know the bed just dipped

const DUCK_AMOUNT := 0.45     # music multiplier while ducked
const DUCK_HOLD_SEC := 1.1    # how long a single remark holds the duck open
const DUCK_LOUHI_HOLD_SEC := 1.8
const DUCK_RATE := 1.0 / 1.6  # gain units/sec back to 1.0

var _duck_target := 1.0
var _duck_current := 1.0
var _duck_hold_timer := 0.0
var _was_ducked := false

# --- One-shot SFX (the Hand, rites, thunder) --------------------------------

## Real CC0 one-shots, all from OpenGameArt.org — see docs/systems/audio.md
## "Assets used". A missing file just disables that one cue (warned once at
## startup); nothing here crashes or goes silent as a whole.
const SFX_ASSETS := {
	&"grab": "res://audio/sfx/sfx100v2_items_01.ogg",     # rubberduck, CC0
	&"throw": "res://audio/sfx/sfx100v2_air_01.ogg",      # rubberduck, CC0
	&"rite": "res://audio/sfx/magical_4.ogg",             # JaggedStone, CC0
	&"thunder": "res://audio/sfx/sfx100v2_thunder_01.ogg",# rubberduck, CC0
}

## Fixed, tiny voice pool for the spatial one-shots. Four is deliberate: the
## Hand is a single cursor and can physically only grab/throw one thing at a
## time, so 4 covers overlap (a throw whoosh still ringing while the next grab
## fires) with room to spare, and it caps the worst case rather than letting
## one-shots spawn unbounded players on a machine that is already GPU-starved.
const SFX_VOICES := 4

const SFX_GRAB_DB := -9.0
const SFX_THROW_DB := -6.0
const SFX_RITE_DB := -7.0
const SFX_THUNDER_DB := -4.0

## Below this release speed a "throw" is really a "set down": play the softer
## grab/handling sample instead of the air whoosh.
const THROW_MIN_SPEED := 2.5
const THROW_REF_SPEED := 14.0 # release speed that reads as a full-strength throw

## Thunder. `systems/weather/weather.gd` has no lightning/strike event of any
## kind — only a continuous `storm_intensity` 0..1 — so thunder is generated
## HERE from that intensity on a self-scheduling timer, not triggered by a real
## strike somewhere else in the sim. Stated plainly because it means thunder
## does NOT line up with any visual lightning (there isn't any yet either).
signal thunder_cracked(intensity: float) # for a future lightning-flash consumer

const THUNDER_MIN_INTENSITY := 0.25 # quieter storms get no thunder at all
const THUNDER_GAP_MIN := 7.0
const THUNDER_GAP_MAX := 26.0

var _storm_intensity := 0.0
var _thunder_timer := THUNDER_GAP_MAX

var _sfx_streams: Dictionary = {}       # StringName -> AudioStream (only successfully loaded ones)
var _sfx_voices: Array[AudioStreamPlayer3D] = []
var _sfx_next_voice := 0
var _thunder_player: AudioStreamPlayer

# --- Scene-tree emitters discovered at runtime -------------------------------
#
# audio/ owns none of these packages and may not edit world/god_view.tscn, so
# nothing here uses a hardcoded NodePath. Each emitter is found by *capability*
# (`has_signal`), which also fixes a real latent bug in the previous pass: it
# looked for Louhi at `/root/LouhiDirector`, but god_view.tscn actually
# instances her at `/root/GodView/LouhiDirector`, so that connection had never
# once fired.

var _hand: Node = null
var _sigil_caster: Node = null
var _louhi: Node = null

# --- Node/stream handles -----------------------------------------------------

var _prayer_playback: AudioStreamGeneratorPlayback
var _infernal_playback: AudioStreamGeneratorPlayback
var _wind_player: AudioStreamPlayer
var _wind_playback: AudioStreamGeneratorPlayback
var _sea_player: AudioStreamPlayer3D
var _sea_playback: AudioStreamGeneratorPlayback
var _bell_player: AudioStreamPlayer

var _dt := 1.0 / MIX_RATE

# --- Synthesis phase state ---------------------------------------------------

var _prayer_ph_root := 0.0
var _prayer_ph_fifth := 0.0
var _prayer_ph_octave := 0.0
var _prayer_ph_lfo := 0.0

var _infernal_ph_root := 0.0
var _infernal_ph_tritone := 0.0
var _infernal_ph_lfo := 0.0

var _wind_lp := 0.0
var _sea_lp := 0.0
var _sea_wave_ph := 0.0

# --- Ambience gain state (smoothed toward Weather-derived targets) ---------

var _wind_gain := WIND_GAIN_MIN
var _wind_gain_target := WIND_GAIN_MIN
var _wind_brightness := WIND_FILTER_MIN
var _wind_brightness_target := WIND_FILTER_MIN
var _sea_gain := SEA_GAIN_BASE
var _sea_gain_target := SEA_GAIN_BASE

func _ready() -> void:
	_setup_music_layers()
	_setup_ambience_layers()
	_setup_bell()
	_setup_sfx()

	Naklon.naklon_changed.connect(_on_naklon_changed)
	Naklon.pole_crossed.connect(_on_pole_crossed)
	Weather.weather_changed.connect(_on_weather_changed)
	Voices.remark.connect(_on_voices_remark)

	# Emitter discovery (Hand / SigilCaster / LouhiDirector). MusicDirector is
	# an autoload, so it is ready BEFORE the main scene is instanced — the
	# `node_added` connection is what actually catches all three. The deferred
	# one-shot sweep is belt-and-braces for the reverse order (e.g. a test
	# scene already running when this autoload comes up).
	get_tree().node_added.connect(_on_node_added)
	_scan_tree_for_emitters.call_deferred()

	# Seed real state immediately rather than waiting for the first signal —
	# Weather/Naklon/Voices are all earlier in project.godot's [autoload]
	# list than MusicDirector, so their `_ready()` has already run and
	# `Weather.current` is already a real reading by the time this runs.
	_on_weather_changed(Weather.current)
	_update_crossfade()

func _process(delta: float) -> void:
	_fill_all_generators()
	_update_duck(delta)
	_update_crossfade()
	_update_ambience_gains(delta)
	_update_thunder(delta)

# --- Setup -------------------------------------------------------------------

func _make_generator_stream() -> AudioStreamGenerator:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = GEN_BUFFER_LENGTH
	return stream

## Load a real, sourced bed as a seamlessly-looping stream, or return null if
## the file isn't in the build. `ResourceLoader.exists()` is checked first so a
## missing asset is a warning we handle, not an engine-level load error.
func _load_looping_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	# Loop flags are set here rather than baked into the .import files so the
	# same source file could be reused as a one-shot elsewhere without a second
	# import config, and so the intent is visible in code review.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream

## The one place a bed decides "real file" vs. "synthesized fallback".
## Records the answer in `_layer_is_sourced` so gain trims and the synthesis
## early-out both know which world they're in.
func _stream_for_layer(layer_name: StringName) -> AudioStream:
	var path: String = LAYER_ASSETS.get(layer_name, "")
	var sourced: AudioStream = _load_looping_stream(path) if path != "" else null
	if sourced != null:
		_layer_is_sourced[layer_name] = true
		return sourced
	_layer_is_sourced[layer_name] = false
	push_warning("MusicDirector: '%s' bed asset missing (%s) — falling back to runtime AudioStreamGenerator synthesis for that layer." % [layer_name, path])
	return _make_generator_stream()

func _setup_music_layers() -> void:
	var prayer := AudioStreamPlayer.new()
	prayer.name = "MusicPrayer"
	prayer.stream = _stream_for_layer(&"prayer")
	add_child(prayer)
	prayer.play()
	if not _layer_is_sourced[&"prayer"]:
		_prayer_playback = prayer.get_stream_playback()
	layers[&"prayer"] = prayer

	var infernal := AudioStreamPlayer.new()
	infernal.name = "MusicInfernal"
	infernal.stream = _stream_for_layer(&"infernal")
	add_child(infernal)
	infernal.play()
	if not _layer_is_sourced[&"infernal"]:
		_infernal_playback = infernal.get_stream_playback()
	layers[&"infernal"] = infernal

func _setup_ambience_layers() -> void:
	# Wind: deliberately non-spatial. This is a whole-sea/whole-island
	# ambient bed ("the whole sea sounds like this"), not a point source —
	# making it 3D would mean it fades out near the edges of wherever the
	# listener wanders, which is wrong for weather that blankets the entire
	# board. See docs/systems/audio.md for the fuller rationale.
	_wind_player = AudioStreamPlayer.new()
	_wind_player.name = "AmbienceWind"
	_wind_player.stream = _stream_for_layer(&"wind")
	add_child(_wind_player)
	_wind_player.play()
	if not _layer_is_sourced[&"wind"]:
		_wind_playback = _wind_player.get_stream_playback()

	# Sea/surf: deliberately spatial (AudioStreamPlayer3D). Waves breaking on
	# a shoreline genuinely are directional and distance-attenuated — louder
	# near the coast, quieter inland — unlike wind, which reads as ambient
	# everywhere. Positioned at a placeholder shoreline offset until a real
	# integration pass (or world/ocean's own package) calls
	# `set_sea_anchor()`/`set_sea_position()` with real geometry.
	# NOTE: like any AudioStreamPlayer3D, this is only audible with an
	# active Camera3D/AudioListener3D somewhere in the running scene tree —
	# that's standard Godot behavior, not something this autoload manages.
	_sea_player = AudioStreamPlayer3D.new()
	_sea_player.name = "AmbienceSea"
	_sea_player.stream = _stream_for_layer(&"sea")
	_sea_player.unit_size = 12.0
	_sea_player.max_distance = 400.0
	_sea_player.position = SEA_PLACEHOLDER_POSITION
	add_child(_sea_player)
	_sea_player.play()
	if not _layer_is_sourced[&"sea"]:
		_sea_playback = _sea_player.get_stream_playback()

func _setup_bell() -> void:
	var stream: AudioStream = load("res://audio/sfx/bong_001.ogg")
	if stream == null:
		push_warning("MusicDirector: audio/sfx/bong_001.ogg missing — rite-bell cue on Naklon.pole_crossed is disabled.")
		return
	_bell_player = AudioStreamPlayer.new()
	_bell_player.name = "RiteBell"
	_bell_player.stream = stream
	_bell_player.volume_db = -4.0
	add_child(_bell_player)

func _setup_sfx() -> void:
	# Load the one-shots up front (not on first use) so a missing file is a
	# single startup warning instead of a hitch mid-play, and so `load()` never
	# runs on the frame the player actually grabs something.
	for key: StringName in SFX_ASSETS:
		var path: String = SFX_ASSETS[key]
		if not ResourceLoader.exists(path):
			push_warning("MusicDirector: SFX '%s' missing (%s) — that cue is disabled; everything else still plays." % [key, path])
			continue
		var stream: AudioStream = load(path)
		if stream != null:
			_sfx_streams[key] = stream

	# Spatial voice pool. Created once, reused round-robin forever — no
	# per-event node allocation, which matters more than the audio cost on a
	# machine this tight.
	for i in SFX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "SfxVoice%d" % i
		voice.unit_size = 10.0
		voice.max_distance = 300.0
		add_child(voice)
		_sfx_voices.append(voice)

	# Thunder is deliberately NON-spatial, for the same reason wind is: a storm
	# is a whole-board condition, and thunder that pans and attenuates with the
	# camera would read as "a small noise over there" rather than weather.
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.name = "Thunder"
	if _sfx_streams.has(&"thunder"):
		_thunder_player.stream = _sfx_streams[&"thunder"]
	add_child(_thunder_player)

# --- Emitter discovery (Hand / SigilCaster / Louhi) --------------------------

## One-shot sweep of whatever is already in the tree. Cheap (a few hundred
## nodes, once) and only ever runs at startup; steady-state discovery is
## `_on_node_added`.
func _scan_tree_for_emitters() -> void:
	var root := get_tree().root
	if root != null:
		_scan_node_recursive(root)

func _scan_node_recursive(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_scan_node_recursive(child)

## Runs for every node that enters the tree. Deliberately capability-based
## (`has_signal`) rather than NodePath-based: `audio/` may not edit
## `world/god_view.tscn` and must not break if another package moves or renames
## its own nodes. Cost is three null checks per node added once everything is
## bound (see the early return), which is nothing next to instancing the node
## itself.
func _on_node_added(node: Node) -> void:
	if _hand != null and _sigil_caster != null and _louhi != null:
		return
	if _hand == null and node.has_signal(&"grabbed") and node.has_signal(&"released"):
		_bind_hand(node)
	if _sigil_caster == null and node.has_signal(&"rite_cast"):
		_bind_sigil_caster(node)
	if _louhi == null and node.has_signal(&"sign_occurred"):
		_bind_louhi(node)

# String-based `connect()` throughout (not `node.signal_name.connect(...)`):
# these nodes are statically typed as plain `Node` here, because depending on
# package E's `Hand` / package F's `SigilCaster` / package N's `LouhiDirector`
# class names would make audio/ fail to parse if any of those packages were
# absent. Same defensive pattern louhi_director.gd itself uses for /root/DuelArena.

func _bind_hand(node: Node) -> void:
	_hand = node
	node.connect("grabbed", _on_hand_grabbed)
	node.connect("released", _on_hand_released)
	node.tree_exiting.connect(_on_hand_gone)

func _bind_sigil_caster(node: Node) -> void:
	_sigil_caster = node
	node.connect("rite_cast", _on_rite_cast)
	node.tree_exiting.connect(_on_sigil_caster_gone)

## Louhi's signs reuse the same brief ducking dip as a Voices remark, at a
## slightly longer hold — "something happened" gets a beat of quiet.
func _bind_louhi(node: Node) -> void:
	_louhi = node
	node.connect("sign_occurred", _on_louhi_sign)
	node.tree_exiting.connect(_on_louhi_gone)

# Clearing the reference on exit is what lets a scene reload (or a skirmish map
# swap) rebind to the new instance instead of holding a freed one.
func _on_hand_gone() -> void:
	_hand = null

func _on_sigil_caster_gone() -> void:
	_sigil_caster = null

func _on_louhi_gone() -> void:
	_louhi = null

# --- Crossfade (Naklon) ------------------------------------------------------

func _on_naklon_changed(_old_value: float, _new_value: float) -> void:
	_update_crossfade()

func _update_crossfade() -> void:
	var t := Naklon.unit() # 0..1, 0 = full prayer, 1 = full infernal
	var angle := t * PI * 0.5
	_set_layer_gain(&"prayer", cos(angle))
	_set_layer_gain(&"infernal", sin(angle))

func _set_layer_gain(layer_name: StringName, linear_gain: float) -> void:
	var player: AudioStreamPlayer = layers.get(layer_name)
	if player == null:
		return
	var g: float = clampf(linear_gain, 0.0, 1.0) * MUSIC_MASTER * _duck_current
	var trim: float = SOURCED_MUSIC_TRIM_DB if _layer_is_sourced.get(layer_name, false) else 0.0
	player.volume_db = linear_to_db(maxf(g, 0.0001)) + trim

func _on_pole_crossed(pole: int) -> void:
	if _bell_player == null:
		return
	# Same asset, three meanings: a touch lower/softer for "settled back to
	# neutral" (pole == 0) than for "crossed into a dominance" (+-1), so the
	# one real sample reads slightly differently rather than being identical
	# every time.
	_bell_player.pitch_scale = 0.85 if pole == 0 else 1.0
	_bell_player.play()

# --- Ducking (Voices remarks / optional Louhi signs) ------------------------

func _on_voices_remark(_speaker: StringName, _line: String) -> void:
	_duck_target = DUCK_AMOUNT
	_duck_hold_timer = DUCK_HOLD_SEC

func _on_louhi_sign(_tier: int, _village_id: StringName, _description: String) -> void:
	_duck_target = DUCK_AMOUNT
	_duck_hold_timer = DUCK_LOUHI_HOLD_SEC

func _update_duck(delta: float) -> void:
	if _duck_hold_timer > 0.0:
		_duck_hold_timer -= delta
	else:
		_duck_target = 1.0
	_duck_current = move_toward(_duck_current, _duck_target, DUCK_RATE * delta)

	var is_ducked := _duck_current < 0.999
	if is_ducked != _was_ducked:
		_was_ducked = is_ducked
		ducked.emit(is_ducked)

# --- Ambience (Weather) ------------------------------------------------------

func _on_weather_changed(state: Dictionary) -> void:
	var wind_speed: float = state.get("wind_speed", 2.0)
	var precipitation: float = state.get("precipitation", 0.0)
	var storm_intensity: float = state.get("storm_intensity", 0.0)
	_storm_intensity = storm_intensity # cached for the thunder scheduler

	var wind_ratio := clampf(wind_speed / WIND_SPEED_REF, 0.0, 1.0)
	_wind_gain_target = clampf(WIND_GAIN_MIN + wind_ratio * (1.0 - WIND_GAIN_MIN), WIND_GAIN_MIN, 1.0)
	_wind_brightness_target = clampf(WIND_FILTER_MIN + wind_ratio * WIND_FILTER_RANGE, WIND_FILTER_MIN, WIND_FILTER_MIN + WIND_FILTER_RANGE)

	_sea_gain_target = clampf(SEA_GAIN_BASE + precipitation * 0.4 + storm_intensity * 0.35, 0.0, 1.0)

func _update_ambience_gains(delta: float) -> void:
	var rate := AMBIENCE_LERP_RATE * delta
	_wind_gain = move_toward(_wind_gain, _wind_gain_target, rate)
	_wind_brightness = move_toward(_wind_brightness, _wind_brightness_target, rate)
	_sea_gain = move_toward(_sea_gain, _sea_gain_target, rate)

	var wind_trim: float = SOURCED_WIND_TRIM_DB if _layer_is_sourced.get(&"wind", false) else 0.0
	var sea_trim: float = SOURCED_SEA_TRIM_DB if _layer_is_sourced.get(&"sea", false) else 0.0
	_wind_player.volume_db = linear_to_db(maxf(_wind_gain * WIND_MASTER, 0.0001)) + wind_trim
	_sea_player.volume_db = linear_to_db(maxf(_sea_gain * SEA_MASTER, 0.0001)) + sea_trim

	# The sourced wind bed is a fixed recording, so `_wind_brightness` can't
	# open its filter the way it does for the synthesized noise. Pitch is the
	# honest cheap substitute: a harder wind reads slightly faster/higher.
	# +-6% is small enough not to sound like a tape-speed effect.
	if _layer_is_sourced.get(&"wind", false):
		var brightness_ratio: float = clampf((_wind_brightness - WIND_FILTER_MIN) / WIND_FILTER_RANGE, 0.0, 1.0)
		_wind_player.pitch_scale = 0.97 + brightness_ratio * 0.09

# --- One-shot SFX: playback ---------------------------------------------------

## Round-robin through the fixed voice pool. Stealing the oldest voice when all
## four are busy is deliberate: a bounded, predictable cost beats an unbounded
## one, and with a single Hand four simultaneous one-shots is already generous.
func _play_sfx_3d(key: StringName, world_pos: Vector3, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _sfx_streams.get(key)
	if stream == null or _sfx_voices.is_empty():
		return
	var voice: AudioStreamPlayer3D = _sfx_voices[_sfx_next_voice]
	_sfx_next_voice = (_sfx_next_voice + 1) % _sfx_voices.size()
	voice.stream = stream
	voice.global_position = world_pos
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()

## Where a Hand/rite one-shot should sound from. Falls back to the sea anchor's
## neighbourhood rather than to (0,0,0) only if the Hand has gone — a one-shot
## with no emitter is rare enough not to be worth more machinery than this.
func _emitter_position(node: Node) -> Vector3:
	if node is Node3D:
		return (node as Node3D).global_position
	if _hand is Node3D:
		return (_hand as Node3D).global_position
	return Vector3.ZERO

func _on_hand_grabbed(_node: Node3D) -> void:
	# Slight random pitch so repeated grabs don't sound machine-stamped. One
	# randf_range per grab — an event, not a per-frame cost.
	_play_sfx_3d(&"grab", _emitter_position(_hand), SFX_GRAB_DB, randf_range(0.94, 1.08))

## `released(node, velocity)` carries the throw velocity, so the same event can
## read as either a set-down or a hurl without the Hand having to tell us which.
func _on_hand_released(_node: Node3D, velocity: Vector3) -> void:
	var pos := _emitter_position(_hand)
	var speed := velocity.length()
	if speed < THROW_MIN_SPEED:
		# Put down, not thrown: reuse the softer handling sample, quieter and
		# a touch lower, rather than a whoosh for something barely moving.
		_play_sfx_3d(&"grab", pos, SFX_GRAB_DB - 5.0, randf_range(0.85, 0.95))
		return
	var force := clampf(speed / THROW_REF_SPEED, 0.0, 1.0)
	# Harder throws are louder AND higher — a whoosh's pitch tracking its speed
	# is most of what makes a throw read as forceful.
	_play_sfx_3d(&"throw", pos, SFX_THROW_DB - (1.0 - force) * 9.0, 0.9 + force * 0.35)

## `rite_cast(rite_id, confidence)` from systems/sigils/sigil_caster.gd. A
## confidently-drawn sigil sounds fuller than a sloppy one that barely matched —
## the recognizer's own confidence is already the right number for that, so
## nothing new needed inventing here.
func _on_rite_cast(_rite_id: StringName, confidence: float) -> void:
	var conf := clampf(confidence, 0.0, 1.0)
	var pos := _emitter_position(_sigil_caster)
	_play_sfx_3d(&"rite", pos, SFX_RITE_DB - (1.0 - conf) * 6.0, 0.95 + conf * 0.12)

## Thunder scheduler. Per-frame cost is one float compare and (during a storm
## only) one subtract — see docs/systems/audio.md for why this is generated
## here rather than triggered by a lightning event that does not exist.
func _update_thunder(delta: float) -> void:
	if _storm_intensity < THUNDER_MIN_INTENSITY:
		# Re-arm to the long gap so a storm that has just formed doesn't crack
		# on its very first frame.
		_thunder_timer = THUNDER_GAP_MAX
		return
	_thunder_timer -= delta
	if _thunder_timer > 0.0:
		return
	# Heavier storms crack more often (shorter gap) and louder.
	var severity := clampf((_storm_intensity - THUNDER_MIN_INTENSITY) / (1.0 - THUNDER_MIN_INTENSITY), 0.0, 1.0)
	_thunder_timer = lerpf(THUNDER_GAP_MAX, THUNDER_GAP_MIN, severity) * randf_range(0.6, 1.4)
	if _thunder_player == null or _thunder_player.stream == null:
		return
	_thunder_player.volume_db = SFX_THUNDER_DB - (1.0 - severity) * 12.0
	_thunder_player.pitch_scale = randf_range(0.88, 1.06)
	_thunder_player.play()
	thunder_cracked.emit(_storm_intensity)

## Lets a future integration pass (or the package that owns world/ocean's
## real shoreline geometry) move the spatial sea layer onto real geometry
## instead of `SEA_PLACEHOLDER_POSITION`. Not called by anything in this
## package.
func set_sea_anchor(node: Node3D) -> void:
	if _sea_player == null or node == null:
		return
	_sea_player.reparent(node, false)
	_sea_player.position = Vector3.ZERO

func set_sea_position(pos: Vector3) -> void:
	if _sea_player != null:
		_sea_player.position = pos

# --- Runtime synthesis (placeholder tones — see header docstring) ----------

func _fill_all_generators() -> void:
	# In a normal build all four beds are file-backed, every playback handle
	# below is null, and this whole path costs four null compares per frame —
	# the ~176,000 per-second GDScript Callable invocations the previous
	# all-synthesized version needed (4 layers x 44,100 samples/sec) are simply
	# not executed. Only a build with a missing .ogg pays for synthesis, and
	# only for the layer that's actually missing.
	if _prayer_playback == null and _infernal_playback == null and _wind_playback == null and _sea_playback == null:
		return
	_fill_generator(_prayer_playback, _next_prayer_sample)
	_fill_generator(_infernal_playback, _next_infernal_sample)
	_fill_generator(_wind_playback, _next_wind_sample)
	_fill_generator(_sea_playback, _next_sea_sample)

func _fill_generator(playback: AudioStreamGeneratorPlayback, sample_fn: Callable) -> void:
	if playback == null:
		return
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i in frames:
		var s: float = sample_fn.call()
		buffer[i] = Vector2(s, s)
	playback.push_buffer(buffer)

## Calm/sacred placeholder pad: root + fifth + octave sine partials under a
## slow amplitude "breathing" swell. Deliberately consonant — no beating,
## no dissonant intervals — to read as "prayer" even as a bare tone.
func _next_prayer_sample() -> float:
	_prayer_ph_root = fposmod(_prayer_ph_root + TAU * PRAYER_FREQ_ROOT * _dt, TAU)
	_prayer_ph_fifth = fposmod(_prayer_ph_fifth + TAU * PRAYER_FREQ_FIFTH * _dt, TAU)
	_prayer_ph_octave = fposmod(_prayer_ph_octave + TAU * PRAYER_FREQ_OCTAVE * _dt, TAU)
	_prayer_ph_lfo = fposmod(_prayer_ph_lfo + TAU * PRAYER_LFO_HZ * _dt, TAU)

	var swell := 0.75 + 0.25 * sin(_prayer_ph_lfo)
	var s := sin(_prayer_ph_root) * 0.5 + sin(_prayer_ph_fifth) * 0.3 + sin(_prayer_ph_octave) * 0.2
	return s * swell * PRAYER_AMPLITUDE

## Dark/ominous placeholder drone: a low root against the tritone
## ("diabolus in musica") a slow beat apart, plus a thin noise grit so it
## doesn't read as a clean, pure tone.
func _next_infernal_sample() -> float:
	_infernal_ph_root = fposmod(_infernal_ph_root + TAU * INFERNAL_FREQ_ROOT * _dt, TAU)
	_infernal_ph_tritone = fposmod(_infernal_ph_tritone + TAU * INFERNAL_FREQ_TRITONE * _dt, TAU)
	_infernal_ph_lfo = fposmod(_infernal_ph_lfo + TAU * INFERNAL_LFO_HZ * _dt, TAU)

	var unease := 0.7 + 0.3 * sin(_infernal_ph_lfo)
	var s := sin(_infernal_ph_root) * 0.65 + sin(_infernal_ph_tritone) * 0.35
	s += (randf() - 0.5) * INFERNAL_GRIT
	return s * unease * INFERNAL_AMPLITUDE

## Wind placeholder: white noise through a one-pole low-pass whose cutoff
## (`_wind_brightness`) brightens with `Weather.current.wind_speed` — a
## storm's wind reads audibly harsher/hissier than a calm breeze, not just
## louder.
func _next_wind_sample() -> float:
	var white := randf() * 2.0 - 1.0
	_wind_lp = lerpf(_wind_lp, white, _wind_brightness)
	return _wind_lp

## Sea/surf placeholder: filtered noise under a slow rectified-sine
## surge-and-retreat envelope (~one wave cycle every ~8s) so it reads as
## "waves," not flat hiss.
func _next_sea_sample() -> float:
	var white := randf() * 2.0 - 1.0
	_sea_lp = lerpf(_sea_lp, white, SEA_FILTER_ALPHA)
	_sea_wave_ph = fposmod(_sea_wave_ph + TAU * SEA_WAVE_HZ * _dt, TAU)
	var envelope := 0.45 + 0.55 * absf(sin(_sea_wave_ph))
	return _sea_lp * envelope
