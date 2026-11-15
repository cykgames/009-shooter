# 003-shooter — Build Checkpoint (2026-11-15)

## Status: playable mobile MVP v0.1.0, headless-verified, APK exported (local repo only, no remote)

## What was built

Base: nezvers/Godot-GameTemplate (MIT) scaffold, Steam/dev plugins already
stripped. Complete upstream game kept intact: boot -> title -> arena rooms,
EnemyWaveManager + SpawnWaveList waves (3x10 + Big Jelly boss), player dash,
5 weapons, zombies/slims/boss, pickups, HUD, pause/game-over, A* enemy AI.

New work (this checkpoint):

- **Touch twin-stick controls** (`addons/top_down/scripts/ui/touch/`):
  - `Joystick.gd` — adapted from 002-obby (anchored disc, full Vector2,
    radial deadzone, 1.5x grab radius, MAX_DRIFT lean). Constants scaled
    for the 480x270 viewport: RADIUS 40 / KNOB_MAX 26 (was 165/108).
  - `TouchControls.gd` + `scenes/ui/touch_controls.tscn` — instanced in
    `game_hud.tscn`. Left stick = move, right stick = aim + auto-fire
    beyond deadzone, DASH / WPN / pause buttons (1.5x hit radii). All
    routing via `_unhandled_input` with explicit touch-index tracking
    (multi-touch safe); buttons/sticks are MOUSE_FILTER_IGNORE drawing
    surfaces so menu Buttons keep working via emulated mouse. Hidden
    while paused; sticks force-released on pause.
  - `TouchState.gd` — autoload bridge. Latches `touch_active` on Android
    (`OS.has_feature("android")`) or first `InputEventScreenTouch`.
  - `PlayerInput.gd` — when `TouchState.touch_active`, reads virtual
    axes/buttons from TouchState instead of keyboard/mouse/gamepad and
    ignores emulated-mouse aim; desktop path unchanged otherwise.
  - `TouchMenuAdjust.gd` — hides the Controls (keyboard rebinding) button
    in title + pause menus on touch devices.
  - Pause button injects the project's `pause` action (InputEventAction)
    so PausingManager handles submenu depth exactly like the keyboard.
- **Rebrand**: boot/title header "COOL GAME" -> "CYK SHOOTER"; generated
  `icon.png` 192x192 (crosshair); project icon switched to it.
- **Android preset**: `export_presets.cfg` copied from 002-obby with
  `com.cykagent.shooter` / `CykShooter` / `build/003-shooter.apk`.
  arm64-v8a only, etc2=true, immersive, no internet permission, 0.1.0,
  script_export_mode=2 (compiled .gdc in APK).
- **Project settings**: added TouchState autoload; enabled
  `rendering/textures/vram_compression/import_etc2_astc=true` (required
  for Android export). Renderer stays Forward Plus (Vulkan; A54 capable).
- **Headless regression** `tools/test_shooter.tscn/.gd` (pattern:
  002-obby test_joystick): joystick math, real-action movement + dash,
  full touch chain, ArenaEntry trigger, combat to wave advance.
- `.gitignore`: `build/` added. `.import` files (712) now tracked.

## Verification evidence

Godot 4.7.2 stable win64 console binary (absolute tool path kept out of
the repo; referred to as `%GODOT%` below). All commands run from the repo
root; logs under `build/` (gitignored).

1. **Import** — `--headless --path . --import` -> exit 0, 712 `.import`
   files. Log: `build/import.log` (first pass) + `build/import2.log`
   (after ETC2/ASTC enabled). One first-scan error (music OGG referenced
   before its first import existed) resolved on subsequent runs.
2. **Smoke** — `--headless --path . --quit-after 1200` -> exit 0,
   **0 SCRIPT ERROR / Parse Error**; boot flow confirmed:
   `BootPreloader [INFO]: ... DONE` then `Music [INFO]: start - title`.
   Log: `build/smoke.log`. Remaining noise: ~250 "invalid UID ... using
   text path instead" warnings (fresh `.import` UIDs differ from upstream
   references; harmless path fallback) and exit-time "resources still in
   use" cleanup messages (forced-quit autoload teardown, not gameplay).
