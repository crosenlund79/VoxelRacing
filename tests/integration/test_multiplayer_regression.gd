extends GutTest
## M4 regression gate: single-player and spectator simulation fingerprints
## (fresh processes) recorded at dee9387, before the multiplayer foundation.
## They must never change unless a gameplay change is approved.
## M6 (vehicle damage, approved 2026-11-16) changes races on purpose: the
## pre-M6 fingerprints must still hold with damage switched off (the driving,
## AI and combat simulation are untouched), and the M6 ones with damage on.
## Race experience (approved 2026-11-16): the rivals' personal racing lines,
## wreck awareness, ammo pacing and race-length ammunition change every race,
## so all three sets were re-recorded then (same switches as before; the old
## values are in git history). Each set still isolates its feature: damage=0
## lock=0 contact=0 / lock=0 contact=0 / everything on.

## Re-recorded 2026-11-17 for the human (race-mode) probes only: the approved
## steering precision change ramps the scripted player's key steering. Spectator
## hashes, pit lanes, split sections and lighting change nothing here.
## Re-recorded 2026-11-23 for the armed probes only (all three sets): the
## approved AI ammunition pacing changes when rivals fire. Every unarmed
## probe (driving, racing lines, damage, physics) is unchanged.
const FINGERPRINTS := {
	"mode=race ticks=3600 weapons=0": "3d35204f54580c909e3f004940c57f6d",
	"mode=race ticks=3600 weapons=1 style=1": "c207a150c1e8b4f549cb9c8a5da0e668",
	"mode=spectate ticks=4800 weapons=1": "bc81fdf1a1eaacf3ccafeeb691c0ffdc",
	"mode=spectate ticks=4800 weapons=1 style=1": "4c12e7e20cf23e49c285a6ad3dcd3704",
}


## Recorded at M6 (damage on; the hash also covers every car's condition and DNF).
const M6_FINGERPRINTS := {
	"mode=race ticks=3600 weapons=0": "b37dc17e55f7edd48e25368fda14154c",
	"mode=race ticks=3600 weapons=1 style=1": "44743b95e7a4f51ddeaee267dc66f5b8",
	"mode=spectate ticks=4800 weapons=1": "4cb37484fb6353774653b13589df20db",
	"mode=spectate ticks=4800 weapons=1 style=1": "9f2ab03a6e3a0bbd76cae3465cf50c4f",
}


## Recorded with Weapons Hot (start lock) and rear-quarter contact (2026-11-16),
## everything on. Both change races on purpose (the start is calmer, contacts
## turn cars); with lock=0 contact=0 the M6 values above still hold.
const CURRENT_FINGERPRINTS := {
	"mode=race ticks=3600 weapons=0": "205080edcda1cc16b76e34ce49e603d1",
	"mode=race ticks=3600 weapons=1 style=1": "a15c9340818d734a8f6f779c43f86c8c",
	"mode=spectate ticks=4800 weapons=1": "3561d8026b3e54ae8ca73e12d91ae768",
	"mode=spectate ticks=4800 weapons=1 style=1": "1bb43eab4275a1477556c64a11d38e6e",
}


func test_current_fingerprints() -> void:
	for args in CURRENT_FINGERPRINTS:
		assert_eq(ProbeRunner.run(PackedStringArray(args.split(" "))), CURRENT_FINGERPRINTS[args], args)


func test_single_player_and_spectator_fingerprints_unchanged() -> void:
	for args in FINGERPRINTS:
		assert_eq(ProbeRunner.run(PackedStringArray((args + " damage=0 lock=0 contact=0").split(" "))), FINGERPRINTS[args],
			args + " (damage, weapons lock and contact yaw off)")


func test_m6_damage_fingerprints() -> void:
	for args in M6_FINGERPRINTS:
		assert_eq(ProbeRunner.run(PackedStringArray((args + " lock=0 contact=0").split(" "))), M6_FINGERPRINTS[args], args + " (weapons lock and contact yaw off)")
