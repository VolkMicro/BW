extends Resource
class_name WildlifeSpecies
## PACKAGE W (wildlife) — data-only description of one wild animal species.
##
## Deliberately built the same way package K built `AvatarSpecies`
## (`actors/avatar/species/avatar_species.gd`): ONE shared brain/body-builder
## (`actors/wildlife/wild_creature.gd`) plus a small Resource of tuning
## numbers per species, so a fourth animal can be added later by writing one
## `.tres` and one `build_*` block in `wildlife_body.gd`, without touching the
## AI at all.
##
## Every number here is a design knob, not a magic constant buried in code.
## Distances are in metres; the AI compares SQUARED distances internally
## (see wild_creature.gd) so nothing here is ever fed to `.distance_to()`.

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
@export var id: StringName = &""
@export var display_name: String = ""
@export var one_line: String = ""

# ---------------------------------------------------------------------------
# Look — primitive-mesh palette only. wildlife_body.gd builds the whole
# animal out of CapsuleMesh/SphereMesh/BoxMesh/CylinderMesh in code and
# merges it into ONE ArrayMesh with exactly two surfaces (primary, accent),
# so a whole species shares one Mesh resource and two Materials.
# ---------------------------------------------------------------------------
@export var color_primary: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var color_accent: Color = Color(0.8, 0.8, 0.8, 1.0)
@export var body_scale: float = 1.0
@export var label_height: float = 1.8

# ---------------------------------------------------------------------------
# Collision capsule (CharacterBody3D). Set so the capsule's BOTTOM sits at
# local y = 0, i.e. collider_y == collider_height * 0.5.
# ---------------------------------------------------------------------------
@export var collider_radius: float = 0.4
@export var collider_height: float = 1.0

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
@export var walk_speed: float = 1.6      ## calm wander pace
@export var flee_speed: float = 4.2      ## panic sprint
@export var hunt_speed: float = 0.0      ## predators only (0 = never hunts)
@export var turn_rate: float = 4.0       ## lerp_angle factor for yaw

# ---------------------------------------------------------------------------
# Fear response. `flee_radius` is the species-specific "a god / a predator
# got this close" trigger; `calm_radius` is deliberately larger so the
# state machine has hysteresis and animals don't strobe in and out of panic
# right at the boundary. `calm_seconds` is how long the threat has to stay
# outside calm_radius before the animal goes back to grazing.
# ---------------------------------------------------------------------------
@export var flee_radius: float = 11.0
@export var calm_radius: float = 17.0
@export var calm_seconds: float = 4.0
@export var flee_step: float = 14.0      ## how far ahead it aims when running

# ---------------------------------------------------------------------------
# Home range / wandering
# ---------------------------------------------------------------------------
@export var home_range_radius: float = 26.0
@export var wander_step: float = 9.0     ## max distance of one wander leg
@export var wander_min_seconds: float = 3.0
@export var wander_max_seconds: float = 8.0
@export var graze_min_seconds: float = 5.0
@export var graze_max_seconds: float = 13.0

# ---------------------------------------------------------------------------
# Herding (cheap cohesion — see docs/systems/wildlife.md "Flocking, honestly")
# ---------------------------------------------------------------------------
@export var is_herd: bool = false
@export var cohesion_radius: float = 9.0  ## beyond this from the herd centroid, drift back
@export var cohesion_weight: float = 0.55 ## 0 = ignore the herd, 1 = walk straight at it

# ---------------------------------------------------------------------------
# Predation
# ---------------------------------------------------------------------------
@export var is_predator: bool = false
## Species ids this animal will actually hunt. A species absent from every
## predator's list is simply never hunted (this is how the snagbill stays
## alive next to a thawjaw without needing an "escape chance" fudge).
@export var hunts: PackedStringArray = PackedStringArray()
@export var hunt_radius: float = 34.0
@export var kill_range: float = 1.7
@export var seconds_to_hunger: float = 80.0 ## time from a full belly to hunting again
@export var feed_seconds: float = 12.0

## Prey flag: whether predators are allowed to list this species in `hunts`
## AND whether this animal flees from predators at all. A thawjaw has this
## false, so it does not run from itself or from another thawjaw.
@export var is_prey: bool = true

# ---------------------------------------------------------------------------
# Scavenging — reacts to WildlifeManager.prey_killed by walking to the kill
# site. Event-driven, costs nothing until something actually dies.
# ---------------------------------------------------------------------------
@export var scavenges: bool = false
@export var scavenge_radius: float = 55.0
@export var scavenge_seconds: float = 9.0

# ---------------------------------------------------------------------------
# AI tick. Each creature ticks its own decision pass this often, with a
# randomized phase assigned at spawn so a herd never thinks on the same
# frame. Larger = cheaper and dopier.
# ---------------------------------------------------------------------------
@export var think_interval: float = 0.35

## Lowest terrain height (world Y) this species will voluntarily walk onto or
## spawn at. Keeps grazers out of the surf without a single raycast — see
## wild_creature.gd's wander-target rejection.
@export var min_ground_height: float = 1.2


## Convenience: the collider's local Y centre, so the capsule's bottom sits
## exactly on the creature's origin.
func collider_center_y() -> float:
	return collider_height * 0.5
