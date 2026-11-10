# SKIvSKI: the game's own sound effects, synthesised here (no recordings, so nothing to license), written to
# Docs/Audio/*.wav and imported as Sound Waves into /SKIvSKI/Audio. Rerunnable: the WAVs are made again and
# re-imported over the assets. Change a sound by changing its recipe below.
#
#   S_SkiHit        a wet splat and a bright two-note ding: your paint knocked someone OUT
#   S_SkiBounce     a springy "pyoing" that falls in pitch: the ball bounced off
#   S_SkiBeep       one countdown second (GET READY 3, 2, 1)
#   S_SkiGo         the start: a higher, longer beep
#   S_SkiFanfare    brass-like fanfare for the results scoreboard
#   S_SkiScore      a short rising chime when a team's score goes up
#
# The shots themselves use Other5Combat's rifle sounds (see SetupGuns.py).
# Run in the editor: py "<this file>"
import math
import os
import random
import struct
import sys
import traceback
import wave

import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupAudio"
RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Audio"))
FOLDER = "/SKIvSKI/Audio"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def note(name):
    """'C5' -> Hz (A4 = 440)."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12.0)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(base, add, at=0.0, gain=1.0):
    start = int(at * RATE)
    if len(base) < start + len(add):
        base.extend([0.0] * (start + len(add) - len(base)))
    for i, v in enumerate(add):
        base[start + i] += v * gain
    return base


def env(i, n, attack, release):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (n - i) / (release * RATE)) if release > 0 else 1.0
    return a * r


def tone(freq, seconds, harmonics=(1.0,), attack=0.01, release=0.05, decay=0.0, vibrato=0.0, sweep_to=None):
    """Additive tone: harmonics[k] is the level of the (k+1)th harmonic. decay: exponential fade per second.
    sweep_to: the pitch glides to this frequency (exponentially) over the note."""
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if sweep_to is None else freq * (sweep_to / freq) ** (i / n)
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t / 0.15)
        phase += 2 * math.pi * f / RATE
        v = sum(h * math.sin(phase * (k + 1)) for k, h in enumerate(harmonics) if h)
        v *= env(i, n, attack, release) * (math.exp(-decay * t) if decay else 1.0)
        out.append(v)
    return out


def noise(seconds, cutoff=0.2, decay=20.0, attack=0.002, seed=1):
    """Low-passed noise burst (one-pole filter; cutoff 0..1), fading exponentially."""
    rnd = random.Random(seed)
    n = int(seconds * RATE)
    out, y = [], 0.0
    for i in range(n):
        y += cutoff * (rnd.uniform(-1, 1) - y)
        t = i / RATE
        out.append(y * min(1.0, t / attack) * math.exp(-decay * t))
    return out


def normalize(samples, peak=0.8):
    m = max(abs(v) for v in samples) or 1.0
    return [v * peak / m for v in samples]


BELL = (1.0, 0.0, 0.35, 0.0, 0.18, 0.0, 0.08)
BRASS = (1.0, 0.75, 0.55, 0.42, 0.3, 0.2, 0.14, 0.09)
SOFT = (1.0, 0.0, 0.2, 0.0, 0.05)


def make_hit():
    s = noise(0.16, cutoff=0.35, decay=28.0, seed=7)
    mix(s, noise(0.10, cutoff=0.08, decay=35.0, seed=3), 0.0, 1.6)        # low thump under the splat
    mix(s, tone(note("E6"), 0.16, BELL, 0.002, 0.03, decay=10.0), 0.05, 0.55)
    mix(s, tone(note("B6"), 0.42, BELL, 0.002, 0.12, decay=6.0), 0.13, 0.6)
    return normalize(s, 0.85)


def make_bounce():
    s = tone(1500.0, 0.34, (1.0, 0.3, 0.1), 0.003, 0.08, decay=4.0, vibrato=0.06, sweep_to=420.0)
    mix(s, noise(0.05, cutoff=0.5, decay=60.0, seed=11), 0.0, 0.5)
    return normalize(s, 0.7)


def make_beep():
    return normalize(tone(note("A5"), 0.16, SOFT, 0.004, 0.05), 0.6)


def make_go():
    s = tone(note("A6"), 0.45, SOFT, 0.004, 0.2, decay=1.5)
    mix(s, tone(note("E6"), 0.45, SOFT, 0.004, 0.2, decay=1.5), 0.0, 0.5)
    return normalize(s, 0.7)


def make_fanfare():
    s = []
    beat = 0.13
    # Pick-up triplet, then the call, then a held major chord.
    line = [("G4", 0, 0.8), ("C5", 1, 0.8), ("E5", 2, 0.8), ("G5", 3, 2.0), ("E5", 5, 0.8), ("G5", 6, 4.5)]
    for name, at, length in line:
        mix(s, tone(note(name), beat * length + 0.08, BRASS, 0.02, 0.06, vibrato=0.006), beat * at, 0.5)
    hold_at = beat * 11
    for name in ("C5", "E5", "G5", "C6"):
        mix(s, tone(note(name), 1.5, BRASS, 0.04, 0.5, vibrato=0.008), hold_at, 0.32)
    mix(s, noise(1.4, cutoff=0.9, decay=2.5, attack=0.01, seed=5), hold_at, 0.12)   # a cymbal wash
    mix(s, noise(0.12, cutoff=0.06, decay=25.0, seed=9), hold_at, 0.9)               # and a drum hit
    return normalize(s, 0.85)


def make_score():
    s = []
    for k, name in enumerate(("C6", "E6", "G6")):
        mix(s, tone(note(name), 0.22, BELL, 0.002, 0.08, decay=7.0), 0.07 * k, 0.5)
    return normalize(s, 0.6)


SOUNDS = {
    "S_SkiHit": make_hit,
    "S_SkiBounce": make_bounce,
    "S_SkiBeep": make_beep,
    "S_SkiGo": make_go,
    "S_SkiFanfare": make_fanfare,
    "S_SkiScore": make_score,
}


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


def main():
    os.makedirs(OUT, exist_ok=True)
    tasks = []
    for name, make in SOUNDS.items():
        path = os.path.join(OUT, name + ".wav")
        write_wav(path, make())
        t = unreal.AssetImportTask()
        t.set_editor_property("filename", path)
        t.set_editor_property("destination_path", FOLDER)
        t.set_editor_property("destination_name", name)
        t.set_editor_property("replace_existing", True)
        t.set_editor_property("automated", True)
        t.set_editor_property("save", True)
        tasks.append(t)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
    for t in tasks:
        for p in t.get_editor_property("imported_object_paths"):
            log("imported " + p)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
