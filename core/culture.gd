extends Resource
class_name Culture
## Static data describing one of the four invented peoples. Every field here
## is fiction: no culture is named after, or built as a costume of, a real
## living or historical people. See docs/audit/respect_audit.md for the
## sourcing notes on where the *flavor* (materials, silhouettes, landscape
## words) was drawn from and why the names themselves are not real ethnonyms.

@export var id: StringName
@export var display_name: String
@export var one_line: String
@export var material_palette: Array[String] = [] # notes for the art dept, not real texture paths yet
@export var architecture_notes: String
@export var ritual_name: String
@export var ritual_notes: String
@export var taboo_notes: String
@export var color_primary: Color = Color.WHITE
@export var color_accent: Color = Color.WHITE
@export var voice_notes: String
