#!/usr/bin/env python3
"""Synthesise Airline Empire's sound palette from first principles.

Run:  python3 scripts/audio/generate.py

Why a generator rather than files
---------------------------------
Every asset this writes is original: it is arithmetic, not a recording and
not a sample library, so there is no licence to track and nothing that could
belong to anyone else (docs/AUDIO_ASSETS.md).  Checking in the generator as
well as its output means the palette can be re-voiced by editing a number
here rather than by finding whoever made the files.

What this is not
----------------
This is not the work of a sound designer.  It is a coherent, deliberately
restrained synthesis palette built to the briefs in docs/AUDIO_ASSETS.md, and
it is a real, shippable first voice for the game — but a professional pass
would replace most of it.  Nobody has heard any of it; see §32 of the phase
report.

Design rules, applied to every asset here
-----------------------------------------
*  No sound starts at full amplitude.  Every envelope has an attack, because
   an instantaneous edge is what makes cheap game audio sound cheap.
*  Nothing is bright for the sake of being heard.  The palette is centred on
   200-2000 Hz with air above rather than sizzle.
*  Tuning is consistent: one pitch set across the whole game, so unrelated
   sounds still sound like the same product.
*  Every one-shot ends in silence, so overlaps never click.
"""

import math
import os
import struct
import wave

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "..", "AirlineEmpireApp", "Resources", "Audio")

# One pitch set for the entire game. A minor-pentatonic-ish collection on D:
# calm, slightly serious, and it never resolves too sweetly — which is what
# keeps a strategy game from sounding like a puzzle game.
D3, F3, G3, A3, C4, D4, F4, G4, A4, C5, D5, F5, A5 = (
    146.83, 174.61, 196.00, 220.00, 261.63, 293.66,
    349.23, 392.00, 440.00, 523.25, 587.33, 698.46, 880.00)


# ---------------------------------------------------------------- primitives

def silence(duration):
    return [0.0] * int(RATE * duration)


def _mix_into(buf, samples, at=0.0, gain=1.0):
    start = int(RATE * at)
    if start + len(samples) > len(buf):
        buf.extend([0.0] * (start + len(samples) - len(buf)))
    for i, s in enumerate(samples):
        buf[start + i] += s * gain
    return buf


def env_ad(n, attack, decay, curve=2.2):
    """Attack-decay envelope. `curve` above 1 gives a natural, non-linear tail."""
    a = max(1, int(RATE * attack))
    out = []
    for i in range(n):
        if i < a:
            # Raised cosine attack: no corner, therefore no click.
            v = 0.5 - 0.5 * math.cos(math.pi * i / a)
        else:
            t = (i - a) / max(1.0, RATE * decay)
            v = math.exp(-curve * t)
        out.append(v)
    return out


def tone(freq, duration, attack=0.004, decay=None, harmonics=(1.0, 0.0, 0.0),
         detune=0.0, drift=0.0):
    """A sine stack. `harmonics` are the relative levels of 1st/2nd/3rd partial.

    `drift` bends the pitch over the sound's life (positive = rising), which is
    what turns a beep into something that feels like it is going somewhere.
    """
    n = int(RATE * duration)
    decay = duration * 0.6 if decay is None else decay
    e = env_ad(n, attack, decay)
    out = []
    phase = [0.0, 0.0, 0.0]
    for i in range(n):
        t = i / n
        f = freq * (1.0 + drift * t)
        s = 0.0
        for h, level in enumerate(harmonics, start=1):
            if level == 0.0:
                continue
            phase[h - 1] += 2 * math.pi * f * h / RATE
            s += level * math.sin(phase[h - 1])
            if detune:
                s += level * 0.5 * math.sin(phase[h - 1] * (1 + detune))
        out.append(s * e[i])
    return out


