#!/usr/bin/env python3
"""Fails when a sound cue has no file, or a file has no cue.

A missing audio asset is the one bug an audio system cannot report: nothing
throws, nothing logs, the moment simply passes in silence and the player
assumes the game has none. So it is checked mechanically, in CI, against
Core's own `AudioCue.assetName` — which is why that mapping lives in Core
rather than being written out again in the app.

Run:  python3 scripts/audio/check-assets.py
"""

import os
import re
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SWIFT = os.path.join(REPO, "AirlineEmpireCore", "Sources", "AirlineEmpireCore",
                     "Session", "AudioDirection.swift")
AUDIO = os.path.join(REPO, "AirlineEmpireApp", "Resources", "Audio")

# Peak ceiling. Nothing may be mastered hotter than this: the mixer trims per
# category at runtime, but an asset that is already at full scale cannot be
# made to sit under anything.
MAX_PEAK = 0.85
# Anything longer than this is not a game sound, it is a cue the player has to
# wait through. The one deliberate exception is ambience, which loops.
MAX_ONESHOT_SECONDS = 3.5


def cue_asset_names():
    """Every `case .x: return "y"` inside AudioCue.assetName."""
    source = open(SWIFT).read()
    start = source.index("public var assetName: String {")
    end = source.index("\n    }", start)
    body = source[start:end]
    return dict(re.findall(r'case \.(\w+): return "([\w]+)"', body))


def declared_cues():
    """Every case of the AudioCue enum, so a cue cannot be added without a
    branch in assetName (Swift already enforces that, but this keeps the two
    counts visible in the failure message)."""
    source = open(SWIFT).read()
    start = source.index("public enum AudioCue: String")
    end = source.index("public var category: AudioCategory", start)
    body = source[start:end]
    return set(re.findall(r"^\s+case (\w+)$", body, re.M))


def _music_assets_named_in_swift():
    """Track names from `MusicDirector.asset(for:)`, so a state added without
    a bed fails here rather than playing silence at a player."""
    path = os.path.join(REPO, "AirlineEmpireCore", "Sources", "AirlineEmpireCore",
                        "Session", "SoundscapeDirection.swift")
    source = open(path).read()
    start = source.index("public static func asset(for state: MusicState)")
    end = source.index("\n    }", start)
    return set(re.findall(r'return "([\w]+)"', source[start:end]))


def main():
    names = cue_asset_names()
    cues = declared_cues()
    problems = []

    missing_branch = cues - set(names)
    if missing_branch:
        problems.append(f"cues with no assetName branch: {sorted(missing_branch)}")

    all_files = {f[:-4] for f in os.listdir(AUDIO) if f.endswith(".wav")}
    # Music is addressed by `MusicDirector.asset(for:)` rather than by an
    # `AudioCue`, so it is checked for format and level but not for a cue.
    music = {f for f in all_files if f.startswith("music_")}
    files = all_files - music

    for cue, asset in sorted(names.items()):
        if asset not in files:
            problems.append(f"{cue}: no such asset '{asset}.wav'")

    orphans = files - set(names.values())
    if orphans:
        problems.append(f"assets no cue plays: {sorted(orphans)}")

    duplicates = [a for a in set(names.values())
                  if list(names.values()).count(a) > 1]
    if duplicates:
        problems.append(f"assets shared by several cues: {sorted(duplicates)}")

    # Every track the music director can ask for must exist, or a whole game
    # state plays silently — the same silent failure as a missing cue.
    for state_asset in _music_assets_named_in_swift():
        if state_asset not in music:
            problems.append(f"music state asset '{state_asset}.wav' is missing")

    for asset in sorted(files | music):
        path = os.path.join(AUDIO, asset + ".wav")
        with wave.open(path) as w:
            frames, rate, ch, width = (w.getnframes(), w.getframerate(),
                                       w.getnchannels(), w.getsampwidth())
            raw = w.readframes(frames)
        is_music = asset in music
        # Music runs at half rate on purpose: a slow pad has nothing near
        # Nyquist, and it halves the bundle. Everything else matches the
        # engine's own format so no per-node converter is needed.
        allowed_rate = 22050 if is_music else 44100
        if ch != 1 or width != 2 or rate != allowed_rate:
            problems.append(f"{asset}: expected mono/16-bit/{allowed_rate}, "
                            f"got {ch}ch/{width * 8}-bit/{rate}")
        seconds = frames / rate
        looping = asset.startswith("ambience_") or is_music
        if not looping and seconds > MAX_ONESHOT_SECONDS:
            problems.append(f"{asset}: {seconds:.2f}s exceeds the "
                            f"{MAX_ONESHOT_SECONDS}s one-shot ceiling")
        # A loop with mismatched endpoints clicks once every pass, which over
        # an hour is the most irritating defect an audio system can have.
        if looping and frames > 2:
            first = int.from_bytes(raw[0:2], "little", signed=True)
            last = int.from_bytes(raw[-2:], "little", signed=True)
            if abs(first - last) / 32767 > 0.02:
                problems.append(f"{asset}: loop seam discontinuity "
                                f"{abs(first - last) / 32767:.3f}")
        # Music must never be the loudest thing in the game.
        if is_music and (max(abs(int.from_bytes(raw[i:i + 2], "little", signed=True))
                             for i in range(0, len(raw), 2)) / 32767) > 0.40:
            problems.append(f"{asset}: music may not exceed 0.40 peak")
        peak = max(abs(int.from_bytes(raw[i:i + 2], "little", signed=True))
                   for i in range(0, len(raw), 2)) / 32767
        if peak > MAX_PEAK:
            problems.append(f"{asset}: peak {peak:.2f} over the "
                            f"{MAX_PEAK} ceiling")
        if peak < 0.05:
            problems.append(f"{asset}: peak {peak:.3f} — effectively silent")

    if problems:
        print("Audio asset check FAILED:")
        for p in problems:
            print("  -", p)
        return 1
    print(f"Audio assets OK: {len(names)} cues, {len(files)} cue files, "
          f"{len(music)} music beds, all voiced, all within the mix ceiling.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
