extends Resource
class_name Relic
## Static data describing one relic. `GameState.relics_held` (core/game_state.gd)
## only ever stores bare `StringName` ids — this resource is what gives an id
## real meaning (a name, a culture, flavor text) once it's looked up through
## `RelicCatalog`. Deliberately data-only (no gameplay hooks of its own): a
## relic held is just an id in `GameState.relics_held` until some other
## system decides an id being present/absent means something mechanically
## (e.g. `actors/louhi/louhi_director.gd`'s tier-3 theft already reads and
## removes from that same array — see docs/systems/campaign.md).
##
## Every relic here is fictional per docs/audit/respect_audit.md: drawn from
## the same four invented cultures (data/cultures/*.tres) or from Louhi's own
## already-vetted Kalevala role (README.md / respect_audit.md's sourcing
## table), never a real venerated deity's object and never a real sacred
## symbol. `origin_notes` exists specifically to carry the one-line audit
## rationale alongside the data, the same way each Culture's own
## `taboo_notes` field carries its rationale inline rather than only in a doc.

@export var id: StringName
@export var display_name: String
## "" for a relic that belongs to no single culture (Louhi's mythos, or the
## Ninefold Sea's own frame-myth rather than any one people's).
@export var culture_id: StringName = &""
@export var flavor: String
## Short in-repo note on why this name/object is audit-safe — see the class
## doc above. Not shown to the player; a paper trail for the audit pass.
@export var origin_notes: String
## "" if picking this relic up doesn't carry an epithet. When set, this is
## the exact string `CampaignManager.grant_relic()` passes to
## `GameState.earn_epithet(text, reason)`.
@export var grants_epithet: String = ""
