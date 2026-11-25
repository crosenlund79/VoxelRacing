# HyperCars — consolidated human playtest checklist

One checklist for the full pre-release playtest. It replaces walking through every
older milestone checklist; those remain for detail.

**Before you start:** play with a controller and with the keyboard. Note your Godot
window size and machine. The game shows hints with your own bindings, so the keys
below are the defaults.

## 1. Controls and menus

- [ ] Title, GO RACING!, setup, garage, championship standings and the Esc race menu
      work with a controller only: d-pad / stick to move, A or Start to select, B back.
- [ ] CONTROLS: remap Fire to another key **and** a controller button.
  - [ ] The second Fire key still works.
  - [ ] It works in a race and is still remapped after restarting the game.
  - [ ] Giving Confirm the Fire key is refused with a message.
  - [ ] Delete empties a slot; the last input of an action cannot be removed.
  - [ ] RESTORE DEFAULTS resets everything.
- [ ] With a remapped binding, every hint shows it: grid panel, results, watch prompt,
      spectator history panel, race menu, garage, championship standings, network
      ready line, join panel.
- [ ] Hold Fire through a finish: results, championship standings, rewards, the garage
      prompt and forfeit prompts never react. Enter / Start continues.
- [ ] Fire starts the race on the grid panel. Holding it from the previous screen does
      not start a race on its own.
- [ ] Single player with a second controller (not the first one Windows / Linux
      reports): it drives.
- [ ] Unplug the controller mid-race: the race pauses with "CONTROLLER DISCONNECTED".
      Plug it in, resume, and it works.
- [ ] Couch: two controllers join; each drives only its own car. Unplugging one pauses
      the race and names the player. Remapped bindings apply to both.

## 2. Music and audio (listening — automated tests cannot judge this)

- [ ] Title: "HyperCars - Theme" starts. Moving through GO RACING!, setup, garage and
      championship screens never restarts it.
- [ ] Wait past 1:29 on the title: the Theme loops with no gap, click or doubled beat.
- [ ] Start a race: the Racing Theme fades in (about 1.2 s). Leave the race: the Theme
      fades back.
- [ ] Let a race run past 2:58: the Racing Theme's reverb tail overlaps the restart
      naturally, with no hard cut and no silence.
- [ ] Destructions, respawns, the Esc menu, results, spectator camera changes and
      fast-forward never restart the music.
- [ ] An announcer line or rival taunt dips the music and engines a little; they come
      back smoothly.
- [ ] SETTINGS > AUDIO: MUSIC changes only the music; mute works; both are remembered
      after a restart.
- [ ] Put an MP3 or OGG at `custom/audio/music/music_race.mp3`, restart: it plays and
      loops.

## 3. Races, environments and day / night

- [ ] Each circuit (Kestrel Ridge, Larkspur Ring, Ravenhook) in each environment, by
      day and by night:
  - [ ] the road is readable;
  - [ ] props never cover the road;
  - [ ] Tabletop objects never look like barriers;
  - [ ] Raceway ad boards face the road;
  - [ ] kerbs follow the corners.
- [ ] Feel:
  - [ ] Winter slides;
  - [ ] Wasteland is a little less grippy;
  - [ ] The Raceway is slightly faster and grippier;
  - [ ] Tabletop launches much quicker;
  - [ ] Green Valley is the baseline.
- [ ] Jumps: fast enough flies, too slow falls in. The same for you and the rivals.
- [ ] New quick races start from different grids and play out differently. Rocco is
      dangerous but does not win most races.
- [ ] Rivals feel like themselves:
  - [ ] Victor clean;
  - [ ] Rocco reckless, with spectacular wins and crashes;
  - [ ] Ellie flustered under pressure;
  - [ ] Hank defends;
  - [ ] Nina hunts.
- [ ] Armed races at 3, 7 and 20 laps: retirements happen but most cars finish; the
      kill feed and TOMBSTONE | K | D read correctly.

## 4. Garage career

- [ ] Garage race, buy and sell, repair, armour, race, then quit the game. Restart:
      money, rounds, equipped weapons, condition and armour are as you left them.
- [ ] Quit **during** a garage race and restart: nothing was spent or paid, the car is
      as before the race, and no rounds were lost or duplicated.
- [ ] NEW GARAGE asks once, then starts over from $300 and 5 + 5 rounds.
- [ ] Session of 6+ garage races finishing mid-field: tight but you can keep racing
      (free patch-up to 50 %). Note whether it feels too easy or too hard.
- [ ] One 7-lap garage race: note the repair bill against the prize.

## 5. Modes

- [ ] Championship 6 rounds and 3 rounds:
  - [ ] round 1 grid varies between championships;
  - [ ] the schedule mixes circuits, environments and times;
  - [ ] the final is billed as the GRAND FINAL, with 7 laps;
  - [ ] the laps key does nothing on the grid.
- [ ] Win a championship: a rival's car in its original colours; that rival drives the
      junker. Enter the won car in a championship and lose it: it goes back to its
      owner.
- [ ] Knockout:
  - [ ] the grid panel says "9 LAPS (FIXED)";
  - [ ] the last car is out at each leader lap;
  - [ ] the red "!" and "YOU ARE IN THE DROP ZONE!" appear when you are last.
- [ ] Battle Royale in several environments:
  - [ ] it ends with one winner;
  - [ ] a hit shows no rival popup, the eliminating hit does;
  - [ ] note whether the pacing is right.
- [ ] Finish first in a single race: celebration, then live spectating with
      provisional standings; Tab skips.

## 6. Multiplayer (two PCs)

- [ ] LAN and internet (`docs/NETWORK_PLAY.md`):
  - [ ] the joiner readies with Fire, the host starts with Fire;
  - [ ] after the results the host continues with Enter;
  - [ ] both see the same environment, time of day, results, damage and jump
        outcomes;
  - [ ] each environment incl. The Raceway at night and Tabletop Mayhem.
- [ ] Pull the cable mid-race: CONNECTION LOST on the other side; Enter / Esc returns.

## 7. Presentation

- [ ] 1280×720, 1920×1080 and a non-16:9 window:
  - [ ] HUD, standings, kill feed, achievement toasts (below the feed), results,
        championship standings and garage are readable and don't overlap;
  - [ ] the TOMBSTONE | K | D heads sit over their numbers, also with two-digit
        counts.
- [ ] Split-screen: both HUDs, compact standings and banners readable.
