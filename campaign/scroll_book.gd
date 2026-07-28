class_name ScrollBook
extends RefCounted
## Bookkeeping layer for `GameState.scrolls_known` (a bare `Array[StringName]`
## with no prior meaning — see core/game_state.gd) against the nine real rite
## ids defined in `systems/sigils/sigil_templates.gd`'s `SigilTemplates`.
##
## Deliberately a stateless static utility (no instance, no autoload) rather
## than living only on `CampaignManager`: `GameState.scrolls_known` is
## already the real, singular source of truth (an always-present autoload
## per docs/systems/OWNERSHIP.md — every read/write below assumes that
## registration, exactly like `systems/faith/reach.gd` and
## `systems/voices/voice_lines.gd` already assume `GameState`/`Voices` are
## live rather than defensively checking every call), so anything that just
## wants to ask "is this rite unlocked" — a future UI pass, a debug panel —
## can call `ScrollBook.is_rite_unlocked(rite_id)` directly with no
## `CampaignManager` node required. `CampaignManager`
## (campaign/campaign_manager.gd) exposes thin wrapper methods of the same
## name for callers that already hold a reference to it and want the
## `scroll_learned` signal that firing through the manager gives them.
##
## THE GATING GAP THIS DOESN'T FIX: `systems/sigils/sigil_caster.gd` (package
## F's territory — this package may not edit it) currently recognizes and
## fires `rite_cast` for any of the nine rites regardless of
## `GameState.scrolls_known`, i.e. every rite is playable today whether or
## not it's "known." `is_rite_unlocked()` below is real, correct, and ready
## to be called — it just isn't called by `sigil_caster.gd` yet. See
## docs/systems/campaign.md's "Scoped out" section for the exact one-line
## hook (`if not ScrollBook.is_rite_unlocked(rite_id): return` right before
## `rite_cast.emit(...)` in `_try_recognize()`) flagged for package F rather
## than patched here.

## Rites known from the very start of the game, before any scroll is found.
## `&"ward"` (a plain protective circle) is the one rite every culture's own
## player-god relationship would reasonably start with — a village's very
## first ask of a new, unproven god is protection, not weather control or
## war. The other eight are discovered over the course of the campaign
## (see campaign/quest_catalog.gd's reward_scrolls).
const DEFAULT_KNOWN_RITES: Array[StringName] = [&"ward"]

## True if `rite_id` is either a default-known rite or already present in
## `GameState.scrolls_known`. An id `SigilTemplates` doesn't recognize at all
## returns false rather than silently defaulting to "unlocked."
static func is_rite_unlocked(rite_id: StringName) -> bool:
	if rite_id in DEFAULT_KNOWN_RITES:
		return true
	return rite_id in GameState.scrolls_known

## Learns a scroll: appends `rite_id` to `GameState.scrolls_known` if it's a
## real rite id (per `SigilTemplates.DESCRIPTIONS`) not already known.
## Returns true if this call actually changed anything (so a caller — e.g.
## `CampaignManager.complete_quest()` — knows whether to fire its own
## `scroll_learned` signal / a Voices remark, rather than doing so on a
## no-op re-grant).
static func learn_scroll(rite_id: StringName) -> bool:
	if not SigilTemplates.DESCRIPTIONS.has(rite_id):
		push_warning("ScrollBook.learn_scroll: %s is not a real SigilTemplates rite id — ignored." % rite_id)
		return false
	if is_rite_unlocked(rite_id):
		return false
	GameState.scrolls_known.append(rite_id)
	return true

## Every rite currently castable-with-a-scroll-in-hand: the default set plus
## whatever `GameState.scrolls_known` has accumulated. Convenience for a
## future UI pass (package T) that wants "here's everything you can draw"
## without reimplementing the union logic above.
static func known_rite_ids() -> Array[StringName]:
	var out: Array[StringName] = DEFAULT_KNOWN_RITES.duplicate()
	for rite_id in GameState.scrolls_known:
		if rite_id not in out:
			out.append(rite_id)
	return out

## Every rite that exists but hasn't been learned yet — the "still locked"
## list a scroll-hunt UI would want to show as silhouettes.
static func locked_rite_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for rite_id in SigilTemplates.DESCRIPTIONS.keys():
		if not is_rite_unlocked(rite_id):
			out.append(rite_id)
	return out
