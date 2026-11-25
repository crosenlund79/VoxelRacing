# Voice Director: announcer and rival taunts

Event-driven race commentary with the user's own recordings (presentation only:
nothing it does can change a race; tests prove races are bit-identical with it on
or off).

## Events and recordings

| Event (VoiceCatalog.Event) | When | Line (logical name) | Recording (`assets/audio/_inbox/`) |
|---|---|---|---|
| `PLAYER_DESTROYED` | a weapon destroys the player's car (combat `destroyed` event; a DNF without a destruction is not one) | `voice/announcer_smoked_you` | Announcer - Smoked you (on player killed).mp3 |
| `PLAYER_HIT_WALL` | the player hits a barrier at ≥ 210 px/s (sometimes) | `voice/announcer_bumper_cars` | Announcer - U playing bumper cars (sometimes when player hits the walls).mp3 |
| `RIVAL_OVERTOOK_PLAYER`, Rocco (racer 2) | Rocco passes the player | `voice/rocco_laughing` | Rocco - Laughing (if overtaken by Rocco).mp3 |
| `RIVAL_OVERTOOK_PLAYER`, Nina "The Hunter" (racer 9) | Nina passes the player | `voice/nina_thank_you` | the Hunter - Thank you (if overtaken by The Hunter).mp3 |
| `RIVAL_OVERTOOK_PLAYER`, Victor "The Professor" (racer 1) | Victor passes the player | `voice/victor_clean` | The Professor - Clean (if overtaken by The Professor).mp3 |

| `PIT_VIOLATION` | any car gets a pit-lane collision ticket (combat `ticket` event; once per ticket, also when spectating); the recording says "Pit lane violation", which names no offence | `voice/announcer_pit_violation` | Announcer - Pit lane violation (When a car speeds in the pit lane).mp3 |
| `WEAPONS_HOT` (a race announcement) | weapons unlock after the starting field has crossed the start line (Weapons Hot) | `voice/announcer_weapons_hot` | Announcer - Weapons Hot (When all drivers have passed the starting line - and weapons are unlocked).mp3 |

Rivals are matched by racer id (`RivalRoster`), never by name. Other rivals passing
the player, and the player passing a rival, say nothing (no recordings).

**Overtakes** are confirmed, not standings flicker: the rival must have trailed the
player by ≥ 24 px of race distance for 0.6 s and then lead by ≥ 24 px for 0.6 s
(`OvertakeWatch`). Race distance includes laps (lap changes and lapping are never
passes); comparisons involving a car that finished, retired (DNF) or is not racing are
dropped; a car whose distance jumps (jump recovery, a network correction) restarts
its comparisons silently; nothing is reported in the first 3 s of a race.

Race announcements (`VoiceCatalog.ANNOUNCEMENTS`, so far "Weapons hot") are never
skipped by chance and are not held back by the short gap after a line, but they never
start over a line that is still playing. "Weapons hot" is also said when spectating.

## One voice, memory, silence (`VoiceSelector`)

- Only one line plays at a time. Events during a line, or within 3.5 s after it, are
  discarded (never queued for later).
- Events at the same moment are pooled: at most one line, chosen by weight. A rival's
  own line is preferred (×1.6) over announcer commentary on the same event; silence is
  always an option (weight 0.35 for a destroyed car, 0.55 for an overtake, 2.2 for a
  barrier hit, + 0.25 per line spoken in the last minute).
- The same speaker within 18 s ×0.12, the same interaction (event + speaker) within
  40 s ×0.25, the line just played ×0.35. So Nina passing you again ten seconds later
  is usually met with silence.
- Memory is per race (reset when a race starts).

## Playback (`VoiceParams`, `src/audio/default_voice_params.tres`)

- Rival lines at 1.10× speed, announcer at 1.0× (`rival_speed`, `announcer_speed`,
  per-line `line_speed`). The natural pitch is kept: the speed-up uses `pitch_scale`
  and an `AudioEffectPitchShift` on the Voice bus shifts the pitch back
  (`preserve_pitch`; off = plain faster playback, ~1.6 semitones higher). Measured:
  the in-game voice pitch is within 1–2 % of the original at 1.10×. Godot's pitch
  shifter is FFT-based and can add a slight "phasey" colour; judge by ear.
- Voice bus with its own volume and mute in AUDIO SETTINGS (default 90 %), under Master.
- Music and engines dip by 5 dB while someone speaks, fading over 0.25 s.
- Pausing (the race menu) holds the line; leaving the race stops it.

## Modes

Single-player and garage races: the player. Couch: both players (still one voice).
Network: each computer comments on its own player only (the host on Player 1, the
client on Player 2), so lines never double up. Spectating: nobody is "the player",
so nothing is said about the followed rival.

## Adding recordings

1. Keep the original in `assets/audio/_inbox/` (Godot ignores that folder:
   `.gdignore`, so originals are never imported or packed twice).
2. Copy it to `assets/audio/voice/<speaker>_<phrase>.mp3` (OGG or WAV also work).
3. Add one entry to `VoiceCatalog.LINES` (`src/audio/voice_catalog.gd`): id, logical
   name, speaker (`ANNOUNCER` or the rival's racer id), event, source file. Several
   lines for the same speaker and event become variants; `weight` makes one rare,
   `min_count` makes one an escalation (only after the interaction happened that
   often in the race). New kinds of events need a small detection hook in
   `VoiceDirector`.

Players can replace any line without rebuilding: `custom/audio/voice/<name>.ogg`,
`.wav` or `.mp3` next to the game (or the project's override root). A missing or
broken recording is skipped silently.
