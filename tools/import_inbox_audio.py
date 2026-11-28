#!/usr/bin/env python3
"""Copies the user's delivered recordings from an audio inbox folder into the
game's runtime audio folder (assets/audio/<logical>_<n>.wav), with a gain per
file towards a loudness target for its category (so the variations of one
sound play at a similar level). The inbox originals are never modified.

    python3 tools/import_inbox_audio.py assets/audio/_inbox/20261128

Needs numpy. 16-bit PCM WAV in and out (sample rate and channels kept).
Re-running overwrites the runtime copies; add new rows to MAP for new sounds.
"""
import os
import re
import sys
import wave

import numpy as np

# inbox name (before the variation number) -> (logical name, target RMS dBFS)
MAP = {
    "engine loop": ("vehicles/engine_loop", -15.0),
    "engine load": ("vehicles/engine_load", -15.0),
    "tire squeal": ("vehicles/tire_squeal", -19.0),
    "car impact": ("vehicles/impact_car", -15.0),
    "wall impact": ("vehicles/impact_wall", -15.0),
    "backfire": ("vehicles/backfire", -19.0),
    "turbo spit": ("vehicles/turbo_spit", -19.0),
    "debris rattle": ("vehicles/debris_rattle", -21.0),
    "missile launch": ("weapons/missile_launch", -15.0),
    "homing launch": ("weapons/homing_launch", -15.0),
    "super launch": ("weapons/super_launch", -15.0),
    "mine drop": ("weapons/mine_drop", -19.0),
    "empty weapon": ("weapons/empty", -25.0),
    "explosion": ("weapons/explosion", -14.0),
    "crowd loop": ("crowd/crowd_loop", -22.0),
    "crowd cheer": ("crowd/cheer", -19.0),
    "crowd gasp": ("crowd/gasp", -19.0),
    "crowd applause": ("crowd/applause", -19.0),
    "racetrack ambiance": ("ambience/ambience", -26.0),
    "ui move": ("ui/ui_move", -22.0),
    "ui select": ("ui/ui_select", -20.0),
    "ui back": ("ui/ui_back", -22.0),
    "notification pop": ("ui/pop", -21.0),
    "lap completion tick": ("ui/tick", -23.0),
    "replay whosh": ("ui/whoosh", -22.0),
    "replay whoosh": ("ui/whoosh", -22.0),
    "race start": ("race/start_go", -14.0),
    "race finish": ("race/finish", -15.0),
    "achievement": ("ui/achievement", -19.0),
    "fastest lap stinger": ("ui/stinger", -19.0),
    "shop buy": ("ui/shop_buy", -19.0),
    "shop sell": ("ui/shop_sell", -19.0),
}
PEAK_LIMIT_DB = -1.0
GAIN_RANGE = (-12.0, 26.0)


def main(inbox: str) -> None:
    root = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
    done = {}
    for name in sorted(os.listdir(inbox)):
        m = re.match(r"^(.*?)\s*(\d+)\.wav$", name, re.IGNORECASE)
        if not m:
            print("skip", name)
            continue
        key = m.group(1).strip().lower()
        if key not in MAP:
            print("UNMAPPED", name)
            continue
        logical, target = MAP[key]
        n = int(m.group(2))
        w = wave.open(os.path.join(inbox, name))
        ch, sw, sr, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        if sw != 2:
            print("not 16-bit, skipped", name)
            continue
        data = np.frombuffer(w.readframes(frames), dtype=np.int16).astype(np.float64) / 32768.0
        mono = data.reshape(-1, ch).mean(axis=1) if ch > 1 else data
        rms_db = 20 * np.log10(np.sqrt(np.mean(mono ** 2)) + 1e-12)
        peak_db = 20 * np.log10(np.max(np.abs(data)) + 1e-12)
        gain = min(target - rms_db, PEAK_LIMIT_DB - peak_db)
        gain = max(GAIN_RANGE[0], min(GAIN_RANGE[1], gain))
        out = np.clip(data * 10 ** (gain / 20.0), -1.0, 32767 / 32768.0)
        dest = os.path.join(root, logical + "_%d.wav" % n)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        o = wave.open(dest, "wb")
        o.setnchannels(ch)
        o.setsampwidth(2)
        o.setframerate(sr)
        o.writeframes((out * 32768.0).astype("<i2").tobytes())
        o.close()
        done.setdefault(logical, []).append((n, round(float(gain), 1)))
    for logical, items in sorted(done.items()):
        print("%-24s %d variations, gain dB %s" % (logical, len(items), [g for _, g in sorted(items)]))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/audio/_inbox/20261128")
