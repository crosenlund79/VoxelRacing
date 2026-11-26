@echo off
rem VoxelRacing Performance Investigation 001 - DIAGNOSTIC benchmark kit.
rem Runs the measured scenarios with this PC's real GPU and writes CSV / JSON
rem results to the "results" folder next to this file. Takes about 25 minutes.
rem Close other programs first. Do not touch the mouse / keyboard while it runs.
setlocal
set EXE="%~dp0VoxelRacingBench.console.exe"
if not exist %EXE% set EXE="%~dp0VoxelRacingBench.exe"
set OUT=%~dp0results
mkdir "%OUT%" 2>nul
echo Writing system information...
systeminfo > "%OUT%\systeminfo.txt" 2>nul
dxdiag /t "%OUT%\dxdiag.txt"
call :run race_day_720   1280x720  --bench=race --secs=30 --warm=6
call :run race_day_1080  1920x1080 --bench=race --secs=30 --warm=6
call :run race_day_1440  2560x1440 --bench=race --secs=30 --warm=6
call :run race_day_2160  3840x2160 --bench=race --secs=30 --warm=6
call :run race_night_1080 1920x1080 --bench=race --night=1 --secs=30 --warm=6
call :run race_night_1440 2560x1440 --bench=race --night=1 --secs=30 --warm=6
call :run race_day_1080_vsync 1920x1080 --bench=race --vsync=1 --secs=30 --warm=6
call :run race_day_1080_cap60 1920x1080 --bench=race --cap=60 --secs=30 --warm=6
call :run combat_1080    1920x1080 --bench=combat --secs=25
call :run replay_1080    1920x1080 --bench=replay
call :run menu_1080      1920x1080 --bench=menu --secs=20 --warm=5
call :run setup_1080     1920x1080 --bench=setup --warm=5
call :run garage_1080    1920x1080 --bench=garage --warm=5
call :run split_1080     1920x1080 --bench=split --secs=25 --warm=6
call :run env3_night_1080 1920x1080 --bench=race --variant=3 --night=1 --secs=25 --warm=6
call :run env4_night_1080 1920x1080 --bench=race --variant=4 --night=1 --secs=25 --warm=6
call :run env5_day_1080  1920x1080 --bench=race --variant=5 --secs=25 --warm=6
call :run iso_no_shadows_1080 1920x1080 --bench=race --night=1 --secs=25 --warm=6 --iso=no_dir_shadow
call :run iso_no_lights_1080  1920x1080 --bench=race --night=1 --secs=25 --warm=6 --iso=no_omni_spot
call :run iso_no_people_1080  1920x1080 --bench=race --secs=25 --warm=6 --iso=no_people
call :run iso_no_post_1080    1920x1080 --bench=race --secs=25 --warm=6 --iso=no_post
call :run d3d12_day_1080 1920x1080 --bench=race --secs=25 --warm=6 --driver=d3d12
call :run gl_day_1080    1920x1080 --bench=race --secs=25 --warm=6 --driver=gl
call :run gamerace_1080  1920x1080 --bench=gamerace --secs=25 --warm=6
call :run load_1080      1920x1080 --bench=load
call :run long_1080      1920x1080 --bench=long --secs=15 --windows=5 --gap=45
call :run transitions_1080 1920x1080 --bench=transitions --cycles=4
echo.
echo Done. Please zip the "results" folder and send it back.
pause
exit /b

:run
set TAG=%1
set RES=%2
shift
shift
set EXTRA=
set RM=--rendering-method forward_plus
:args
if "%~1"=="" goto go
if "%~1"=="--driver=d3d12" (set RM=--rendering-method forward_plus --rendering-driver d3d12& shift & goto args)
if "%~1"=="--driver=gl" (set RM=--rendering-method gl_compatibility --rendering-driver opengl3& shift & goto args)
set EXTRA=%EXTRA% %1
shift
goto args
:go
echo === %TAG% (%RES%)
%EXE% %RM% --resolution %RES% -- --out="%OUT%" --tag=%TAG% %EXTRA% > "%OUT%\%TAG%_log.txt" 2>&1
exit /b
