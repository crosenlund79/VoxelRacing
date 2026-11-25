# Manual checklist: The Big Refinement (2026-11-17)

Needs a human: listening, feel and real controllers.

## Music
- [ ] The title plays the HyperCars Theme. GO RACING!, setup, garage and championship
      screens keep it going without restarting.
- [ ] At GO! the Racing Theme fades in (about 1.2 s). Leaving the race fades back to the
      Theme.
- [ ] Let each piece run past its end:
      - Theme at 1:30: the loop sounds natural, with no gap or click.
      - Racing Theme at 3:00: the reverb tail overlaps the restart naturally.
- [ ] Destructions, respawns, taunts, the Esc menu, camera changes in spectating and the
      results never restart the music.
- [ ] A taunt dips the music, which then comes back.
- [ ] SETTINGS > AUDIO > MUSIC changes only the music and is remembered after a restart.
- [ ] An override in `custom/audio/music/music_race.mp3` plays after a restart.

## Menu safety
- [ ] Hold Fire through the finish: results, championship standings, the garage prompt,
      rewards and the forfeit prompt never react to Fire.
- [ ] Enter (pad Start) continues. Esc (pad B) goes back.
- [ ] Spectating: Tab skips, F changes the speed, and Enter watches now after you finish.

## Controls screen
- [ ] Remap Fire to another key and a pad button; it works in a race and is remembered
      after a restart.
- [ ] Try to give Confirm the Fire key: it is refused, with a message.
- [ ] RESTORE DEFAULTS brings back Space / Ctrl / pad A.
- [ ] Couch split-screen: each player's controller uses the remapped pad buttons, and the
      keyboard player uses the remapped keys.

## Environments
- [ ] The Raceway, day and night:
      - kerbs follow the corners;
      - ad boards face the road and are readable;
      - the pit building sits beside the straight;
      - floodlit at night.
- [ ] The Raceway feels slightly faster and grippier.
- [ ] Tabletop Mayhem, day and night:
      - the giant objects never cover the road and never look like barriers;
      - warm desk-lamp night.
- [ ] Tabletop Mayhem launches noticeably quicker.
- [ ] Previews: the setup diorama shows floodlights and kerbs for The Raceway, and pencils
      and dice for Tabletop Mayhem.
- [ ] Battle Royale in both new environments looks right.

## Championship
- [ ] ROUNDS 6 / 3 on the setup; the note lists every round and the FINAL.
- [ ] Before the last round the standings say "NEXT: THE GRAND FINAL" and
      "START THE FINAL"; the HUD says GRAND FINAL.

## Modes and economy
- [ ] Knockout: when you are last of those still in, the HUD line turns red
      ("YOU ARE IN THE DROP ZONE!") and your position shows a red "!".
- [ ] Battle Royale: a hit that does not eliminate you shows no rival popup; the
      eliminating hit does.
- [ ] Garage session of 5+ races at middling results:
      - repairs at $2 per %;
      - a car below 50 % is patched up free;
      - prizes $550 / 400 / 300 / 200 / 125;
      - you stay in the game.
- [ ] Achievement toasts appear below the kill feed, not on top of it.
