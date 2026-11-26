@echo off
rem VoxelRacing Performance Investigation 001 - DIAGNOSTIC benchmark kit.
rem Runs the measured scenarios with this PC's real GPU and writes CSV / JSON
rem results to the "results" folder next to this file. Takes about 30 minutes.
rem Close other programs first. Do not touch the mouse / keyboard while it runs.
setlocal
cd /d "%~dp0"
set EXE="%~dp0VoxelRacingBench.console.exe"
if not exist %EXE% set EXE="%~dp0VoxelRacingBench.exe"
set OUT=%~dp0results
mkdir "%OUT%" 2>nul
echo Writing system information...
systeminfo > "%OUT%\systeminfo.txt" 2>nul
dxdiag /t "%OUT%\dxdiag.txt"
echo [1/29] race_day_720 (1280x720)
%EXE% --rendering-method forward_plus --resolution 1280x720 -- --out="%OUT%" --tag=race_day_720 --bench=race --secs=30 --warm=6 > "%OUT%\race_day_720_log.txt" 2>&1
echo [2/29] race_day_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=race_day_1080 --bench=race --secs=30 --warm=6 > "%OUT%\race_day_1080_log.txt" 2>&1
echo [3/29] race_day_1440 (2560x1440)
%EXE% --rendering-method forward_plus --resolution 2560x1440 -- --out="%OUT%" --tag=race_day_1440 --bench=race --secs=30 --warm=6 > "%OUT%\race_day_1440_log.txt" 2>&1
echo [4/29] race_day_2160 (3840x2160)
%EXE% --rendering-method forward_plus --resolution 3840x2160 -- --out="%OUT%" --tag=race_day_2160 --bench=race --secs=30 --warm=6 > "%OUT%\race_day_2160_log.txt" 2>&1
echo [5/29] race_night_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=race_night_1080 --bench=race --night=1 --secs=30 --warm=6 > "%OUT%\race_night_1080_log.txt" 2>&1
echo [6/29] race_night_1440 (2560x1440)
%EXE% --rendering-method forward_plus --resolution 2560x1440 -- --out="%OUT%" --tag=race_night_1440 --bench=race --night=1 --secs=30 --warm=6 > "%OUT%\race_night_1440_log.txt" 2>&1
echo [7/29] race_day_1080_vsync (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=race_day_1080_vsync --bench=race --vsync=1 --secs=30 --warm=6 > "%OUT%\race_day_1080_vsync_log.txt" 2>&1
echo [8/29] race_day_1080_cap60 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=race_day_1080_cap60 --bench=race --cap=60 --secs=30 --warm=6 > "%OUT%\race_day_1080_cap60_log.txt" 2>&1
echo [9/29] combat_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=combat_1080 --bench=combat --secs=25 > "%OUT%\combat_1080_log.txt" 2>&1
echo [10/29] replay_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=replay_1080 --bench=replay > "%OUT%\replay_1080_log.txt" 2>&1
echo [11/29] menu_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=menu_1080 --bench=menu --secs=20 --warm=5 > "%OUT%\menu_1080_log.txt" 2>&1
echo [12/29] setup_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=setup_1080 --bench=setup --warm=5 > "%OUT%\setup_1080_log.txt" 2>&1
echo [13/29] garage_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=garage_1080 --bench=garage --warm=5 > "%OUT%\garage_1080_log.txt" 2>&1
echo [14/29] split_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=split_1080 --bench=split --secs=25 --warm=6 > "%OUT%\split_1080_log.txt" 2>&1
echo [15/29] env3_night_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=env3_night_1080 --bench=race --variant=3 --night=1 --secs=25 --warm=6 > "%OUT%\env3_night_1080_log.txt" 2>&1
echo [16/29] env4_night_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=env4_night_1080 --bench=race --variant=4 --night=1 --secs=25 --warm=6 > "%OUT%\env4_night_1080_log.txt" 2>&1
echo [17/29] env5_day_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=env5_day_1080 --bench=race --variant=5 --secs=25 --warm=6 > "%OUT%\env5_day_1080_log.txt" 2>&1
echo [18/29] iso_no_shadows_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_shadows_1080 --bench=race --night=1 --secs=25 --warm=6 --iso=no_dir_shadow > "%OUT%\iso_no_shadows_1080_log.txt" 2>&1
echo [19/29] iso_no_lights_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_lights_1080 --bench=race --night=1 --secs=25 --warm=6 --iso=no_omni_spot > "%OUT%\iso_no_lights_1080_log.txt" 2>&1
echo [20/29] iso_no_people_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_people_1080 --bench=race --secs=25 --warm=6 --iso=no_people > "%OUT%\iso_no_people_1080_log.txt" 2>&1
echo [21/29] iso_no_flowers_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_flowers_1080 --bench=race --secs=25 --warm=6 --iso=no_flowers_grass > "%OUT%\iso_no_flowers_1080_log.txt" 2>&1
echo [22/29] iso_no_ssao_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_ssao_1080 --bench=race --secs=25 --warm=6 --iso=no_ssao > "%OUT%\iso_no_ssao_1080_log.txt" 2>&1
echo [23/29] iso_no_post_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=iso_no_post_1080 --bench=race --secs=25 --warm=6 --iso=no_post > "%OUT%\iso_no_post_1080_log.txt" 2>&1
echo [24/29] d3d12_day_1080 (1920x1080)
%EXE% --rendering-method forward_plus --rendering-driver d3d12 --resolution 1920x1080 -- --out="%OUT%" --tag=d3d12_day_1080 --bench=race --secs=25 --warm=6 > "%OUT%\d3d12_day_1080_log.txt" 2>&1
echo [25/29] gl_day_1080 (1920x1080)
%EXE% --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 -- --out="%OUT%" --tag=gl_day_1080 --bench=race --secs=25 --warm=6 > "%OUT%\gl_day_1080_log.txt" 2>&1
echo [26/29] gamerace_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=gamerace_1080 --bench=gamerace --secs=25 --warm=6 > "%OUT%\gamerace_1080_log.txt" 2>&1
echo [27/29] load_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=load_1080 --bench=load > "%OUT%\load_1080_log.txt" 2>&1
echo [28/29] long_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=long_1080 --bench=long --secs=15 --windows=5 --gap=45 > "%OUT%\long_1080_log.txt" 2>&1
echo [29/29] transitions_1080 (1920x1080)
%EXE% --rendering-method forward_plus --resolution 1920x1080 -- --out="%OUT%" --tag=transitions_1080 --bench=transitions --cycles=4 > "%OUT%\transitions_1080_log.txt" 2>&1
echo.
echo Done. Please zip the "results" folder and send it back.
pause
