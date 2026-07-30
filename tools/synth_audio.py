#!/usr/bin/env python3
"""Generates every ambient bed and cue this game uses.

WHY THE AUDIO IS SYNTHESISED RATHER THAN SOURCED
------------------------------------------------
`docs/audit/respect_audit.md` requires every third-party asset to trace to a
real, checkable licence. Sourced audio satisfies that only as long as somebody
keeps the paper trail intact, and the previous beds were a grab-bag of CC0
clips whose character had nothing to do with this island: the sea was a flat
band of noise, the "music" was a generic ambient loop.

Everything this script writes is authored here, in the open, from first
principles. It is original by construction, there is no licence question, and
— more usefully — every sound can be tuned to the game instead of the game
being tuned to whatever was downloadable.

WHY THE SEA WAS THE WORST OF THEM
---------------------------------
A recording of surf played on a loop reads as white noise because the loop is
short and the ear locks onto its period within seconds. Real sea is not a
texture, it is EVENTS: a slow swell you feel more than hear, and individual
breakers that hiss and drain on their own schedule. This synthesises both —
brown noise under three incommensurate swell LFOs, with discrete breaking
waves scattered on top, each with its own attack, hiss and drain.

LOOPING
-------
Everything long is generated a little over length and then tail-crossfaded
into its own head, so there is no seam and no need to make every LFO period
divide the loop length.

Usage:  python3 tools/synth_audio.py
Writes 16-bit mono WAVs into audio/generated/.
"""

import math
import os
import struct
import wave

import numpy as np

SR = 32000          # plenty for ambience; keeps the repo from ballooning
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "audio", "generated")

rng = np.random.default_rng(20260730)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def write_wav(name, samples, sr=SR):
    """16-bit mono. Peak-normalised with headroom, then dithered.

    Dither matters more than it looks: these are quiet ambient beds, and
    quantising a slow fade to 16 bits without it produces audible stepping —
    which on a drone sounds exactly like the "plastic" quality this whole
    pass is meant to remove.
    """
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.89
    x = x + rng.normal(0.0, 1.0 / 32768.0, x.shape)
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    print("%-28s %6.1f s  %5.1f MB" % (name, len(x) / sr, os.path.getsize(path) / 1e6))


def seamless(x, loop_seconds, fade_seconds=2.5):
    """Crossfades the tail over the head so the loop has no seam."""
    n = int(loop_seconds * SR)
    f = int(fade_seconds * SR)
    assert len(x) >= n + f, "generate at least loop+fade seconds"
    head = x[:n].copy()
    tail = x[n:n + f]
    ramp = np.linspace(0.0, 1.0, f)
    head[:f] = head[:f] * ramp + tail * (1.0 - ramp)
    return head


def brown(n, leak=0.995):
    """Brown-ish noise: integrated white with a slow leak so it cannot walk
    away into an offset over a long file."""
    w = rng.normal(0.0, 1.0, n)
    out = np.empty(n)
    acc = 0.0
    for i in range(n):
        acc = acc * leak + w[i]
        out[i] = acc
    return out / (np.max(np.abs(out)) or 1.0)


def one_pole_lp(x, cutoff_hz):
    """Simple one-pole low pass. Cutoff may be an array (per-sample sweep)."""
    n = len(x)
    c = np.broadcast_to(np.asarray(cutoff_hz, dtype=np.float64), (n,))
    a = 1.0 - np.exp(-2.0 * math.pi * c / SR)
    out = np.empty(n)
    y = 0.0
    for i in range(n):
        y += a[i] * (x[i] - y)
        out[i] = y
    return out


def one_pole_hp(x, cutoff_hz):
    return x - one_pole_lp(x, cutoff_hz)


def band(x, lo, hi):
    return one_pole_hp(one_pole_lp(x, hi), lo)


def lfo(n, period_s, phase=0.0):
    t = np.arange(n) / SR
    return np.sin(2.0 * math.pi * (t / period_s + phase))


# ---------------------------------------------------------------------------
# the sea
# ---------------------------------------------------------------------------

def sea(loop_s=30.0):
    """Swell plus discrete breakers. See the module docstring for why."""
    n = int((loop_s + 3.0) * SR)

    # Swell: three incommensurate periods so the ear never finds the cycle.
    swell = (0.55 + 0.22 * lfo(n, 7.3) + 0.15 * lfo(n, 11.7, 0.31)
             + 0.10 * lfo(n, 17.1, 0.62))
    swell = np.clip(swell, 0.12, 1.0)

    body = one_pole_lp(brown(n), 420.0) * swell

    # Breakers. Each is a burst of hiss with a fast rise and a long drain —
    # the drain is what a recording loop never gets right, because a loop cuts
    # the drains of the waves that straddle its ends.
    breakers = np.zeros(n)
    t = 1.0
    while t < loop_s + 2.0:
        length = rng.uniform(1.6, 3.4)
        start = int(t * SR)
        count = int(length * SR)
        if start + count >= n:
            break
        k = np.arange(count) / SR
        rise = np.clip(k / rng.uniform(0.08, 0.25), 0.0, 1.0) ** 2
        drain = np.exp(-k / rng.uniform(0.55, 1.25))
        env = rise * drain
        hiss = band(rng.normal(0.0, 1.0, count),
                    rng.uniform(240.0, 480.0), rng.uniform(1400.0, 2600.0))
        breakers[start:start + count] += hiss * env * rng.uniform(0.35, 1.0)
        t += rng.uniform(2.2, 5.2)

    x = body * 1.35 + breakers * 0.40
    # Roll the top off HARD. Measured on the first attempt: spectral centroid
    # 4181 Hz, which is a hiss, not a sea — surf heard from three hundred
    # metres up has had its sparkle absorbed by the air long before it
    # arrives, and that sparkle is most of what made the old bed read as a
    # noise generator.
    x = one_pole_lp(x, 1500.0)
    return seamless(x, loop_s)


