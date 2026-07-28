extends Resource
class_name AvatarSpecies
## PACKAGE K — data-only description of one Avatar species/starting body.
## avatar.gd is the ONE shared brain/body-builder; every species is just a
## small Resource of tuning numbers + placeholder-mesh palette so a new
## species can be added later without touching avatar.gd's logic at all.
##
## `base_learning_rate` is the single most important number here: it's the
## species' baseline for how fast beliefs move per praise/chastise event
## (see Avatar._effective_learning_rate, which also scales this by the
## avatar's own current Watching attachment — the species number is a
## starting bias, not a hard cap).

@export var id: StringName = &""
@export var display_name: String = ""
@export var one_line: String = ""

## Belief learning-rate baseline. Higher = a single praise/chastise moves a
## belief further. This is a design axis, not a difficulty axis: Otso is
## slow to learn but hits like a landslide once grown; Krukk is the reverse.
@export_range(0.02, 1.0, 0.01) var base_learning_rate: float = 0.35

## Starting Attachments (0..1). These are only the SEED — every avatar's
## Watching/Toothy/Kind then drifts independently from here based on how
## the player actually plays (see docs/systems/avatar.md, "Divergence from
## Naklon"). They are deliberately NOT derived from Naklon.value.
@export_range(0.0, 1.0, 0.01) var start_attachment_watching: float = 0.5
@export_range(0.0, 1.0, 0.01) var start_attachment_toothy: float = 0.3
@export_range(0.0, 1.0, 0.01) var start_attachment_kind: float = 0.3

## Base stat multipliers (1.0 = "average" across the three species). These
## are read by combat (package L) and any other system via
## Avatar.get_effective_strength/speed/stamina(), which additionally fold
## in the current growth stage's stat_mult.
@export var base_strength: float = 1.0
@export var base_speed: float = 1.0
@export var base_stamina: float = 1.0

## Base visual scale at growth stage "Grown" (index 2 of Avatar.GROWTH_STAGES).
## Earlier stages shrink this, later stages grow it further — see
## Avatar.get_effective_scale().
@export var base_scale: float = 1.0

## Sarv-only in this pass, but kept generic: does this species let the
## player feed accumulated devotion back into a village as food/resources?
## See docs/systems/avatar.md "Scoped out" for what is NOT wired up yet.
@export var feeds_villages: bool = false
@export var devotion_yield_per_feed_action: float = 0.0

## Placeholder-mesh palette (see Avatar._build_placeholder_body). Real
## sculpted/scanned creature art is out of scope for this pass — this is
## primitive-composed geometry honestly tinted per species.
@export var color_primary: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var color_accent: Color = Color(0.8, 0.8, 0.8, 1.0)

## Free-text note for whoever eventually replaces the placeholder mesh.
@export_multiline var body_notes: String = ""
