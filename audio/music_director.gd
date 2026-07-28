extends Node
## Autoload stub. Package R (audio/) replaces this with the full adaptive
## layered mix (prayer <-> infernal arrangement, crossfaded continuously by
## Naklon.unit()) and 3D spatial ambience. Kept minimal so any scene that
## expects MusicDirector to exist can boot before that package lands.

var layers: Dictionary = {} # &"prayer" / &"infernal" -> AudioStreamPlayer

func _ready() -> void:
	Naklon.naklon_changed.connect(_on_naklon_changed)

func _on_naklon_changed(_old: float, _new: float) -> void:
	pass # crossfade logic lands with package R