def noise(duration, seed=1):
    """Deterministic white noise — a tiny LCG, so a rebuild is byte-identical."""
    n = int(RATE * duration)
    out = []
    state = seed * 2654435761 % (2 ** 32)
    for _ in range(n):
        state = (1103515245 * state + 12345) % (2 ** 31)
        out.append((state / (2 ** 30)) - 1.0)
    return out


def lowpass(samples, cutoff):
    """One-pole low-pass. Cheap, and the right character: gentle, no ringing."""
    if cutoff >= RATE / 2:
        return list(samples)
    a = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    lp = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, lp)]


def bandsweep(duration, f_from, f_to, seed=1, attack=0.05, decay=None,
              resonance=0.55):
    """Filtered noise whose passband travels — the spool of a turbine, the
    rush of air over a wing. This is the palette's aviation signature and it
    is used sparingly, because it stops meaning anything if everything has it.
    """
    n = int(RATE * duration)
    src = noise(duration, seed)
    decay = duration * 0.5 if decay is None else decay
    e = env_ad(n, attack, decay, curve=1.6)
    # A swept two-pole band-pass, integrated by hand so the cutoff can move
    # per sample without rebuilding a filter.
    out, lp1, lp2 = [], 0.0, 0.0
    for i in range(n):
        t = i / n
        f = f_from * ((f_to / f_from) ** t)
        a = 1.0 - math.exp(-2 * math.pi * f / RATE)
        lp1 += a * (src[i] - lp1)
        lp2 += a * (lp1 - lp2)
        band = lp1 - lp2
        out.append(band * e[i] * (1.0 + resonance))
    return out


def chord(freqs, duration, spread=0.0, **kw):
    """Several tones, optionally arpeggiated by `spread` seconds each."""
    buf = []
    for i, f in enumerate(freqs):
        _mix_into(buf, tone(f, duration - i * spread, **kw), at=i * spread,
                  gain=1.0 / max(1, len(freqs)) ** 0.6)
    return buf


def thump(freq, duration, seed=3):
    """A soft low impact: a pitch-dropping sine plus a dab of muffled noise.
    Aircraft-sized rather than drum-sized — no attack transient, all body.
    """
    body = tone(freq, duration, attack=0.006, decay=duration * 0.35,
                harmonics=(1.0, 0.12, 0.0), drift=-0.45)
    air = lowpass(noise(duration * 0.5, seed), 420)
    e = env_ad(len(air), 0.004, duration * 0.16)
    air = [s * v for s, v in zip(air, e)]
    buf = list(body)
    _mix_into(buf, air, gain=0.35)
    return buf


def normalise(samples, peak=0.7):
    m = max((abs(s) for s in samples), default=0.0)
    if m == 0:
        return samples
    g = peak / m
    return [s * g for s in samples]


def fade_edges(samples, fade=0.006):
    """Guarantees the file starts and ends at zero. Prevents the click that
    makes an otherwise fine sound feel like a cheap one."""
    n = int(RATE * fade)
    out = list(samples)
    for i in range(min(n, len(out))):
        v = 0.5 - 0.5 * math.cos(math.pi * i / n)
        out[i] *= v
        out[-1 - i] *= v
    return out


def loopable(samples, crossfade=0.75):
    """Wraps the tail of a buffer over its head so the file loops seamlessly.
    Used only for ambience, where an audible seam every few seconds would be
    the single most irritating thing in the game."""
    n = int(RATE * crossfade)
    out = list(samples)
    if n * 2 >= len(out):
        return out
    tail = out[-n:]
    del out[-n:]
    for i in range(n):
        v = i / n
        out[i] = out[i] * v + tail[i] * (1 - v)
    return out


