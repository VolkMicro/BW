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
## HONESTY NORM — what's real vs. placeholder here (full account, including
## the exact searches performed and their results, in docs/systems/audio.md):
##  All four continuous beds (prayer, infernal, wind, sea) are **synthesized
##  at runtime** with `AudioStreamGenerator`, not sourced audio files. No
##  mood-appropriate CC0 prayer/infernal music loop, and no wind/sea ambience
##  loop, was obtainable within reasonable effort: Kenney's entire Audio
##  category (verified by walking all 9 of its actual audio packs) contains
##  only UI blips, sci-fi/impact one-shots, RPG interaction foley, and
##  short (~1-2s) music *jingles* — no ambient nature loops and nothing
##  usable as a sustained mood bed; Freesound's download endpoints 401
##  without an API key this sandbox does not have (confirmed:
##  `curl https://freesound.org/apiv2/search/text/?query=wind+loop` ->
##  401 "Authentication credentials were not provided"); Musopen returned
##  403 on every request, including with a browser User-Agent header. This
##  is the repository's documented escape hatch for exactly this situation
##  (README "What this repository is, honestly") — stated plainly here and
##  in the doc, not silently presented as finished.
##
##  `res://audio/sfx/bong_001.ogg` **is** a real, verified CC0 asset (Kenney
##  "Interface Sounds" pack, https://kenney.nl/assets/interface-sounds) used
##  as-is for the one-shot "rite bell" that plays on `Naklon.pole_crossed`.
##  See docs/systems/audio.md "Assets used" for the exact CREDITS-ready row.

# --- Public state (kept from the original stub's documented contract) ------

var layers: Dictionary = {} # &"prayer" / &"infernal" -> AudioStreamPlayer

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

	Naklon.naklon_changed.connect(_on_naklon_changed)
	Naklon.pole_crossed.connect(_on_pole_crossed)
	Weather.weather_changed.connect(_on_weather_changed)
	Voices.remark.connect(_on_voices_remark)
	_connect_louhi_if_present()

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

# --- Setup -------------------------------------------------------------------

func _make_generator_stream() -> AudioStreamGenerator:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = GEN_BUFFER_LENGTH
	return stream

func _setup_music_layers() -> void:
	var prayer := AudioStreamPlayer.new()
	prayer.name = "MusicPrayer"
	prayer.stream = _make_generator_stream()
	add_child(prayer)
	prayer.play()
	_prayer_playback = prayer.get_stream_playback()
	layers[&"prayer"] = prayer

	var infernal := AudioStreamPlayer.new()
	infernal.name = "MusicInfernal"
	infernal.stream = _make_generator_stream()
	add_child(infernal)
	infernal.play()
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
	_wind_player.stream = _make_generator_stream()
	add_child(_wind_player)
	_wind_player.play()
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
	_sea_player.stream = _make_generator_stream()
	_sea_player.unit_size = 12.0
	_sea_player.max_distance = 400.0
	_sea_player.position = SEA_PLACEHOLDER_POSITION
	add_child(_sea_player)
	_sea_player.play()
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

## Optional, defensive: if a future integration pass instances
## `actors/louhi/louhi_director.gd` (package N) as `/root/LouhiDirector`,
## react to her signs with the same brief ducking dip used for Voices
## remarks — "something happened" gets a beat of quiet rather than nothing.
## As of this pass `LouhiDirector` is not instanced anywhere (see its own
## docs/systems/louhi.md "Scoped out"), so `get_node_or_null` returns null
## and this is a safe no-op today. Mirrors the same defensive-connection
## pattern louhi_director.gd itself uses for `/root/DuelArena`.
func _connect_louhi_if_present() -> void:
	var louhi := get_node_or_null("/root/LouhiDirector")
	# String-based connect (not `louhi.sign_occurred.connect(...)`) deliberately:
	# `louhi` is statically typed as plain `Node` here (that's all
	# `get_node_or_null` can promise without depending on package N's script
	# class), so the direct signal-object syntax would fail static analysis.
	if louhi != null and louhi.has_signal("sign_occurred"):
		louhi.connect("sign_occurred", _on_louhi_sign)

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
	player.volume_db = linear_to_db(maxf(g, 0.0001))

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

	var wind_ratio := clampf(wind_speed / WIND_SPEED_REF, 0.0, 1.0)
	_wind_gain_target = clampf(WIND_GAIN_MIN + wind_ratio * (1.0 - WIND_GAIN_MIN), WIND_GAIN_MIN, 1.0)
	_wind_brightness_target = clampf(WIND_FILTER_MIN + wind_ratio * WIND_FILTER_RANGE, WIND_FILTER_MIN, WIND_FILTER_MIN + WIND_FILTER_RANGE)

	_sea_gain_target = clampf(SEA_GAIN_BASE + precipitation * 0.4 + storm_intensity * 0.35, 0.0, 1.0)

func _update_ambience_gains(delta: float) -> void:
	var rate := AMBIENCE_LERP_RATE * delta
	_wind_gain = move_toward(_wind_gain, _wind_gain_target, rate)
	_wind_brightness = move_toward(_wind_brightness, _wind_brightness_target, rate)
	_sea_gain = move_toward(_sea_gain, _sea_gain_target, rate)

	_wind_player.volume_db = linear_to_db(maxf(_wind_gain * WIND_MASTER, 0.0001))
	_sea_player.volume_db = linear_to_db(maxf(_sea_gain * SEA_MASTER, 0.0001))

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
