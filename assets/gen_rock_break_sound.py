"""
Generates assets/audio/rock_break.wav — a short rock cracking/breaking sound.
Layers: low thump + broadband noise crumble, all with fast exponential decay.

Run via:  python3 assets/gen_rock_break_sound.py
"""

import wave
import struct
import math
import random
import os

SAMPLE_RATE = 44100
DURATION    = 0.45
OUT_PATH    = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "audio", "rock_break.wav")

rng = random.Random(7)
samples = []

for i in range(int(SAMPLE_RATE * DURATION)):
    t = i / SAMPLE_RATE

    # Low-frequency impact thump — fast decay
    thump = math.sin(2 * math.pi * 70 * t) * math.exp(-t * 18.0) * 0.55

    # Initial sharp crack — very fast noise burst
    crack = rng.uniform(-1.0, 1.0) * math.exp(-t * 40.0) * 0.50

    # Longer crumble — slower noise decay
    crumble = rng.uniform(-1.0, 1.0) * math.exp(-t * 9.0) * 0.35

    samples.append(thump + crack + crumble)

# Normalise to 16-bit PCM
peak = max(abs(s) for s in samples)
pcm  = [max(-32768, min(32767, int(s / peak * 28000))) for s in samples]

with wave.open(OUT_PATH, "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(SAMPLE_RATE)
    for s in pcm:
        f.writeframes(struct.pack("<h", s))

print(f"Written: {OUT_PATH}  ({DURATION}s, {SAMPLE_RATE} Hz, mono 16-bit PCM)")
