"""
Generates assets/audio/mining_laser.wav — a loopable low hum.
Simple sine wave at 90 Hz with two harmonics, no modulation.

Run via:  python3 assets/gen_mining_sound.py
"""

import wave
import struct
import math
import os

SAMPLE_RATE = 44100
DURATION    = 1.0        # seconds — 90 Hz completes exactly 90 cycles, loops cleanly
OUT_PATH    = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "audio", "mining_laser.wav")

samples = []
for i in range(int(SAMPLE_RATE * DURATION)):
    t = i / SAMPLE_RATE

    # Low hum: fundamental + two harmonics
    sig  = 0.55 * math.sin(2 * math.pi *  90 * t)
    sig += 0.28 * math.sin(2 * math.pi * 180 * t)
    sig += 0.17 * math.sin(2 * math.pi * 270 * t)

    samples.append(sig)

# Normalise and convert to 16-bit PCM
peak = max(abs(s) for s in samples)
pcm  = [max(-32768, min(32767, int(s / peak * 28000))) for s in samples]

with wave.open(OUT_PATH, "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(SAMPLE_RATE)
    for s in pcm:
        f.writeframes(struct.pack("<h", s))

print(f"Written: {OUT_PATH}  ({DURATION}s, {SAMPLE_RATE} Hz, mono 16-bit PCM)")