# ---------------------------------------------------------------------------
# the wind
# ---------------------------------------------------------------------------

def wind(loop_s=26.0):
    n = int((loop_s + 3.0) * SR)
    gust = 0.5 + 0.5 * np.clip(0.6 * lfo(n, 9.1) + 0.4 * lfo(n, 13.9, 0.4), -1, 1)
    # Same correction as the sea: the first attempt measured a 5123 Hz
    # centroid, which is static rather than weather. Open-country wind is
    # felt low and heard as pressure, not as hiss.
    cutoff = 140.0 + gust * 520.0
    x = one_pole_lp(rng.normal(0.0, 1.0, n), cutoff) * (0.35 + 0.65 * gust)
    # A faint resonance reads as wind moving past something rather than as a
    # filter sweep on noise.
    x += band(rng.normal(0.0, 1.0, n), 300.0, 420.0) * gust * 0.22
    x = one_pole_lp(x, 1100.0)
    return seamless(x, loop_s)


# ---------------------------------------------------------------------------
# instruments for the music
# ---------------------------------------------------------------------------

def pluck(freq, seconds, brightness=0.5, damping=0.996):
    """Karplus-Strong. A plucked, gut-strung sound — the closest thing to a
    folk instrument you can get out of a delay line and some noise."""
    count = int(seconds * SR)
    delay = max(2, int(SR / freq))
    buf = rng.normal(0.0, 1.0, delay)
    buf = one_pole_lp(buf, 1200.0 + brightness * 6000.0)
    out = np.empty(count)
    idx = 0
    prev = 0.0
    for i in range(count):
        v = buf[idx]
        nxt = buf[(idx + 1) % delay]
        filtered = (v + nxt) * 0.5 * damping
        buf[idx] = filtered
        out[i] = v
        prev = v
        idx = (idx + 1) % delay
    env = np.exp(-np.arange(count) / (SR * seconds * 0.42))
    return out * env


def bowed(freq, seconds, detune=0.004, harmonics=6):
    """A slow, breathing drone. Two slightly detuned stacks beating against
    each other, which is what stops a synthesised fifth sounding like a
    test tone."""
    count = int(seconds * SR)
    t = np.arange(count) / SR
    out = np.zeros(count)
    for h in range(1, harmonics + 1):
        amp = 1.0 / (h ** 1.6)
        vib = 1.0 + 0.0018 * np.sin(2.0 * math.pi * (0.19 + 0.03 * h) * t)
        out += amp * np.sin(2.0 * math.pi * freq * h * t * vib)
        out += amp * np.sin(2.0 * math.pi * freq * (1.0 + detune) * h * t)
    attack = np.clip(t / 3.5, 0.0, 1.0)
    release = np.clip((seconds - t) / 3.5, 0.0, 1.0)
    return out * attack * release


def note(name_semitones_from_a, octave_shift=0.0):
    """A4 = 440 Hz."""
    return 440.0 * (2.0 ** ((name_semitones_from_a + 12.0 * octave_shift) / 12.0))


# D Dorian, relative to A4 in semitones. Dorian is the mode most northern
# and eastern European folk music sits in — minor-coloured but with a raised
# sixth, so it is melancholy without being funereal. It is also the reason
# these two layers can crossfade: both are built on the same D.
D_DORIAN = [-19, -17, -16, -14, -12, -10, -9, -7, -5, -4, -2, 0, 2, 3]


# ---------------------------------------------------------------------------
# music: the mercy layer
# ---------------------------------------------------------------------------

