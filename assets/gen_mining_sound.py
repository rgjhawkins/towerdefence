"""
Generates assets/audio/mining_laser.wav — a loopable mining laser sound.
Layers: low industrial hum + mid buzz + high-freq laser whine,
amplitude-modulated at 8 Hz so it feels like active cutting.
The 2-second duration is an exact multiple of the 8 Hz mod period,
so it loops seamlessly.

Run via:  python3 assets/gen_mining_sound.py
"""

import wave
import struct
import math
import os

SAMPLE_RATE = 44100
DURATION    = 2.0        # seconds — exact multiple of mod period (8 Hz → 16 cycles)
OUT_PATH    = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "audio", "mining_laser.wav")

samples = []
for i in range(int(SAMPLE_RATE * DURATION)):
    t = i / SAMPLE_RATE

    # Low industrial hum (base + 2 harmonics)
    sig  = 0.40 * math.sin(2 * math.pi *   90 * t)
    sig += 0.20 * math.sin(2 * math.pi *  180 * t)
    sig += 0.10 * math.sin(2 * math.pi *  270 * t)

    # Mid laser buzz
    sig += 0.12 * math.sin(2 * math.pi *  540 * t)

    # High-frequency laser whine with slight FM wobble
    freq_whine = 1800 + 60 * math.sin(2 * math.pi * 3 * t)
    sig += 0.08 * math.sin(2 * math.pi * freq_whine * t)

    # Amplitude modulation — 8 Hz "cutting" pulse
    am   = 0.80 + 0.20 * math.sin(2 * math.pi * 8 * t)
    sig *= am

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
