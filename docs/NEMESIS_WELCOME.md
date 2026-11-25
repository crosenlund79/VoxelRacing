# Nemesis Welcome — the cars remember

Approved 2026-11-17 ("HyperCars — Personality & Polish"). The game remembers a few
real moments between the player and each rival. Now and then a rival greets the
player at the title with a short written taunt about one of them.

The game remembers the events. The rival remembers just enough to tease the player.

## What is remembered (`src/memory/rival_memory.gd`)

| Kind | When | Facts kept |
|---|---|---|
| `took_you_out` | a rival's weapon or collision damage causes the player's DNF | rival, weapon, lap, circuit, laps, mode |
| `you_took_me_out` | the player causes a rival's DNF | the same |
| `beat_you_close` | the rival wins and the player is second, less than 1.0 s behind | rival, gap, circuit |
| `you_beat_me_close` | the player wins and the rival is second, less than 1.0 s behind | rival, gap, circuit |
| `won_my_car` | the player wins the rival's car in a championship | rival |
| `took_car_back` | the rival reclaims its car (Racing for Keeps: a lost or forfeited championship) | rival |

**Sources:**
- **DNFs:** the race's own combat statistics (the tombstone entries of
  `CombatStats`, which already name the attacker and weapon).
- **Close finishes:** the race's finishing times.
- **Cars:** the car collection.

**Which races count:** only the player's own single-player races that reach the
finish: quick, garage and championship rounds. These never count:
- spectating;
- couch, LAN and online races;
- Knockout and Battle Royale;
- a race left early.

**Limits:**
- Rival-against-rival incidents, and DNFs that nobody caused, are not stored.
- Nothing is invented, and nothing is reconstructed from saves made before this
  feature.
- Storage is bounded: `user://rival_memory.cfg` keeps the newest 24 events. A missing
  or broken file is an empty memory, and invalid entries are dropped on load.

## Greetings

- **How often:** on a launch, with a 35 % chance when something is remembered. Never
  on two launches running, and never one of the last three events greeted.
- **Which event:** chosen by significance (DNFs and car changes 3, close finishes 2)
  times recency (×0.8 for each newer event).
- **Presentation** (`src/ui/nemesis_welcome.gd`): a compact panel at the bottom left
  of the title.
  - **The car is the character:** the rival's actual car in its current look (its
    own colours, or the shared junker while the player owns its car; art overrides
    apply).
  - **Text:** the rival's name and nickname, a short opener, its reaction in brackets
    and one written taunt.
  - **Dismissing:** any key, controller button or click dismisses it, and the menus
    still receive that input. It also leaves by itself after 9 s.
- **Taunts** (`src/memory/nemesis_lines.gd`): one per rival and kind, in the rival's
  established voice, filled in from the remembered facts only. Examples:
  - **Hank, a rear-rocket DNF:** "Hey... look who's here!" *(a deep, satisfied laugh)*
    "Still remember those rear rockets?"
  - **Rocco, a mine DNF:** "Lap 4, my mines, and BOOM! Still makes me laugh."
  - **Victor, beaten by 0.3 s:** "Oh. It's you." *(adjusts the gloves)* "0.3 seconds
    at Larkspur Ring. I intend to correct that."
  - **Nina, car reclaimed:** "Collected. Thank you."
  - **Greta, car won by the player:** "My car's service interval is in three races. Do
    not be late."
- **No gameplay effect:** there is no targeting, no buffs and no revenge missions.
  Rivals race exactly as before.

## Audio

Only the user's existing recordings are used, on the Voice bus. The music dips while
they play and the clip stops when the panel is dismissed.

| Rival | Clip (smug greetings only) |
|---|---|
| Rocco | "Rocco - Laughing" (`voice/rocco_laughing`) |
| Nina | "the Hunter - Thank you" (`voice/nina_thank_you`) |
| Victor | "The Professor - Clean" (`voice/victor_clean`) |

Every other greeting is text only. A missing or overridden-away clip leaves the
greeting silent; it never fails.

**Optional recordings the user could supply later** (each would be a one-line entry in
`NemesisLines.SMUG_CLIPS` or a sore-greeting table):
- **Generic opener** "Hey... look who's here!": one take per rival, or the announcer.
- **Laughs or chuckles** for the smug greetings:
  - Hank: deep and satisfied;
  - Ellie: a giggle;
  - Maya: soft;
  - Dante: showy;
  - Greta: dry;
  - Finn: a cackle;
  - Victor: a quiet chuckle.
- **Sore reactions** for when the player beat them: a scoff, grunt or sigh per rival
  (Hank grunt, Rocco snort, Ellie scoff, Dante sigh, Greta "tsk").

## Tests

- **`tests/unit/test_rival_memory.gd`:**
  - attribution, and no invented events;
  - close finishes only;
  - bounded history, saving and loading;
  - old and broken saves;
  - frequency, no repeats, recency weighting;
  - every taunt filled in from facts.
- **`tests/integration/test_nemesis_welcome.gd`:**
  - a real rival's mine DNF is remembered;
  - spectating and leaving early remember nothing;
  - the greeting's real car, name and taunt;
  - the junker for a displaced rival;
  - Rocco's laugh;
  - dismissed by a key, or after the time runs out.
- **`tests/integration/test_championship_flow.gd`:** won and reclaimed cars are
  remembered.
