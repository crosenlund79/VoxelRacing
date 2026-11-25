VoxelRacing - Prototype 001: The Voxel Experiment
==================================================

HyperCars, rebuilt as a voxel miniature. Portable build: extract the folder
anywhere and run VoxelRacing.exe (VoxelRacing.console.exe shows a log window).
No installation needed.

Controls are HyperCars' (see CONTROLS in the menu). Voxel extras:
  V  cycle the camera: MINIATURE / HIGH / LOW / TOP-DOWN
  G  switch between the voxel world and the original 2D look (A / B)
  L  night lighting on / off (as in HyperCars)

Graphics: Forward+ renderer (Vulkan, falling back to Direct3D 12, then to
OpenGL on older hardware). The voxel world is built when a race loads
(a couple of seconds; "BUILDING THE VOXEL WORLD..." shows meanwhile).

custom/ : put your own art and audio here, exactly as in HyperCars.
