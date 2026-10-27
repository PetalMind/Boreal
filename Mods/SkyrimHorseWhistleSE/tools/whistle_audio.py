"""Create an original, deterministic two-note whistle (PCM mono 44.1 kHz)."""
import math
import random
import struct
import sys
import wave
from pathlib import Path


def build_whistle(output: Path) -> None:
    sample_rate = 44100
    duration = 1.25
    randomizer = random.Random(34)
    samples = []
    phase = 0.0
    breath = 0.0
    for index in range(int(sample_rate * duration)):
        time = index / sample_rate
        note_start = 0.04 if time < 0.43 else 0.50
        note_length = 0.30 if time < 0.43 else 0.62
        local = time - note_start
        if 0.0 <= local < note_length:
            envelope = min(local / 0.025, 1.0) * min((note_length - local) / 0.075, 1.0)
            progress = local / note_length
            frequency = (1780.0 + 380.0 * math.sin(math.pi * progress / 2.0)
                         if note_start < 0.1 else 2080.0 - 680.0 * progress ** 1.6)
            frequency += 12.0 * math.sin(2.0 * math.pi * 5.5 * time)
            phase += 2.0 * math.pi * frequency / sample_rate
            breath = 0.4 * breath + 0.6 * randomizer.uniform(-1.0, 1.0)
            value = envelope * (0.68 * math.sin(phase) + 0.025 * math.sin(2.0 * phase) + 0.012 * breath)
        else:
            value = 0.0
        samples.append(struct.pack("<h", round(max(-1.0, min(1.0, value)) * 32767)))
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as audio:
        audio.setparams((1, 2, sample_rate, 0, "NONE", "not compressed"))
        audio.writeframes(b"".join(samples))


if __name__ == "__main__":
    build_whistle(Path(sys.argv[1]))
