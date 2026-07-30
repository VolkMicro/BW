# Playability audit — 2026-07-30

## How this was done, and what that is worth

This audit is built from three things: the shipped tuning constants, a
simulation of the conversion curve using those constants, and rendered stills
of the running game. **Nobody has played it.** That limit is real and it
bounds everything below: I can prove a target is 30 pixels wide and that
seven casts convert a village, and I cannot tell you whether drawing a sickle
with a mouse feels good. Treat the numbers as findings and the feel
judgements as hypotheses.

Frame rate on the target hardware (Dell Latitude 5411, integrated Intel) is
still unmeasured and remains the largest unknown in the project.

---

## The first sixty seconds, as a person meets them

1. The game launches straight into the island — no menu, no loading screen.
   Cold generation is ~2.7 s, cached ~0.5 s, and the cache survives restarts.
2. The camera opens on the whole island. Fifteen villages, each labelled with
   its name and one line of state.
3. The two Voices start talking in the lower left.
4. After a six-second grace, one line appears low-centre: *"Fifteen villages.
   None of them have decided what you are yet."*
5. Then: *"Press 3."* The rite panel shows all nine sigils as drawn shapes
   with a start dot and a direction arrow; three are yours.
6. Then: *"Hold the RIGHT mouse button over a village and draw one."*

Nothing is gated and no lesson blocks anything. A player who already knows
what to do never sees steps 4–6.

**Assessment: the opening is legible.** It was not two days ago — the panel
described the shapes in prose, and the two rites the objective line names
were not in the starting kit.

---

## What the numbers say

### Aiming (was broken, fixed)

| | |
|---|---|
| Village Reach circle | 15–22 m |
| …in screen pixels from god view | **25–35 px** |
| A recognisable sigil | 150–300 px across |

The rite used to be aimed at the Hand — wherever the mouse stopped, and
spring-damped at that. Drawing a 200-pixel shape *over* a 30-pixel target
finishes roughly 100 m away from it, so the game's only verb silently landed
on nothing. Rites now use the stroke's centroid. Guarded by
`tests/aim_test.tscn`.

### Pace of conversion

Simulated from `HELP_GAIN_PER_AMOUNT`, `FATIGUE_RISE_PER_USE`,
`FATIGUE_DECAY_PER_SECOND` and the 0.90 tipping point:

| Gap between casts on the SAME village | Casts to convert it |
|---|---|
| 3 s | 115 |
| 5 s | 67 |
| 10 s | 28 |
| 20 s | **7** |

Fatigue is the single most important rule in the game. Patience is worth
sixteen times what spamming is, which turns the whole island into the play
space: cast, move on, come back. Played that way an island is roughly 105
casts and, with camera work and Louhi's interference, **20–40 minutes**.

That rule was invisible. Village markers now say "heard enough for now" when
either method drops below 45% effectiveness.

### Pressure from Louhi

She evaluates every 75 s, notices any village above 0.05 faith, gives it 300 s
to improve, then takes it. **The earliest a first village can be lost is
about six minutes in** — comfortably after the opening lessons, tight but
fair for a first island. Every village she holds shortens her clock, to a
26 s floor. Ten clean rites take one back.

---

## Findings

### Fixed in this pass

1. **Rites landed where the mouse stopped.** Critical — it broke the core
   verb. Now the stroke's centroid, marched onto the terrain.
2. **The Voices were drowned by the food chain.** `wildlife_kill` had no
   pacing cooldown; scaling the island's animals from 16 to 74 made predation
   the most frequent event in the game, and the log was six lines of snagbill
   obituary with the gameplay lines already scrolled off. Now 45 s.
3. **Fatigue was invisible.** See above.

### Open, ranked

1. **Frame rate on the target machine is unknown.** Everything else is
   guesswork until somebody runs it on the Latitude.
2. **No audio confirmation that a rite landed.** There are CC0 sfx wired for
   casting, but nothing distinguishes *recognised and landed* from
   *recognised and out of reach* by ear. The Hand flashes; that is easy to
   miss while looking at the village.
3. **Reach is explained but not shown until you fail.** The ring is drawn per
   village, but at god-view zoom a 20 m ring is thin. A player's first
   refusal is likely to read as "the drawing didn't work" rather than "you
   can't reach there" — the two failures look identical from the player's
   side.
4. **Nine rites, three known, and no visible path to the other six.** They
   come from quests; nothing on screen says which quest.
5. **No way to compare villages except by flying around.** Fifteen markers
   are readable when they are on screen; there is no island-wide list.
6. **The temple interior is a dark void** up close (long-standing).
7. **Rivers read faintly from god view** (long-standing).

---

## Verdict against the question asked

**Understandable?** The opening now teaches itself, the sigils are shown as
shapes rather than described, and every village states what it needs. The
remaining comprehension gap is failure feedback: a rite that misses, a rite
out of reach, and a rite the village is tired of are three different things
that currently feel the same.

**Easy?** The aiming fix moves it from "unplayable by accident" to "a normal
pointing task". The drawing itself is a $1 recognizer at a 0.75 threshold,
which is forgiving; the shapes are distinct enough not to collide.

**Pleasant?** Unknown, honestly. The parts that produce pleasure in this
genre — the sound of a rite landing, the moment a village flips, the feeling
of an island slowly turning your colour — exist mechanically but have had no
polish pass, and one of them (audio confirmation) is missing outright.
