# Voice Director — manual playtest checklist

- [ ] Quick race with weapons: get destroyed by a missile or mine → the announcer says "Smoked you" (not every time a car explodes elsewhere).
- [ ] Hit a barrier hard a few times → "U playing bumper cars" sometimes, never on light scrapes.
- [ ] Let Rocco, Nina and Victor pass you → laugh / "Thank you" / "Clean"; the same rival passing again soon is often silent.
- [ ] Passing them yourself, other rivals passing you, and the race start say nothing.
- [ ] Never two voices at once; nothing plays late for something that happened earlier.
- [ ] Voices sound natural at 1.10× (no chipmunk effect); if the pitch shifter colours the sound, try `preserve_pitch = false` or another speed in `default_voice_params.tres`.
- [ ] SETTINGS → VOICE slider and mute work; music and engines dip slightly while someone speaks.
- [ ] Esc menu while a line plays: it waits and continues on RESUME; LEAVE RACE stops it.
- [ ] Spectating: no lines about the followed rival. Couch: one voice for both players. LAN / online: each computer only comments on its own player.
