extends Resource
class_name Quest
## Static definition of one quest/objective. `CampaignManager` owns the
## *runtime* state (locked/active/complete, per playthrough); this resource
## is the authored, unchanging content a `QuestCatalog` entry describes —
## same split as `Culture` (static flavor data) vs. `Village` (runtime
## state), or `Relic` (static data) vs. `GameState.relics_held` (runtime
## list of held ids).
##
## Activation/completion are event-driven rather than polled: both
## `activation_trigger` and `completion_trigger` are internal campaign event
## names `CampaignManager._fire_campaign_event()` recognizes (see that
## file's own doc comment for the full vocabulary: `&"any_village_converted"`,
## `&"culture_village_converted"`, `&"first_epithet_earned"`,
## `&"rite_cast_any"`, `&"louhi_tier1"`, `&"louhi_tier1_resolved"`,
## `&"louhi_tier2"`, `&"louhi_tier3"`). These are campaign/'s own vocabulary,
## never the same namespace as `Voices.react()` triggers or `GameState`
## signals, even where a campaign event is fired *from* one of those (no
## collision risk, but called out so nobody greps for one and expects to
## find it defined as the other).

@export var id: StringName
@export var title: String
## "" if this quest isn't tied to one of the four peoples (a Louhi beat, or
## a whole-campaign capstone).
@export var culture_id: StringName = &""
@export var description: String

## Quest ids that must all be COMPLETE before this one can activate. Empty
## means "activates immediately at boot" (subject to activation_trigger,
## below).
@export var prerequisites: Array[StringName] = []

## "" means: activate the moment prerequisites are satisfied (checked once
## at `CampaignManager._ready()` and again after every quest completion).
## Non-"": stays LOCKED, even with prerequisites satisfied, until that named
## campaign event fires.
@export var activation_trigger: StringName = &""

## "" means: this quest only ever completes via an explicit
## `CampaignManager.complete_quest(id)` call from some other system.
## Non-"": auto-completes the moment that named campaign event fires while
## this quest is ACTIVE.
@export var completion_trigger: StringName = &""

## True for a pure narrative/log beat that is already true the instant it
## activates (e.g. "Louhi has just demanded a reckoning" — there's nothing
## further for the player to do to make that statement true; it just
## happened). When true, `CampaignManager` completes the quest in the same
## call that activates it, in the same evaluation pass so it never briefly
## renders as "active" to a quest-log UI.
@export var auto_complete_on_activate: bool = false

## Reward ids granted on completion. All three are safe to leave empty.
@export var reward_relics: Array[StringName] = []
@export var reward_scrolls: Array[StringName] = [] # SigilTemplates rite ids
## "" for no epithet reward. Passed verbatim to
## `GameState.earn_epithet(text, "quest:" + str(id))` on completion.
@export var reward_epithet: String = ""
