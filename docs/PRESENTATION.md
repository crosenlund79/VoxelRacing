# Presentation & personality (2026-11-23)

Approved 2026-11-23, "HyperCars — Presentation & Personality Pass". Presentation only:
no driving, AI, damage, economy, championship or network rules changed. A race is
bit-identical with presentation on or off; the determinism fingerprint tests confirm
this. Evidence: `docs/artwork/presentation_pass.jpg`, 18 real-game screens.

## One look (the main menu's)

`HyperTheme` gains shared pieces taken from the main menu:
- `style_button`: the wooden buttons, with the main menu's type sizes and margins;
- `heading` / accent rule: a gold title with a thin rule;
- `SHADE`: the dark warm overlay;
- `reveal`: a 0.22 s fade-in.

They are used by the pause menu, the championship standings, the career screen, the
garage, the milestone cards and the race introduction.

- **Pause menu:** the race stays visible, dimmed. A gold heading names the race
  (round, circuit, environment, time, laps); RESUME is the large primary button and
  LEAVE / ABANDON a smaller, separate one. The forfeit confirmation is unchanged.
- **Race introduction:** a card at the bottom centre while on the grid:
  - what the race is (round / mode);
  - where (circuit, environment, time, laps, NO GUNS);
  - in a championship after round 1, the standings that matter, from the real points
    ("Rocco leads the championship - you are 2nd, 7 points behind").

  It never blocks input and fades 2.5 s after GO!.
- **Results:** one outcome line for the player, from the standings only. The tones
  are VICTORY!, SO CLOSE (less than 1 s behind the win), PODIUM, FINISHED P*n*, and
  DNF ("out of the race, no points or prize"). There is no line while spectating.

## Career personality

- **Stage identity:** each stage has a tagline and an accent colour, used on its card,
  its standings and its milestones (`ChampionshipSchedule.career_tagline` /
  `career_accent`):
  - Rookie Cup: green, "Where reputations begin";
  - Pro Series: blue, "The big league";
  - Grand Championship: red-orange, "The ultimate championship".
- **Milestone cards** (`src/ui/milestone_screen.gd`) are short and skippable after
  0.45 s. Each shows the car that matters (CarArt):
  - YOUR CAREER BEGINS / STAGE n OF 3 / THE FINAL STAGE;
  - THE GRAND FINAL (with the real standings);
  - FIRST CAREER VICTORY;
  - *STAGE* CHAMPION with PROMOTED TO THE NEXT STAGE;
  - YOU WON *RIVAL*'S CAR;
  - *RIVAL* WINS THE *STAGE*.

  The ending keeps its own ceremony.
- **Rival reactions** (`src/memory/rival_reactions.gd`): after a championship round,
  at most one rival speaks one line, in that rival's established voice, about a
  notable real fact of the round. The facts, most significant first:
  - a title won over the player, or lost to the player;
  - the championship lead changing hands;
  - a first and second within 0.5 s;
  - 2+ weapon destructions between the player and one rival;
  - a comeback win after a 7th-or-worse round;
  - a winner's slump to 8th or worse;
  - a rival behind the player in every round so far (3+).

  Nobody speaks twice in a row, and most rounds stay silent. The line is shown under
  the standings with the rival's car. There are no portraits and no audio; the AI is
  untouched.

## Battle Royale: the Scrapyard diorama

`CircuitPreview.show_arena` turns the real `ArenaLayout` into a rotating 2.5D
diorama, drawn procedurally:
- the octagonal walls;
- the scrap pile, as stacked wrecks in the rivals' colours;
- the hazard-striped blocks, the crash barriers and the tyre posts;
- the grandstands, and the lamps at night.

It uses the environment's colours and day / night. The grandstand and lamp positions
moved into `ArenaLayout`, so the arena and the preview share one geometry.

## Garage

- **The car being prepared** is the centrepiece: the CarArt picture, so the own car, a
  won rival car, user artwork and Artwork Mode all apply. It stands in a spotlight
  with a gentle sway, with its name.
- **Feedback:** buying, selling, repairing and armour pulse the card or the car row,
  and the money changing hands floats up (−$90 / +$15). Prices and rules are unchanged.

## Visible damage

`fx/car_wear` is a new catalogued, replaceable picture: one scratches / dents / soot
drawing shared by every car. A small shader blends it into each body, only where the
body is painted:
- from 85 % condition it fades in, reaching full at 25 %, with a little desaturation;
- below 50 % there is thin smoke, and the dense smoke when critical;
- the wreck is as before.

No per-car damage drawings are needed, and the effect reads `DamageWorld` without
changing anything.

## Tests

- `tests/integration/test_presentation_pass.gd`: outcome lines, the championship line,
  the introduction, the pause context, the garage centrepiece and feedback, and wear /
  smoke by condition.
- `tests/unit/test_rival_reactions.gd`: facts only, priority, silence, no repeats, and
  every line filled in.
- `tests/unit/test_artwork_inventory.gd`: catalogue ⇄ templates ⇄ user drawings ⇄
  master list / specs, and the wear picture's three-level contract.
- Milestone cards along the whole career: `tests/integration/test_career_flow.gd`.
