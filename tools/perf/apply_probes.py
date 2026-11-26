#!/usr/bin/env python3
"""DIAGNOSTIC ONLY (Performance Investigation 001).

Inserts PerfProbe timing probes into the game's per-frame functions on the
investigation branch. Idempotent: a file already carrying probes is skipped.
Whole-function probes rename `func NAME(ARGS)` to `func NAME__perf(ARGS)` and
add a wrapper that times it; call-site probes time single statements.
"""
import re, sys, os

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."

WHOLE = [
    ("src/main/main.gd", "_physics_process", "sim.main_tick"),
    ("src/main/main.gd", "_process", "pres.main_process"),
    ("src/driving/car.gd", "_physics_process", "sim.car_physics"),
    ("src/voxel/replay_recorder.gd", "_physics_process", "sim.replay_record"),
    ("src/achievements/achievement_tracker.gd", "_physics_process", "sim.achievements"),
    ("src/camera/follow_camera.gd", "_physics_process", "sim.follow_camera2d"),
    ("src/voxel/voxel_stage.gd", "_process", "pres.stage_total"),
    ("src/voxel/voxel_stage.gd", "_sync_cars", "pres.stage_cars"),
    ("src/voxel/voxel_race_fx.gd", "sync", "pres.race_fx"),
    ("src/voxel/voxel_life.gd", "_process", "pres.life"),
    ("src/voxel/voxel_fx.gd", "_process", "pres.voxel_fx"),
    ("src/voxel/replay_theater.gd", "_process", "pres.replay_theater"),
    ("src/voxel/photo_mode.gd", "_process", "pres.photo_mode"),
    ("src/presentation/lighting_pilot.gd", "_process", "pres.lighting"),
    ("src/presentation/race_effects.gd", "_process", "legacy2d.race_effects"),
    ("src/presentation/jump_view.gd", "_process", "legacy2d.jump_view"),
    ("src/presentation/combat_view.gd", "_process", "legacy2d.combat_view"),
    ("src/presentation/track_scenery.gd", "_process", "legacy2d.track_scenery"),
    ("src/presentation/damage_view.gd", "_process", "legacy2d.damage_view"),
    ("src/presentation/voice_director.gd", "_process", "audio.voice"),
    ("src/presentation/race_audio.gd", "_process", "audio.race"),
    ("src/audio/music_player.gd", "_process", "audio.music"),
    ("src/ui/vr_tips.gd", "_process", "ui.tooltips"),
    ("src/ui/kill_feed.gd", "_process", "ui.kill_feed"),
    ("src/ui/menu_diorama.gd", "_process", "menu.diorama"),
    ("src/ui/voxel_logo.gd", "_process", "menu.logo"),
    ("src/ui/title_screen.gd", "_process", "menu.title"),
    ("src/ui/circuit_preview.gd", "_process", "menu.preview"),
    ("src/ui/loading_race.gd", "_process", "ui.loading"),
    ("src/ui/podium_scene.gd", "_process", "pres.podium"),
    ("src/ui/garage_workshop.gd", "_process", "garage.workshop"),
    ("src/ui/garage_mechanic.gd", "_process", "garage.mechanic"),
    ("src/voxel/voxel_car_damage.gd", "rebuild", "pres.car_remesh"),
    ("src/voxel/voxel_car_damage.gd", "break_to", "pres.car_break"),
    ("src/voxel/voxel_race_fx.gd", "_explode", "pres.car_explode"),
    ("src/voxel/voxel_race_fx.gd", "_spawn_bits", "pres.car_spawn_bits"),
    ("src/voxel/voxel_mesher.gd", "build_mesh", "mesh.build_mesh"),
    ("src/voxel/voxel_fx.gd", "scatter_near", "pres.debris_scatter"),
    ("src/voxel/voxel_fx.gd", "_step_debris", "pres.debris_step"),
    ("src/voxel/voxel_life.gd", "_update_people", "pres.life_people"),
    ("src/ui/circuit_preview.gd", "show_circuit", "menu.preview_show"),
    ("src/presentation/lighting_pilot.gd", "set_enabled", "pres.lighting_set"),
]

