# Music

The three official tracks by the user are integrated unchanged. They are copied
byte-for-byte from `assets/audio/_inbox/` (originals kept there):

| Logical name | Packaged file | Source | Plays on |
|---|---|---|---|
| `music/music_menu` | `assets/audio/music/template_music_menu.mp3` | HyperCars - Theme.mp3 (89.6 s) | title, GO RACING!, setup screens, garage, championship standings |
| `music/music_race` | `assets/audio/music/template_music_race.mp3` | HyperCars - Racing Theme.mp3 (179.6 s) | every race, Knockout, spectating |
| `music/music_battle` | `assets/audio/music/template_music_battle.mp3` | HyperCars - Battle Royale.mp3 (151.3 s) | Battle Royale (from FIGHT!, through restarts, until back to the menu) |

There is no remix, re-encode, shortening or generated music.

## One shared player (`src/audio/music_player.gd`)

The game root owns one `MusicPlayer`. The title, the race scene and the Battle Royale
arena all use it, so music survives scene changes.

**`play(piece)`**
- If the piece is already playing, it returns and nothing restarts. Laps, collisions,
  destructions, respawns, voice lines, camera changes, the pause menu and results
  screens never restart the music.
- Otherwise it crossfades (1.2 s) from the current piece: menu to race at GO!, race to
  menu on the way back.

Both pieces play on the **Music** bus. MUSIC is an independent volume / mute in
SETTINGS > AUDIO, saved in `user://settings.cfg` with the other buses.

**Voice ducking.** A voice line ducks the Music and Engine buses through an amplify
effect (VoiceDirector). The music player is never touched, so the music dips and comes
back without restarting.

## Loop technique

The files were measured: neither has leading silence. Each piece's musical ending sits
a little before the end of the file:

- Theme: the last 0.92 s is near-silent padding.
- Racing Theme: the last 1.25 s is a reverb tail.

A seamless MP3 loop is impossible: encoder padding adds a gap. Instead, each piece plays
to its musical end and then crossfades into a fresh start of itself on the second
player:

| Piece | Loop point (before file end) | Crossfade |
|---|---|---|
| Theme | 0.92 s | 0.08 s (the padding is silence) |
| Racing Theme | 1.25 s | 0.35 s (the reverb tail overlaps the new start) |
| Battle Royale | 0.59 s (silence) | 0.2 s; the restart begins at 0.83 s, after the file's leading silence (`start`) |

No music is cut: only the trailing silence or tail overlaps the restart.
`MusicPlayer.loop_due()` decides when, and is tested as a pure function. The headless
test driver does not advance playback, so the crossfade itself needs a listening check;
see the manual checklist.

## Overrides

`custom/audio/music/music_menu.(ogg|wav|mp3)`, `music_race.(...)` and `music_battle.(...)` replace the
pieces next to an exported Windows / Linux game, without a rebuild. Overrides loop with
a short default crossfade (0.25 s at the file end), since their padding is unknown.

Tests: `tests/unit/test_music.gd`
- packaged tracks and their lengths;
- no restart when the same piece plays again; crossfade to another piece;
- loop points;
- music survives a destruction, a respawn and the pause menu;
- voice ducking never restarts the music;
- the Battle Royale theme: byte-identical packaged copy, its loop without the
  silences, played in the arena without restarts and handed back to the menu / race
  themes.