def write(name, samples, peak=0.7):
    samples = fade_edges(normalise(samples, peak))
    path = os.path.join(ROOT, name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    return path, len(samples) / RATE


# ------------------------------------------------------------------- palette
# Peaks are deliberately unequal: this is where the mix is decided, and a UI
# blip that measures as loud as an era change would flatten the whole game.

ASSETS = {}


def asset(name, samples, peak):
    ASSETS[name] = (samples, peak)


# --- Interface. Tiny, dark, and quieter than anything else in the game. -----

asset("ui_select", tone(A4, 0.06, attack=0.002, decay=0.035,
                        harmonics=(1.0, 0.05, 0.0)), 0.16)

asset("ui_navigate", tone(G4, 0.075, attack=0.003, decay=0.045,
                          harmonics=(1.0, 0.08, 0.0), drift=0.05), 0.15)

asset("ui_toggle", tone(D5, 0.05, attack=0.002, decay=0.03), 0.14)

# Confirm rises a fifth; cancel falls one. The pair is the smallest possible
# grammar and the player learns it without being told.
_c = []
_mix_into(_c, tone(D4, 0.10, attack=0.003, decay=0.06), 0.0, 0.8)
_mix_into(_c, tone(A4, 0.16, attack=0.004, decay=0.10,
                   harmonics=(1.0, 0.18, 0.04)), 0.055, 0.9)
asset("ui_confirm", _c, 0.34)

_x = []
_mix_into(_x, tone(A4, 0.09, attack=0.003, decay=0.05), 0.0, 0.8)
_mix_into(_x, tone(F4, 0.14, attack=0.004, decay=0.09), 0.05, 0.85)
asset("ui_cancel", _x, 0.26)

# Sheets breathe rather than click.
asset("ui_sheet_open",
      lowpass(bandsweep(0.26, 300, 1700, seed=11, attack=0.03), 3200), 0.20)
asset("ui_sheet_close",
      lowpass(bandsweep(0.22, 1500, 320, seed=12, attack=0.02), 2600), 0.17)

# An error is low and soft, never a buzzer. It says "that is not available",
# not "you fool".
_e = []
_mix_into(_e, tone(F3, 0.13, attack=0.004, decay=0.07,
                   harmonics=(1.0, 0.22, 0.05)), 0.0, 1.0)
_mix_into(_e, tone(F3 * 0.945, 0.17, attack=0.005, decay=0.10,
                   harmonics=(1.0, 0.18, 0.04)), 0.075, 0.9)
asset("ui_error", _e, 0.32)

# --- Fleet ------------------------------------------------------------------

_ord = []
_mix_into(_ord, tone(D4, 0.20, attack=0.008, decay=0.12,
                     harmonics=(1.0, 0.15, 0.03)), 0.0, 0.8)
_mix_into(_ord, lowpass(bandsweep(0.35, 700, 260, seed=21, attack=0.04), 2400),
          0.04, 0.5)
asset("aircraft_ordered", _ord, 0.36)

# Delivery is the second most expensive thing a player does. Sub-weight,
# then a slow metallic bloom: an object of mass has arrived.
_del = []
_mix_into(_del, thump(D3 * 0.75, 0.55, seed=22), 0.0, 1.0)
_mix_into(_del, chord([D4, A4, D5], 0.85, spread=0.045, attack=0.02,
                      decay=0.42, harmonics=(1.0, 0.2, 0.07)), 0.07, 0.55)
_mix_into(_del, highpass(bandsweep(0.9, 900, 2600, seed=23, attack=0.12), 700),
          0.05, 0.16)
asset("aircraft_delivered", _del, 0.62)

_sold = []
_mix_into(_sold, tone(A3, 0.28, attack=0.01, decay=0.18,
                      harmonics=(1.0, 0.12, 0.0), drift=-0.08), 0.0, 0.9)
_mix_into(_sold, lowpass(bandsweep(0.4, 1200, 280, seed=24, attack=0.05), 2000),
          0.02, 0.4)
asset("aircraft_sold", _sold, 0.34)

asset("lease_returned",
      lowpass(bandsweep(0.45, 900, 240, seed=25, attack=0.06), 1800), 0.28)

# Assignment is a latch closing: two short bodies, very close together.
_asg = []
_mix_into(_asg, thump(A3, 0.16, seed=26), 0.0, 0.7)
_mix_into(_asg, tone(D5, 0.12, attack=0.003, decay=0.07,
                     harmonics=(1.0, 0.2, 0.06)), 0.045, 0.55)
asset("aircraft_assigned", _asg, 0.40)

_uasg = []
_mix_into(_uasg, tone(D5, 0.10, attack=0.003, decay=0.06), 0.0, 0.5)
_mix_into(_uasg, thump(G3, 0.18, seed=27), 0.04, 0.6)
asset("aircraft_unassigned", _uasg, 0.26)

asset("maintenance_started",
      lowpass(bandsweep(0.5, 380, 900, seed=28, attack=0.09), 1800), 0.22)
asset("maintenance_completed",
      chord([G4, D5], 0.34, spread=0.05, attack=0.008, decay=0.18), 0.26)

# --- Routes -----------------------------------------------------------------

# The signature sound of the game. A rising three-note figure over a swept
# band of air: a line has been drawn between two cities.
_route = []
_mix_into(_route, chord([D4, A4, D5], 0.75, spread=0.075, attack=0.010,
                        decay=0.34, harmonics=(1.0, 0.22, 0.06)), 0.0, 1.0)
_mix_into(_route, bandsweep(0.85, 420, 2400, seed=31, attack=0.10), 0.0, 0.30)
_mix_into(_route, thump(D3, 0.35, seed=32), 0.0, 0.30)
asset("route_opened", _route, 0.58)

_close = []
_mix_into(_close, chord([D5, A4, F4], 0.55, spread=0.065, attack=0.008,
                        decay=0.26), 0.0, 0.9)
_mix_into(_close, lowpass(bandsweep(0.5, 1600, 340, seed=33, attack=0.05), 2200),
          0.0, 0.28)
asset("route_closed", _close, 0.34)

# --- Flights. The quietest family in the game: they happen constantly. ------

asset("flight_departed",
      highpass(bandsweep(0.5, 260, 1500, seed=41, attack=0.10,
                         resonance=0.35), 220), 0.20)
asset("flight_arrived",
      lowpass(bandsweep(0.45, 1300, 320, seed=42, attack=0.06,
                        resonance=0.35), 2400), 0.19)

_delay = []
_mix_into(_delay, tone(G3, 0.22, attack=0.012, decay=0.13,
                       harmonics=(1.0, 0.16, 0.0)), 0.0, 0.9)
_mix_into(_delay, tone(F3, 0.26, attack=0.014, decay=0.16), 0.10, 0.7)
asset("flight_delayed", _delay, 0.26)

_cancel = []
_mix_into(_cancel, thump(D3 * 0.85, 0.34, seed=43), 0.0, 1.0)
_mix_into(_cancel, tone(F3, 0.28, attack=0.01, decay=0.16,
                        harmonics=(1.0, 0.24, 0.06), drift=-0.10), 0.02, 0.6)
asset("flight_cancelled", _cancel, 0.34)

# The flurries: one sound for a whole busy minute of the network. Wider and
# softer than the individual events they replace, so fast-forward reads as
# activity rather than as a list.
asset("departure_flurry",
      highpass(bandsweep(0.95, 240, 1800, seed=44, attack=0.22,
                         resonance=0.25), 200), 0.26)
asset("arrival_flurry",
      lowpass(bandsweep(0.9, 1500, 300, seed=45, attack=0.18,
                        resonance=0.25), 2600), 0.24)

_disrupt = []
_mix_into(_disrupt, lowpass(noise(0.7, 46), 300), 0.0, 0.5)
_mix_into(_disrupt, tone(F3, 0.5, attack=0.05, decay=0.3,
                         harmonics=(1.0, 0.3, 0.1), drift=-0.06), 0.0, 0.8)
asset("disruption_flurry", _disrupt, 0.36)

# --- The first times. The only sounds allowed to be beautiful. --------------

_first_route = []
_mix_into(_first_route, chord([D4, F4, A4, D5], 1.5, spread=0.10, attack=0.02,
                              decay=0.75, harmonics=(1.0, 0.24, 0.09)), 0.0, 1.0)
_mix_into(_first_route, bandsweep(1.7, 350, 3000, seed=51, attack=0.28), 0.0, 0.28)
_mix_into(_first_route, thump(D3, 0.7, seed=52), 0.0, 0.35)
asset("first_route", _first_route, 0.68)

# A departure: air building under something heavy, then release.
_first_dep = []
_mix_into(_first_dep, bandsweep(1.9, 180, 2200, seed=53, attack=0.55,
                                resonance=0.45), 0.0, 0.75)
_mix_into(_first_dep, tone(D3, 1.5, attack=0.35, decay=0.75,
                           harmonics=(1.0, 0.3, 0.10), drift=0.10), 0.0, 0.55)
_mix_into(_first_dep, chord([D4, A4], 1.1, spread=0.12, attack=0.10,
                            decay=0.55), 0.55, 0.40)
asset("first_departure", _first_dep, 0.72)

# An arrival: the same air, travelling the other way, landing on a resolve.
_first_arr = []
_mix_into(_first_arr, lowpass(bandsweep(1.5, 2000, 300, seed=54, attack=0.20,
                                        resonance=0.40), 3000), 0.0, 0.65)
_mix_into(_first_arr, thump(D3, 0.8, seed=55), 0.72, 0.7)
_mix_into(_first_arr, chord([D4, A4, D5], 1.4, spread=0.09, attack=0.05,
                            decay=0.70, harmonics=(1.0, 0.20, 0.06)), 0.74, 0.75)
asset("first_arrival", _first_arr, 0.74)

# The first money: warm, major, and the only unambiguously happy sound here.
_first_rev = []
_mix_into(_first_rev, chord([D4, F4 * 1.0595, A4, D5], 1.6, spread=0.085,
                            attack=0.025, decay=0.80,
                            harmonics=(1.0, 0.26, 0.10)), 0.0, 1.0)
_mix_into(_first_rev, tone(D3, 1.3, attack=0.10, decay=0.65), 0.0, 0.45)
_mix_into(_first_rev, highpass(bandsweep(1.5, 1400, 4200, seed=56,
                                         attack=0.35), 1100), 0.10, 0.16)
asset("first_revenue", _first_rev, 0.70)

# --- Money ------------------------------------------------------------------

_profit = []
_mix_into(_profit, chord([D4, A4], 0.6, spread=0.06, attack=0.012,
                         decay=0.30, harmonics=(1.0, 0.18, 0.05)), 0.0, 1.0)
_mix_into(_profit, tone(D3, 0.5, attack=0.03, decay=0.25), 0.0, 0.4)
asset("month_profit", _profit, 0.42)

_loss = []
_mix_into(_loss, chord([D4, F4], 0.65, spread=0.06, attack=0.014,
                       decay=0.34), 0.0, 0.9)
_mix_into(_loss, tone(D3 * 0.94, 0.6, attack=0.04, decay=0.30,
                      drift=-0.05), 0.0, 0.5)
asset("month_loss", _loss, 0.40)

_loan = []
_mix_into(_loan, thump(D3, 0.45, seed=61), 0.0, 1.0)
_mix_into(_loan, tone(A3, 0.4, attack=0.02, decay=0.22,
                      harmonics=(1.0, 0.2, 0.05)), 0.05, 0.5)
asset("loan_taken", _loan, 0.44)

asset("loan_repaid",
      chord([A3, D4, A4], 0.55, spread=0.06, attack=0.012, decay=0.28), 0.38)

# --- World. Each one has a different physical character on purpose. --------

asset("world_forecast",
      lowpass(bandsweep(0.7, 500, 1200, seed=71, attack=0.16), 2200), 0.24)

# Storm: broad, moving, wet.
_storm = []
_mix_into(_storm, lowpass(noise(1.5, 72), 700), 0.0, 0.55)
_mix_into(_storm, bandsweep(1.5, 900, 200, seed=73, attack=0.30), 0.0, 0.6)
_mix_into(_storm, tone(D3 * 0.9, 1.2, attack=0.20, decay=0.6, drift=-0.05),
          0.05, 0.5)
asset("world_storm", _storm, 0.44)

# Strike: mechanical, repeating, human. Three even pulses.
_strike = []
for k in range(3):
    _mix_into(_strike, tone(G3, 0.24, attack=0.008, decay=0.12,
                            harmonics=(1.0, 0.3, 0.12)), 0.20 * k, 0.9)
asset("world_strike", _strike, 0.40)

# Fuel shock: a price moving the wrong way. One long unstable slide.
_fuel = []
_mix_into(_fuel, tone(A3, 1.1, attack=0.06, decay=0.55,
                      harmonics=(1.0, 0.35, 0.14), drift=0.16), 0.0, 1.0)
_mix_into(_fuel, tone(A3 * 1.06, 1.1, attack=0.08, decay=0.55, drift=0.14),
          0.0, 0.55)
asset("world_fuel_shock", _fuel, 0.44)

# Boom: the one world event that is good news.
_boom = []
_mix_into(_boom, chord([D4, A4, D5, F5], 1.0, spread=0.06, attack=0.02,
                       decay=0.50, harmonics=(1.0, 0.2, 0.07)), 0.0, 1.0)
_mix_into(_boom, highpass(bandsweep(1.1, 1200, 3600, seed=74, attack=0.25), 900),
          0.0, 0.18)
asset("world_boom", _boom, 0.46)

# An airport closing: a door, not an alarm.
_closed = []
_mix_into(_closed, thump(D3 * 0.8, 0.6, seed=75), 0.0, 1.0)
_mix_into(_closed, lowpass(bandsweep(0.55, 1400, 260, seed=76, attack=0.04), 1600),
          0.0, 0.45)
asset("world_airport_closed", _closed, 0.46)

asset("world_event_ended",
      chord([A3, D4], 0.45, spread=0.05, attack=0.02, decay=0.24), 0.22)

# --- Progression ------------------------------------------------------------

asset("mission_offered",
      chord([A4, D5], 0.35, spread=0.05, attack=0.008, decay=0.18), 0.24)

_mission = []
_mix_into(_mission, chord([D4, A4, D5], 0.9, spread=0.07, attack=0.012,
                          decay=0.45, harmonics=(1.0, 0.22, 0.08)), 0.0, 1.0)
_mix_into(_mission, tone(D3, 0.7, attack=0.03, decay=0.35), 0.0, 0.4)
asset("mission_completed", _mission, 0.52)

asset("mission_expired",
      chord([D4, C4], 0.5, spread=0.07, attack=0.02, decay=0.26), 0.22)

_milestone = []
_mix_into(_milestone, chord([G3, D4, G4], 0.85, spread=0.06, attack=0.012,
                            decay=0.42), 0.0, 1.0)
_mix_into(_milestone, highpass(bandsweep(0.9, 1500, 3800, seed=81, attack=0.20),
                               1200), 0.0, 0.14)
asset("milestone", _milestone, 0.50)

_achieve = []
_mix_into(_achieve, chord([D4, A4, D5, A5], 1.1, spread=0.055, attack=0.012,
                          decay=0.55, harmonics=(1.0, 0.22, 0.08)), 0.0, 1.0)
asset("achievement", _achieve, 0.52)

_capability = []
_mix_into(_capability, thump(D3, 0.5, seed=82), 0.0, 0.8)
_mix_into(_capability, chord([A3, D4, A4], 0.8, spread=0.06, attack=0.02,
                             decay=0.40), 0.05, 0.8)
asset("capability_completed", _capability, 0.48)

# An era change is the largest thing that happens to an airline. It is the
# only asset here allowed to be cinematic, and the only one over two seconds.
_era = []
_mix_into(_era, tone(D3 * 0.5, 2.6, attack=0.55, decay=1.3,
                     harmonics=(1.0, 0.30, 0.12)), 0.0, 0.85)
_mix_into(_era, chord([D4, A4, D5], 2.2, spread=0.14, attack=0.12,
                      decay=1.1, harmonics=(1.0, 0.24, 0.09)), 0.30, 0.75)
_mix_into(_era, bandsweep(2.6, 300, 4000, seed=91, attack=0.90), 0.0, 0.26)
_mix_into(_era, chord([D5, A5], 1.6, spread=0.10, attack=0.30, decay=0.8),
          0.95, 0.30)
asset("era_advanced", _era, 0.80)

# --- The end. Sophisticated, never a jump-scare. ----------------------------

# Administration: a slow, low, unresolved pulse. Urgent by repetition rather
# than by volume.
_admin = []
for k in range(3):
    _mix_into(_admin, tone(F3, 0.55, attack=0.05, decay=0.28,
                           harmonics=(1.0, 0.28, 0.10)), 0.42 * k, 1.0)
    _mix_into(_admin, tone(F3 * 0.943, 0.55, attack=0.06, decay=0.28),
              0.42 * k, 0.6)
asset("administration", _admin, 0.60)

_collapse = []
_mix_into(_collapse, tone(D3 * 0.5, 2.2, attack=0.10, decay=1.1,
                          harmonics=(1.0, 0.35, 0.15), drift=-0.16), 0.0, 1.0)
_mix_into(_collapse, lowpass(noise(2.0, 92), 500), 0.0, 0.30)
asset("collapse", _collapse, 0.66)

_over = []
_mix_into(_over, tone(D3 * 0.5, 3.0, attack=0.30, decay=1.5,
                      harmonics=(1.0, 0.28, 0.10), drift=-0.10), 0.0, 1.0)
_mix_into(_over, chord([D4, F4], 2.2, spread=0.20, attack=0.30, decay=1.1),
          0.45, 0.45)
asset("game_over", _over, 0.62)

# --- Ambience. Loops. Very quiet by construction as well as by mixer. ------

# Operations room: filtered air, a slow breathing swell, no identifiable
# events. It must survive being heard for an hour.
_amb_ops = lowpass(noise(9.0, 101), 380)
_amb_ops = [s * (1.0 + 0.35 * math.sin(2 * math.pi * i / (RATE * 4.5)))
            for i, s in enumerate(_amb_ops)]
_mix_into(_amb_ops, tone(D3 * 0.5, 9.0, attack=2.0, decay=9.0), 0.0, 0.10)
asset("ambience_operations", loopable(_amb_ops), 0.30)

# The world: wider, airier, a touch of altitude.
_amb_world = lowpass(noise(11.0, 102), 620)
_amb_world = [s * (1.0 + 0.30 * math.sin(2 * math.pi * i / (RATE * 6.5)))
              for i, s in enumerate(_amb_world)]
_mix_into(_amb_world, tone(A3 * 0.5, 11.0, attack=3.0, decay=11.0), 0.0, 0.07)
asset("ambience_world", loopable(_amb_world), 0.26)


if __name__ == "__main__":
    total = 0
    print(f"{'asset':28} {'seconds':>8} {'kB':>7}")
    for name in sorted(ASSETS):
        samples, peak = ASSETS[name]
        path, dur = write(name, samples, peak)
        size = os.path.getsize(path)
        total += size
        print(f"{name:28} {dur:8.2f} {size / 1024:7.0f}")
    print(f"{'':28} {'':>8} {'-' * 7}")
    print(f"{len(ASSETS)} assets{'':17} {total / 1024:7.0f} kB")