3. **Gameplay regression** —
   `--headless --fixed-fps 60 --path . res://tools/test_shooter.tscn`
   -> exit 0, `SHOOTER_TEST_PASS`, 0 script errors. Log: `build/regression.log`.
   Key lines:
   ```
   SHOOTER_OK: player moved via 'right' action (51.5 px)
   SHOOTER_OK: dash triggered via action_2
   SHOOTER_OK: touch move axis reaches InputResource
   SHOOTER_OK: touch aim reaches InputResource
   SHOOTER_OK: touch auto-fire while aim held
   SHOOTER_OK: touch release stops auto-fire
   SHOOTER_OK: ArenaEntry body trigger started fight mode
   SHOOTER_OK: wave queue initialized (4 waves)
   SHOOTER_OK: enemies killed (10)
   SHOOTER_OK: wave 1 cleared (kills=10, enemy_count=10)
   SHOOTER_OK: wave counter advanced (wave=1 remaining=3)
   SHOOTER_OK: player survived (hp=135)
   SHOOTER_SUMMARY fails=0 shots=386 hits=265 hit_rate=68.7% kills=10 ...
   SHOOTER_TEST_PASS
   ```
   Re-run after ETC2 re-import: PASS again (shots=395, kills=10, wave=1).
   **Documented harness assists** (game mechanics unmodified):
   - Player HP buffed 50 -> 200 for the combat phase: the ~100-line bot
     cannot out-survive 4-way spawns + slime splits for a full wave at
     normal HP (verified: dies at 18-33 s with 5-7 kills across 3 honest
     bot iterations). All spawn/damage/death/wave logic runs for real.
   - `seed(20261115)` pins wave composition/spread for reproducibility.
   - Aim injected directly into InputResource (headless has no mouse);
     movement/shoot/dash use `Input.action_press` with the project's real
     action names; touch phase drives the actual TouchControls sticks.
4. **APK export** — `--headless --path . --export-debug "Android"
   build/003-shooter.apk` -> exit 0. Log: `build/export.log` (apksigner
   "Signed" + verify DONE). File: `build/003-shooter.apk`,
   **37,726,955 bytes (36.0 MB)**. Verified via zipfile inspection:
   `lib/arm64-v8a/libgodot_android.so` + `libc++_shared.so` only,
   package `com.cykagent.shooter` in AndroidManifest (UTF-16), label
   `CykShooter` in resources.arsc, compiled `.gdc` scripts under assets/,
   embedded PCK (GDPC magic). First export attempt failed: ETC2/ASTC
   import not enabled in project settings -> fixed, re-imported, retried.

## Key decisions / ruled-out alternatives

- **Touch injection point**: TouchState autoload + PlayerInput branch
  (chosen) vs. synthetic InputEvents — the resource path is the game's
  single input abstraction (weapons/dash/AI all read InputResource), so
  injecting there reuses every downstream system with zero duplication.
- **TouchControls as Control inside the HUD CanvasLayer** (chosen) vs.
  separate autoload CanvasLayer — per-room lifetime, pause integration
  via the same pause_resource, no cross-scene state management. First
  draft used a CanvasLayer with cross-node draw calls (invalid in Godot);
  rewritten as a Control drawing its own buttons.
- **Joystick constants scaled, not node-scaled** — keeps touch math in
  viewport pixels (simpler routing, same proven anchored-disc model).
- **Regression weapon = assault rifle** (10 shots/s) via the real
  inventory append path. Gun (2 shots/s) killed too slowly to clear a
  wave in 60 s; bullets fly 120 px/s with +/-5 deg spread, so the bot
  fights inside ~65 px with velocity lead and focus-fires the weakest
  branch (slime = 50 HP + 4x30 HP splits = 170 HP per branch).
- **Bot survival**: escape-direction sampling + post-kill retreat + dash
  escape improved survival 18 s -> 33 s but not enough; HP buff chosen
  over dropping to smoke-only so wave progression stays verified.
- **Renderer**: kept Forward Plus (no headless/import evidence of a
  problem; A54 is Vulkan-capable). Did NOT copy 002-obby's
  gl_compatibility switch.
- **ETC2/ASTC**: project-level import flag required in addition to the
  preset's etc2=true (002-obby already had it; easy to miss).

## Open items / not verified

- **No on-device testing** (per task: phone is shared; parent handles it).
  APK install/run, real multi-touch feel, Vulkan rendering on A54,
  immersive mode, audio on device: all unverified.
- Touch routing tested via stick API + TouchState chain, not real
  InputEventScreenTouch finger streams; title/pause/game-over tap flows
  rely on Godot's emulated-mouse Buttons (standard, but not exercised
  headless).
- Boss wave (Big Jelly), bomb/sword/shotgun weapons, pickups, room
  transitions, game-over flow: not covered by the regression (wave 1
  only). Upstream logic unchanged.
- "invalid UID" warnings: could be silenced by rewriting upstream UID
  references to the freshly generated ones; left as-is (harmless).
- Release keystore (currently debug-signed), difficulty tuning from
  human play, Google Play listing (repo stays local for now).

## Reproduce

```bat
cd <repo-root>
set GODOT=<path-to-Godot_v4.7.2-stable_win64_console.exe>
%GODOT% --headless --path . --import
%GODOT% --headless --path . --quit-after 1200
%GODOT% --headless --fixed-fps 60 --path . res://tools/test_shooter.tscn
%GODOT% --headless --path . --export-debug "Android" build/003-shooter.apk
```

Logs land in `build/` (gitignored): import.log, import2.log, smoke.log,
regression.log, export.log.
