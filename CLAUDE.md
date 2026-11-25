# Claude Code — VoxelRacing

VoxelRacing is a creative experiment: HyperCars (crosenlund79/HyperCars,
imported from commit c2fc606) presented as a voxel miniature. The 2D race
simulation is HyperCars' own and should stay unchanged; the voxel
presentation lives in `src/voxel/` and is attached by `VoxelStage` in
`src/main/main.gd`. See the top of `README.md` for how it works.

- Only VoxelRacing is ever written to. HyperCars and SirensWentQuiet are
  read-only references; never push to them or add them as remotes.
- Visual quality and a playable race matter more than test count here; the
  inherited HyperCars rules and docs (`docs/GODOT_CLAUDE_GUIDELINES.md`,
  `docs/PROJECT_BRIEF.md`) still describe the 2D game underneath.
- Godot 4.7.2, Forward+ (with fallbacks). Screenshot / smoke tools are in
  `tools/` (run under Xvfb; see their headers).
