#!/usr/bin/env python3
"""Generate alert-ding.wav: a bright, high-pitched triple ding for Omadoro's
phase-end alert. Regenerate with:  python3 tools/make-alert-sound.py

Deliberately synthesized rather than borrowed from the freedesktop sound theme:
bell.oga is a soft, low, one-shot chime that is easy to miss. This is a hard
attack, fast decay, high fundamental (C7) with an octave harmonic on top, so it
cuts through music and speech.
"""
import math
import os
import struct
import wave

RATE = 48000
FUND = 2093.0          # C7
HARMONIC = 4186.0      # C8, adds the metallic "ding" edge
DECAY = 0.16           # seconds; exponential amplitude decay
DING_LEN = 0.26        # seconds per ding, including its tail
GAP = 0.04             # silence between dings
DINGS = 3
PEAK = 0.62            # of full scale, leaves headroom


def ding(samples):
    out = []
    for i in range(samples):
        t = i / RATE
        env = math.exp(-t / DECAY)
        # 3 ms attack ramp so the onset is a click-free but still sharp
        attack = min(1.0, t / 0.003)
        v = (math.sin(2 * math.pi * FUND * t)
             + 0.42 * math.sin(2 * math.pi * HARMONIC * t))
        out.append(v / 1.42 * env * attack * PEAK)
    return out


frames = []
for n in range(DINGS):
    frames.extend(ding(int(RATE * DING_LEN)))
    if n != DINGS - 1:
        frames.extend([0.0] * int(RATE * GAP))

path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "alert-ding.wav")
with wave.open(path, "w") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(
        struct.pack("<hh", int(max(-1.0, min(1.0, s)) * 32767),
                    int(max(-1.0, min(1.0, s)) * 32767))
        for s in frames))
print("wrote", path, os.path.getsize(path), "bytes")
