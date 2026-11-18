# Project5

Godot **4.7.2** project using the **Compatibility** renderer. Rocky's desktop slice is playable: Player Stats, workout, Penalty Zone, and Practice Mode. Quest controller support is implemented but awaits an Android build and headset acceptance testing.

## Play in a browser

The GitHub Pages address is **https://shartley.github.io/Project5/** once Pages is enabled and the deployment completes. Click **Play in browser**, then choose an activity. Use a desktop browser with WebGL 2, WebAssembly, a keyboard, and a mouse. The browser build includes the F1 test panel and the same workout, stats, practice, and Penalty Zone as the desktop build.

Escape releases the mouse and pauses the game. Click **Resume** to capture it again; switching tabs also pauses gameplay. Progress lasts until the page is reloaded. Quest/OpenXR testing uses the native game described below.

### One-time GitHub Pages setup

A repository administrator must open [Settings > Pages](https://github.com/Shartley/Project5/settings/pages) and set **Build and deployment > Source** to **GitHub Actions**. Then run [Build and deploy Godot to GitHub Pages](https://github.com/Shartley/Project5/actions/workflows/pages.yml) from the Actions tab, or push to `main`.

The workflow downloads official Godot 4.7.2 binaries and the matching web template, verifies their SHA-512 checksums, runs the gameplay tests, exports the game, and deploys it. Future pushes to `main` update the site automatically. If deployment reports that Pages cannot be found, enable the setting above and rerun the workflow.

The **Web** preset uses a single thread and the Compatibility renderer, so it works on GitHub Pages without special cross-origin headers. Generated binaries are uploaded as a Pages artifact instead of being committed to the repository.

### Test the web export locally

Install the matching Godot 4.7.2 web export templates from **Editor > Manage Export Templates**, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode WebExport
python -m http.server 8065 --bind 127.0.0.1 --directory exports/web
```

Open **http://127.0.0.1:8065/**. Serve the export over HTTP; opening `index.html` directly from disk will not load the game. Stop the local server with Ctrl+C.

## Open the project

1. In Godot 4.7.2, select **Import** and choose `project.godot`.
2. Allow the initial import to finish, then press **F5**.
3. Choose **Begin daily workout**, **Training**, or **Enter chamber**.
4. Press **F1** for test controls. No headset or MCP connection is needed for desktop play.

Progress lasts for the current launch. F1 > **Reset entire session** restores the starting state. The 3D rooms, player rigs, dagger, and attackers are simple stand-ins so Rocky's work is testable independently of Rickey's combat and Samaii's gates/extraction.

## Desktop controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift | Sprint; adds Fatigue |
| Left click | Light dagger attack |
| Right click / hold | Parry / block |
| Space | Dash; defaults backward without a movement key |
| E | Start workout while on the blue pad |
| Space / J or K during workout | Squat / punch on the beat |
| Tab | Stats, permanent point spending, and potions |
| 1 / 2 / 3 | Health potion / mana potion / Fatigue tonic |
| Esc | Pause; Training in hub, Abandon during workout, Leave in training |
| F1 | Debug test panel |

The pause and status menus freeze gameplay. Close them to resume healing, recovery, workout beats, and enemy attacks. Move the mouse to aim the dagger at enemies. Training enemies and the player are invulnerable; normal Fatigue rules still apply.

## Quick test walkthrough

1. **Workout:** choose Begin daily workout. Press Space on the countdown's NOW beat for five squats, J or K for ten punches, then repeat. All 30 reps award three points, full HP, and portal access. A missed beat simply repeats the rep. Tab lets you spend the points.
2. **Resources:** F1 > Take 25 damage, then close and press 1. HP restores over two seconds. Use Empty MP and Fatigue 100 to test mana recovery and exhaustion. At 100 Fatigue, sprint/dash remain locked until it is below 50. F1 > Level 5 / low HP tests the heartbeat and mitigation.
3. **Practice:** Esc > Training. Select one or two opponents and 100%, 75%, or 50% wind-up speed. Press RMB during the last 150 ms of a wind-up (Perception increases this). Ten attacks produce a report. Seven Perfect parries at 100% against one type award one point and +20 ms versus that type, once per session.
4. **Fast mastery check:** F1 > Set up 6 Perfect / 3 late round. Parry the next Goblin attack. F1 also simulates gate clears and stored shadows to test the unlocked enemy catalog.
5. **Penalty:** reset, begin a workout, and choose Esc > Abandon. Survive 180 seconds; one Centipede spawns every 15 seconds, with at most four alive. F1 > Advance Penalty clock 30 seconds skips waiting while retaining the production duration. Survival grants 50 XP; death grants none. Both return to the hub and open portals.
6. **Reset:** F1 > Reset entire session clears XP, stats, inventory, workout status, unlocks, and mastery.

Test actions display **TEST STATE MODIFIED**. Portal lights reflect progression; full dungeon travel is reserved for Samaii's integration.

## Launch and automated checks

Run from the repository folder in PowerShell:

```powershell
# Default keyboard/mouse game
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Desktop

# Deterministic gameplay, integration, and simulated-controller checks
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Tests

# Rendered game with real keyboard/mouse events and visual captures
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode VisualTests

# Desktop view with the simulated-XR indicator; replay gestures using F1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode SimulatedXR
```

The process-only PowerShell allowance is needed on machines that disable local scripts; it does not change the machine's execution policy. The launcher finds Godot on PATH or in the installation discovered on Rocky's computer. Else pass `-GodotExe 'C:\path\to\Godot_console.exe'` or set `GODOT_BIN`.

Tests require no third-party test framework and exit nonzero on failed assertions or GDScript runtime errors. Logs and visual captures are in ignored `.godot/` (`rocky-run.log`, `qa-*.png`). Simulated XR tests feed tracking-space poses through the shared gesture detector and the actual rig adapter; they do not validate stereoscopic rendering or headset comfort.

## Quest testing

Tracked Quest 3/3S controllers are the target. Bare-hand tracking and passthrough are outside this slice. The independent hub is virtual; production passthrough and player rigs can replace the stand-ins through the interfaces in [the handoff](docs/ROCKY_INTEGRATION.md).

**PC / Quest Link:** connect the headset, start Quest Link, and use Meta's active OpenXR runtime. Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode XR
```

If OpenXR cannot initialize, the game shows a message and uses desktop controls. That fallback does not count as a successful XR test.

**Native Quest:** install the matching Godot 4.7.2 Android export templates, OpenJDK 17, and the Android SDK. Set the SDK and Java locations under **Editor Settings > Export > Android**, and set `ANDROID_HOME` and `JAVA_HOME` for the launcher checks. The exact SDK packages are listed in [Godot's Android setup guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html). Enable headset developer mode and authorize the USB debugging connection.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode QuestCheck
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode QuestExport
```

The **Quest Debug** Android preset targets ARM64 and core OpenXR using Godot's prebuilt APK template. It does not require the optional vendor plugin for this basic controller slice. Output is `exports/awakening-quest.apk`. Use Godot's one-click deploy or install that APK with the Android SDK's `adb`. See [Godot's Android XR deployment guide](https://docs.godotengine.org/en/stable/tutorials/xr/deploying_to_android.html).

| Quest input | Action |
| --- | --- |
| Left stick / click | Move / sprint outside hub |
| Right stick | 45-degree snap turn; scroll when a menu is open |
| Menu / X / A | Pause / stats / start workout |
| Right aim ray + trigger, or controller tip poke | Select menu buttons |
| Headset height | Squat below 80% of calibrated height, then above 95%, taking at least 0.8 seconds |
| Controller strike on glowing pad | Punch at 2.5 m/s or faster |
| Right grip and blade contact | Block; a moving blade at 2 m/s within the parry window earns Perfect |
| Left grip + 0.25 m lunge in 0.2 seconds | Dash |
| Stats > Hold potion, then left grip + bottle to mouth | Consume potion |

The left wrist displays HP, MP, and Fatigue. Recenter/tracking loss clears gesture history. Menus pause gameplay, and controller-tracking loss opens the pause menu. Stand fully upright before starting a workout to calibrate height.

**Current validation:** desktop and simulated input have been tested. This machine is missing Android export templates, Android SDK, and Java. No APK or real-headset performance result is claimed. On Quest, verify wrist/menu readability, pokes/rays, all gestures, two-enemy parries, tracking loss/recenter, scene transitions, and a stable 72 FPS before marking XR accepted.

## Project structure

- `scripts/player_stats.gd` and `scripts/progress.gd`: shared session autoloads.
- `scripts/models/`: deterministic workout, practice, penalty, and gesture logic.
- `scripts/main.gd`: content transitions and combat/input adapters.
- `scripts/player_rig.gd`, `scripts/test_enemy.gd`, `scripts/world_builder.gd`: replaceable stand-ins.
- `scripts/system_ui.gd`, `scripts/system_audio.gd`: shared presentation.
- `resources/`: seven enemy definitions and the Quest action map.
- `tests/`: numerical, integration, simulated-controller, and rendered-input checks.

The [implementation plan](docs/ROCKY_IMPLEMENTATION_PLAN.md) records the original scope and defaults. The [integration handoff](docs/ROCKY_INTEGRATION.md) describes the actual APIs and limitations. Generated caches and exported builds are excluded from version control.

## Team

| Name | GitHub |
| --- | --- |
| Rickey Johnson | [rickeyjohnson](https://github.com/rickeyjohnson) |
