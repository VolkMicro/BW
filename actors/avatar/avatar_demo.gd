extends Node3D
## Standalone demo/debug harness for Package K — the Avatar's learning model
## (actors/avatar/avatar_demo.tscn). Spawns one Avatar, assigns it the Otso
## species, then runs a scripted sequence of simulated context + praise/
## chastise events so the belief store and the three Attachments visibly
## move (Output panel + the in-world debug label + the on-screen log).
##
## This also demonstrates the required divergence from Naklon: before
## running a single feedback event, it shoves Naklon hard toward Cruelty —
## then trains the Avatar in the OPPOSITE direction (praise the kind/careful
## acts, chastise the aggressive ones). If attachment_toothy/kind were
## secretly slaved to Naklon.value, this run would end with a cruel beast
## despite the training. It doesn't: watch the final log line.
##
## Real player input still works throughout: press F (praise_avatar) / G
## (chastise_avatar) any time — the currently active context tag (printed
## in the log) is whatever the scripted sequence has open at that moment.

@onready var _avatar: Avatar = $Avatar
@onready var _log_label: Label = $UI/LogLabel
@onready var _status_label: Label = $UI/StatusLabel

const SPECIES_OTSO: AvatarSpecies = preload("res://actors/avatar/species/otso.tres")

# Each step: open a context tag, let the player/script see its belief and
# would_do() reading, apply N praise or chastise events to it (each one a
# REAL call into Avatar.receive_praise()/receive_chastise() — not a faked
# belief write), then close the tag and report the belief/would_do delta.
const SCRIPT_STEPS: Array[Dictionary] = [
	{"tag": &"attack_predator", "feedback": "chastise", "repeats": 4},
	{"tag": &"eat_villager", "feedback": "chastise", "repeats": 4},
	{"tag": &"hoard_food", "feedback": "chastise", "repeats": 2},
	{"tag": &"carry_resource", "feedback": "praise", "repeats": 3},
	{"tag": &"guard_village", "feedback": "praise", "repeats": 3},
	{"tag": &"approach_stranger", "feedback": "praise", "repeats": 2},
]

const DEVOTION_PER_FEEDBACK_EVENT := 12.0
const STEP_PAUSE := 0.35
const EVENT_PAUSE := 0.22

var _log_lines: Array[String] = []


func _ready() -> void:
	_avatar.set_species(SPECIES_OTSO)
	_avatar.belief_updated.connect(_on_belief_updated)
	_avatar.attachment_changed.connect(_on_attachment_changed)
	_avatar.grew.connect(_on_grew)

	Naklon.shift(0.8, 1.0) # push hard toward Cruelty BEFORE any avatar feedback
	_push_log("Naklon pushed to %.2f (Cruelty) before any Avatar feedback runs." % Naklon.value)
	_push_log("Training the OPPOSITE way: chastising aggression, praising care.")
	_run_demo_script()


func _run_demo_script() -> void:
	for step in SCRIPT_STEPS:
		var tag: StringName = step.tag
		var feedback: String = step.feedback
		var repeats: int = int(step.repeats)

		_avatar.begin_context(tag)
		_push_log("context ON: %s   belief=%.2f  would_do=%s" % [
			tag, _avatar.get_belief(tag), str(_avatar.would_do(tag))
		])
		await get_tree().create_timer(STEP_PAUSE).timeout

		for i in range(repeats):
			if feedback == "praise":
				_avatar.receive_praise()
			else:
				_avatar.receive_chastise()
			_avatar.feed_devotion(DEVOTION_PER_FEEDBACK_EVENT)
			await get_tree().create_timer(EVENT_PAUSE).timeout

		_push_log("  -> after %d x %s: belief=%.2f  would_do now=%s" % [
			repeats, feedback, _avatar.get_belief(tag), str(_avatar.would_do(tag))
		])
		_avatar.end_context(tag)
		await get_tree().create_timer(STEP_PAUSE).timeout

	_push_log("DONE. W=%.2f T=%.2f K=%.2f  (Naklon=%.2f, unit=%.2f)" % [
		_avatar.attachment_watching, _avatar.attachment_toothy, _avatar.attachment_kind,
		Naklon.value, Naklon.unit(),
	])
	_push_log("Naklon is Cruelty-high but Toothy ended up low / Kind high: attachments are NOT slaved to Naklon.")


func _on_belief_updated(tag: StringName, old_value: float, new_value: float) -> void:
	print("[Avatar] belief(%s): %.3f -> %.3f" % [tag, old_value, new_value])


func _on_attachment_changed(axis: StringName, old_value: float, new_value: float) -> void:
	print("[Avatar] attachment(%s): %.3f -> %.3f" % [axis, old_value, new_value])


func _on_grew(old_stage: int, new_stage: int) -> void:
	_push_log("GREW: stage %d -> %d (%s)" % [old_stage, new_stage, _avatar.get_growth_stage_name()])


func _push_log(line: String) -> void:
	print("[AvatarDemo] " + line)
	_log_lines.append(line)
	if _log_lines.size() > 12:
		_log_lines.pop_front()
	if _log_label:
		_log_label.text = "\n".join(_log_lines)


func _process(_delta: float) -> void:
	if _status_label:
		_status_label.text = (
			"Species: %s   Stage: %s   Scale: %.2fx\n" +
			"Watching: %.2f   Toothy: %.2f   Kind: %.2f\n" +
			"praise_count: %d   chastise_count: %d   devotion_fed: %.0f\n" +
			"active context tags: %s\n" +
			"Naklon: %.2f (unit %.2f) — tracked separately from the Attachments above."
		) % [
			_avatar.get_species_id(), _avatar.get_growth_stage_name(), _avatar.get_effective_scale(),
			_avatar.attachment_watching, _avatar.attachment_toothy, _avatar.attachment_kind,
			_avatar.praise_count, _avatar.chastise_count, _avatar.devotion_fed,
			str(_avatar.active_tags),
			Naklon.value, Naklon.unit(),
		]
