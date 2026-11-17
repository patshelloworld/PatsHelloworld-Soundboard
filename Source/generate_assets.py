import math
import random
import struct
import sys
import wave
from pathlib import Path

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
rate = 22050
randomizer = random.Random(14)


def note(frequency, seconds, kind="sine"):
    for frame in range(round(rate * seconds)):
        t = frame / rate
        envelope = min(t / 0.01, 1, (seconds - t) / 0.06)
        phase = 2 * math.pi * frequency * t
        if kind == "brass":
            signal = (math.sin(phase) + 0.4 * math.sin(2 * phase) + 0.24 * math.sin(3 * phase)) / 1.64
        elif kind == "drop":
            signal = math.sin(phase * (1 - 0.32 * t / seconds))
        elif kind == "noise":
            signal = randomizer.uniform(-1, 1) * math.exp(-5 * t / seconds)
            signal += 0.3 * math.sin(phase * (1 - 0.44 * t / seconds)) * math.exp(-3 * t / seconds)
        else:
            signal = math.sin(phase)
        yield int(12500 * envelope * signal)


sounds = {
    "Air Horn": [(340, 0.18, "brass"), (340, 0.18, "brass"), (470, 0.4, "brass")],
    "Low Drop": [(150, 0.55, "drop")],
    "Victory": [(523, 0.14), (659, 0.14), (784, 0.14), (1047, 0.44)],
    "Error": [(266, 0.2, "brass"), (192, 0.35, "brass")],
    "Level Up": [(392, 0.09), (494, 0.09), (587, 0.09), (784, 0.09), (988, 0.29)],
    "Rimshot": [(220, 0.11, "noise"), (180, 0.13, "noise"), (1290, 0.5, "noise")],
    "Sad Trombone": [(329, 0.29, "brass"), (311, 0.29, "brass"), (294, 0.29, "brass"), (277, 0.52, "brass")],
    "Record Scratch": [(1660, 0.37, "noise"), (1230, 0.22, "noise")],
    "Coin": [(1319, 0.11), (1976, 0.31)],
    "Alert": [(740, 0.17), (540, 0.17), (740, 0.17), (540, 0.23)],
    "Explosion": [(94, 0.9, "noise")],
    "Game Over": [(440, 0.21), (349, 0.21), (262, 0.21), (196, 0.56, "drop")],
    "Notification": [(880, 0.12), (1175, 0.22)],
    "Countdown": [(440, 0.16), (440, 0.16), (440, 0.16), (880, 0.32)],
    "Whoosh": [(640, 0.48, "noise")],
}

for name, sound in sounds.items():
    samples = [sample for segment in sound for sample in note(*segment)]
    with wave.open(str(destination / f"{name}.wav"), "wb") as output:
        output.setparams((1, 2, rate, 0, "NONE", ""))
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))
