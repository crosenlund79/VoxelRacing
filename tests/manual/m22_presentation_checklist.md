# M2.2 — manual presentation checklist (graphics, sound, menus)

Run the project (F5 in Godot 4.7). The game now opens on the title screen. Earlier checklists (`m1`, `m2`, `m21`) still apply to driving, racing and spectating. Listen with speakers or headphones: **the automated checks cannot judge how the audio sounds.**

## Title and menus
- [ ] Title shows the HyperCars logo over the circuit, slowly panning, with the ten cars on the grid; menu music plays.
- [ ] Keyboard / pad navigation works (Up/Down, Enter/Space or pad A; Esc goes back); mouse hover and click work too; each move and select has a soft UI sound.
- [ ] RACE → choose Fire to Accelerate or Fire to Brake → fade to the grid with the GET READY panel.
- [ ] SPECTATE RIVALS starts the rivals' race straight away.
- [ ] SETTINGS: Master, Music, Engine and Effects sliders change the volume immediately; Mute works; values are still there after restarting the game.
- [ ] CONTROLS lists racing and spectator controls and the two race rules.
- [ ] QUIT (and closing the window) exits cleanly.
- [ ] Esc on the grid or results returns to the title.

## Racing presentation
- [ ] GO! banner and start horn when the race starts; race music replaces menu music.
- [ ] Info panel: big position (P3 / 10), lap, time, control mode; the position tower on the left updates live and highlights YOU.
- [ ] Every car is easy to tell apart (colour, shape, roof number; your car has the lightning bolt).
- [ ] Engines rise in pitch with speed and are louder on throttle; tyres squeal and leave fading tyre marks when sliding; smoke when sliding hard; dust when launching.
- [ ] Bumps and barrier hits give a thud and sparks.
- [ ] FINISH! banner, finish jingle and confetti when you finish; the results card shows stars for 1st-3rd, car icons, names with nicknames and gaps to the winner.
- [ ] Scenery (grandstands, trees, flowers, rocks, tyre stacks, waving flags, road wear, grid boxes) never blocks a car or changes the racing line; trees sway gently.
- [ ] The track surface and the cars stay easy to read with all ten cars on screen; the game stays smooth.

## Spectator presentation
- [ ] H hides / shows the history panel while the race keeps running.
- [ ] History rows are striped, the newest race column is highlighted, Tab switches to Position Counts, Left/Right scroll a long history.
- [ ] "NAME WINS!" banner, jingle and confetti for each winner; the results card appears between races.
- [ ] F (fast) turns off tyre marks, smoke and engine sounds while fast, and they return at normal speed.

## Replaceable art and sound (see docs/ASSET_SPECS.md)
- [ ] Put a PNG in `custom/graphics/scenery/tree_round.png`, restart: trees use it. Remove it: the template returns.
- [ ] Put an OGG or WAV in `custom/audio/music/music_race.ogg` (or `.wav`), restart: race music uses it. A broken file falls back with a warning.
- [ ] Exported Windows/Linux build: **pending** (no export approved).
