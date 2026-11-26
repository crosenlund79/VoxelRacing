#!/usr/bin/env python3
"""DIAGNOSTIC ONLY (Performance Investigation 001).

Reads the PerfBench *_summary.json files in a folder and writes:
  results.csv      one row per run and measured phase (frame stats, CPU probes)
  tables.md        markdown tables used by the report
Usage: analyze.py RAW_DIR OUT_DIR
"""
import json, os, sys, csv, glob

RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

SIM = ["sim.main_tick", "sim.ai_drive", "sim.combat", "sim.replay_record", "sim.progress", "sim.car_physics",
       "sim.pits", "sim.jumps", "sim.debris_traction", "sim.levels", "sim.impacts", "sim.session",
       "sim.camera_target", "sim.wreck_passes", "sim.achievements", "sim.follow_camera2d"]
PRES = ["pres.stage_total", "pres.stage_cars", "pres.race_fx", "pres.voxel_fx", "pres.debris_step", "pres.life",
        "pres.life_people", "pres.main_process", "ui.hud", "pres.lighting", "pres.replay_theater", "pres.photo_mode",
        "pres.car_remesh", "pres.car_break", "pres.car_explode", "pres.car_spawn_bits", "mesh.build_mesh",
        "pres.debris_scatter", "audio.race", "audio.voice", "audio.music", "ui.tooltips", "ui.kill_feed",
        "legacy2d.track_scenery", "legacy2d.race_effects", "legacy2d.combat_view", "legacy2d.damage_view",
        "legacy2d.jump_view", "pres.levels2d", "menu.diorama", "menu.logo", "menu.title", "menu.preview",
        "menu.preview_show", "garage.workshop", "garage.mechanic", "pres.podium", "ui.loading"]

rows = []
for f in sorted(glob.glob(os.path.join(RAW, "*_summary.json"))):
    d = json.load(open(f))
    for ph, s in d["phases"].items():
        if not ph.startswith("measure:"):
            continue
        r = {"tag": d["tag"], "scenario": d["scenario"], "phase": ph[8:], "res": "%dx%d" % tuple(d["window"]),
             "iso": d["args"].get("iso", ""), "variant": d["args"].get("variant", "1"), "night": d["args"].get("night", "0"),
             "layout": d["args"].get("layout", "kestrel_ridge")}
        for k in ["frames", "ticks", "avg_fps", "mean_ms", "median_ms", "p95_ms", "p99_ms", "max_ms", "low1_fps", "stdev_ms",
                  "spikes_2x_median", "render_cpu_ms_mean", "render_gpu_ms_mean", "render_gpu_all_ms_mean", "render_cpu_all_ms_mean", "viewports_mean", "draw_calls_mean", "objects_mean",
                  "primitives_mean", "nodes_mean", "mem_static_mb_mean", "mem_static_mb_max", "video_mem_mb_mean",
                  "video_mem_mb_max", "phys2d_active_mean"]:
            r[k] = s.get(k)
        pr = s.get("probes", {})
        for k in SIM:
            v = pr.get(k, {})
            r["tick:" + k] = v.get("ms_per_tick")
            r["frame:" + k] = v.get("ms_per_frame")
        for k in PRES:
            r["frame:" + k] = pr.get(k, {}).get("ms_per_frame")
        tpf = (r["ticks"] or 0) / max(1, r["frames"] or 1)
        r["ticks_per_frame"] = tpf
        rows.append(r)

keys = []
for r in rows:
    for k in r:
        if k not in keys:
            keys.append(k)
with open(os.path.join(OUT, "results.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=keys)
    w.writeheader()
    for r in rows:
        w.writerow(r)


def fmt(v, n=2):
    if v is None:
        return "-"
    if isinstance(v, float):
        return ("%." + str(n) + "f") % v
    return str(v)


def table(title, sel, cols):
    out = ["### " + title, "", "| " + " | ".join(c[0] for c in cols) + " |", "|" + "---|" * len(cols)]
    for r in sel:
        out.append("| " + " | ".join(fmt(c[1](r)) for c in cols) + " |")
    return "\n".join(out) + "\n\n"


by = {r["tag"] + ":" + r["phase"]: r for r in rows}
md = []
base_cols = [("run", lambda r: r["tag"] + ("" if r["phase"] in ("race",) else " / " + r["phase"])),
             ("res", lambda r: r["res"]), ("frames", lambda r: r["frames"]),
             ("mean ms", lambda r: r["mean_ms"]), ("median", lambda r: r["median_ms"]), ("p95", lambda r: r["p95_ms"]),
             ("p99", lambda r: r["p99_ms"]), ("max", lambda r: r["max_ms"]), ("1% low fps", lambda r: r["low1_fps"]),
             ("GPU ms", lambda r: r["render_gpu_ms_mean"]), ("render CPU ms", lambda r: r["render_cpu_ms_mean"]),
             ("draws", lambda r: r["draw_calls_mean"]), ("prims (k)", lambda r: (r["primitives_mean"] or 0) / 1000),
             ("objects", lambda r: r["objects_mean"]), ("nodes", lambda r: r["nodes_mean"]),
             ("mem MB", lambda r: r["mem_static_mb_mean"]), ("VRAM MB", lambda r: r["video_mem_mb_mean"])]
md.append(table("All measured phases (lavapipe software Vulkan; GPU ms = rasterisation on the CPU)", rows, base_cols))

cpu_cols = [("run", lambda r: r["tag"] + " / " + r["phase"]), ("ticks/frame", lambda r: r["ticks_per_frame"])] + \
    [(k.replace("sim.", ""), (lambda kk: lambda r: r.get("tick:" + kk))(k)) for k in SIM[:10]]
md.append(table("Simulation CPU per 60 Hz tick (ms, release export)", rows, cpu_cols))
pres_cols = [("run", lambda r: r["tag"] + " / " + r["phase"])] + \
    [(k, (lambda kk: lambda r: r.get("frame:" + kk))(k)) for k in PRES[:14]]
md.append(table("Presentation CPU per rendered frame (ms, release export)", rows, pres_cols))
open(os.path.join(OUT, "tables.md"), "w").write("\n".join(md))
print("rows", len(rows), "->", OUT)