# statement-level probes: (file, exact line, probe)
SITES = [
    ("src/main/main.gd", "\t_apply_impacts(step)\n", "sim.impacts"),
    ("src/main/main.gd", "\t_update_progress()\n", "sim.progress"),
    ("src/main/main.gd", "\t_update_levels()\n", "sim.levels"),
    ("src/main/main.gd", "\t_update_jumps(Car.FIXED_STEP)\n", "sim.jumps"),
    ("src/main/main.gd", "\t_debris_tick(step)\n", "sim.debris_traction"),
    ("src/main/main.gd", "\t_drive_cars(step)\n", "sim.ai_drive"),
    ("src/main/main.gd", "\t_update_pits(step)\n", "sim.pits"),
    ("src/main/main.gd", "\t\t_combat_tick(step)\n", "sim.combat"),
    ("src/main/main.gd", "\t\t_update_wreck_passes(step)\n", "sim.wreck_passes"),
    ("src/main/main.gd", "\tsession.tick(step)\n", "sim.session"),
    ("src/main/main.gd", "\t_update_camera_target(step)\n", "sim.camera_target"),
    ("src/main/main.gd", "\t_refresh_hud()\n", "ui.hud"),
    ("src/main/main.gd", "\t_present_levels()\n", "pres.levels2d"),
]

# statement probes are searched from this function's start onwards
SCOPE = {"src/main/main.gd": "_physics_process"}

SIG = re.compile(r"^(static )?func (\w+)\((.*)\)( -> \w+)?:\s*$")


def argnames(args):
    out = []
    for a in [x.strip() for x in args.split(",") if x.strip()]:
        out.append(a.split(":")[0].split("=")[0].strip())
    return ", ".join(out)


def main():
    files = {}
    for f, fn, probe in WHOLE:
        files.setdefault(f, []).append((fn, probe))
    sites = {}
    for f, line, probe in SITES:
        sites.setdefault(f, []).append((line, probe))
    n = 0
    for f in sorted(set(files) | set(sites)):
        p = os.path.join(ROOT, f)
        src = open(p).read()
        k = src.count("var __pt")
        for line, probe in sites.get(f, []):
            if '&"%s"' % probe in src:
                continue
            scope = SCOPE.get(f, "")
            start = src.find("\nfunc %s(" % scope) if scope else 0
            if scope and probe in ("ui.hud", "pres.levels2d"):
                start = src.find("\nfunc _process(")
            pos = src.find(line, max(start, 0))
            if pos < 0:
                print("MISSING site", f, repr(line)); continue
            indent = line[: len(line) - len(line.lstrip("\t"))]
            k += 1
            v = "__pt%d" % k
            src = src[:pos] + "%svar %s := Time.get_ticks_usec()\n%s%sPerfProbe.add(&\"%s\", %s)\n" % (indent, v, line, indent, probe, v) + src[pos + len(line):]
            n += 1
        lines = src.split("\n")
        tail = []
        for fn, probe in files.get(f, []):
            if any(l.startswith("func %s__perf(" % fn) or l.startswith("static func %s__perf(" % fn) for l in lines):
                continue
            for i, l in enumerate(lines):
                m = SIG.match(l)
                if m and m.group(2) == fn:
                    st = m.group(1) or ""
                    ret = m.group(4) or ""
                    lines[i] = "%sfunc %s__perf(%s)%s:" % (st, fn, m.group(3), ret)
                    call = "%s__perf(%s)" % (fn, argnames(m.group(3)))
                    if ret and ret.strip() != "-> void":
                        body = "\tvar __t := Time.get_ticks_usec()\n\tvar __r = %s\n\tPerfProbe.add(&\"%s\", __t)\n\treturn __r" % (call, probe)
                    else:
                        body = "\tvar __t := Time.get_ticks_usec()\n\t%s\n\tPerfProbe.add(&\"%s\", __t)" % (call, probe)
                    tail.append("\n\n## DIAGNOSTIC probe (Performance Investigation 001)\n%sfunc %s(%s)%s:\n%s\n" % (st, fn, m.group(3), ret, body))
                    n += 1
                    break
            else:
                print("MISSING func", f, fn)
        open(p, "w").write("\n".join(lines).rstrip("\n") + "\n" + "".join(tail))
    print("probes inserted:", n)


main()
