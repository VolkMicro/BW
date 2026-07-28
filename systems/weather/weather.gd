extends Node
## Autoload stub. Package P (systems/weather/) replaces this with the full
## sim: procedural weather cells drifting over the Ninefold Sea, plus the
## optional real-weather feed (Open-Meteo, no API key required) that maps
## the player's real location's current conditions onto the home island.

signal weather_changed(state: Dictionary)

var current: Dictionary = {
	"wind_dir_deg": 0.0,
	"wind_speed": 2.0,
	"precipitation": 0.0, # 0..1
	"cloud_cover": 0.2, # 0..1
	"temperature_c": 15.0,
	"is_storm": false,
	"source": "procedural", # or "real_feed"
}

func _ready() -> void:
	weather_changed.emit(current)