def music_prayer(loop_s=48.0):
    n = int((loop_s + 3.0) * SR)
    out = np.zeros(n)

    # Drone: an open fifth, D and A, the way a bowed folk drone sits under
    # everything without ever asking to be listened to.
    for f, gain in ((note(-19), 0.55), (note(-12), 0.34)):
        d = bowed(f, (loop_s + 3.0), detune=0.0035)
        out[:len(d)] += d * gain

    # A slow breath over the whole bed so it swells rather than sits.
    out *= 0.72 + 0.28 * (0.5 + 0.5 * lfo(n, 19.3))

    # Sparse melody. Long gaps on purpose: this plays for forty minutes behind
    # a strategy game, and anything busier becomes something to switch off.
    t = 2.0
    prev = 5
    while t < loop_s + 1.0:
        # Small steps, occasional leap — a melody that mostly walks is what
        # makes a random note sequence sound sung rather than generated.
        step = int(rng.choice([-2, -1, -1, 1, 1, 2, 3], p=[.1, .25, .15, .25, .1, .1, .05]))
        prev = int(np.clip(prev + step, 2, len(D_DORIAN) - 1))
        f = note(D_DORIAN[prev])
        dur = float(rng.choice([2.2, 3.0, 4.5]))
        p = pluck(f, dur, brightness=0.42)
        s = int(t * SR)
        if s + len(p) < n:
            out[s:s + len(p)] += p * rng.uniform(0.16, 0.27)
            # A soft octave shadow every few notes: one voice answering.
            if rng.random() < 0.3:
                q = pluck(f * 2.0, dur * 0.7, brightness=0.3)
                s2 = s + int(rng.uniform(0.28, 0.5) * SR)
                if s2 + len(q) < n:
                    out[s2:s2 + len(q)] += q * 0.09
        t += dur * rng.uniform(0.9, 1.7) + rng.uniform(0.6, 2.4)

    out = one_pole_lp(out, 6000.0)
    return seamless(out, loop_s, fade_seconds=3.0)


# ---------------------------------------------------------------------------
# music: the cruelty layer
# ---------------------------------------------------------------------------

def music_infernal(loop_s=48.0):
    """Same D, an octave down, with the sixth flattened and a semitone rub.

    Built on the same tonal centre as the mercy layer deliberately: the game
    crossfades between them continuously as Naklon drifts, and two beds in
    unrelated keys would grind against each other through the whole middle of
    the range — which is most of the game.
    """
    n = int((loop_s + 3.0) * SR)
    out = np.zeros(n)

    for f, gain in ((note(-31), 0.62), (note(-24), 0.30), (note(-23), 0.12)):
        d = bowed(f, (loop_s + 3.0), detune=0.006, harmonics=8)
        out[:len(d)] += d * gain

    out *= 0.6 + 0.4 * (0.5 + 0.5 * lfo(n, 23.7))

    # Struck low string, rare and heavy.
    t = 4.0
    while t < loop_s:
        f = note(float(rng.choice([-31, -29, -28, -24])))
        p = pluck(f, 6.0, brightness=0.18, damping=0.9975)
        s = int(t * SR)
        if s + len(p) < n:
            out[s:s + len(p)] += p * rng.uniform(0.18, 0.3)
        t += rng.uniform(6.0, 11.0)

    # A breath of noise underneath — not audible as noise, only as weight.
    out += one_pole_lp(brown(n), 120.0) * 0.22
    out = one_pole_lp(out, 3800.0)
    return seamless(out, loop_s, fade_seconds=3.0)


# ---------------------------------------------------------------------------
# cues — the audit's "no audio confirmation" finding
# ---------------------------------------------------------------------------

def cue_landed():
    """A rite landed on a village. Warm, rising, over quickly."""
    seconds = 1.5
    out = np.zeros(int(seconds * SR))
    for i, semi in enumerate([-7, 0, 5]):
        p = pluck(note(semi), 1.4 - i * 0.15, brightness=0.6)
        s = int(i * 0.075 * SR)
        out[s:s + len(p)] += p * (0.6 - i * 0.12)
    return out


def cue_refused():
    """Out of reach. Falling, dull, no sparkle — it must not be mistakable
    for the sound above, because telling those two apart is the whole point.
    """
    seconds = 1.1
    out = np.zeros(int(seconds * SR))
    for i, semi in enumerate([-2, -9]):
        p = pluck(note(semi), 0.9, brightness=0.12, damping=0.985)
        s = int(i * 0.13 * SR)
        out[s:s + len(p)] += p * (0.5 - i * 0.15)
    return one_pole_lp(out, 900.0)


def cue_tired():
    """The village has heard enough of that rite. Muffled version of the
    landing cue: the player DID everything right, it simply did not land
    hard, and the sound should say that rather than sounding like failure."""
    out = cue_landed()
    return one_pole_lp(out, 1400.0) * 0.55


def cue_reclaimed():
    """Her grip broke. The only triumphant sound in the game."""
    seconds = 3.0
    out = np.zeros(int(seconds * SR))
    for i, semi in enumerate([-19, -12, -7, -5, 0, 5]):
        p = pluck(note(semi), 2.6 - i * 0.15, brightness=0.55)
        s = int(i * 0.11 * SR)
        out[s:s + len(p)] += p * (0.5 - i * 0.05)
    d = bowed(note(-19), seconds, detune=0.003, harmonics=5)
    return out + d * 0.25


# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_wav("sea_swell.wav", sea())
    write_wav("wind_bed.wav", wind())
    write_wav("music_prayer.wav", music_prayer())
    write_wav("music_infernal.wav", music_infernal())
    write_wav("cue_rite_landed.wav", cue_landed())
    write_wav("cue_rite_refused.wav", cue_refused())
    write_wav("cue_rite_tired.wav", cue_tired())
    write_wav("cue_village_reclaimed.wav", cue_reclaimed())


if __name__ == "__main__":
    main()
