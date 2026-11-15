# 009-shooter — Build Checkpoint (2026-11-15)

> Renumbered 003 → 009 on 2026-11-15 (serial collision: 003 already taken
> by 003-shmup / 003-outpost from parallel dev waves). Directory, project
> name, export path and docs updated; Android package/label unchanged
> (`com.cykagent.shooter` / `CykShooter`).

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
  `com.cykagent.shooter` / `CykShooter` / `build/009-shooter.apk`.
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
   -> exit 0, `SHOOTER_TEST_PASS`, 0 script errors.
   **Parent acceptance re-run initially FAILED** (worker's PASS was not
   reproducible): the original kiting bot had a movement-gate bug
   (`dir.length() > 1.0` zeroed unit-length escape dirs), a hard position
   clamp that let enemies outside the box stall the wave forever, and
   `seed()` at script start did not pin wave composition (audio/particle
   RNG consumption before spawn is not frame-stable). Harness redesigned
   to a deterministic mechanics test; **3/3 consecutive PASS** after fix:
   ```
   RUN 1: shots=480 hits=300 hit_rate=62.5% kills=10 avg_engage_dist=46px
   RUN 2: shots=315 hits=211 hit_rate=67.0% kills=10 avg_engage_dist=43px
   RUN 3: shots=589 hits=398 hit_rate=67.6% kills=10 avg_engage_dist=46px
   ```
   Logs: `build/verify_run1.log` .. `verify_run3.log` (parent re-run);
   `build/regression.log` (worker's original, superseded).
   Key lines (all runs):
   ```
   SHOOTER_OK: player moved via 'right' action (51.5 px)
   SHOOTER_OK: dash triggered via action_2
   SHOOTER_OK: touch move axis / aim / auto-fire / release reach InputResource
   SHOOTER_OK: ArenaEntry body trigger started fight mode
   SHOOTER_OK: wave queue initialized (4 waves)
   SHOOTER_OK: enemies killed (10)
   SHOOTER_OK: wave 1 cleared / wave counter advanced (wave=1 remaining=3)
   SHOOTER_TEST_PASS
   ```
   **Documented harness assists** (game mechanics unmodified):
   - Combat phase = point-blank hunt: player teleports beside the nearest
     enemy when >55 px away (offset toward arena center), so the test does
     not depend on bot navigation or spawn positions.
   - Player HP 50 -> 500, refilled every frame (god mode): enemy damage
     still applies; player death cannot interrupt the mechanics test.
   - `seed(20261115)` re-applied immediately before the ArenaEntry trigger
     to pin wave composition.
   - Aim injected directly into InputResource (headless has no mouse);
     movement/shoot/dash use the project's real Input actions; the touch
     phase drives the actual TouchControls sticks.
   - Combat budget 90 s; wave 1 (10 kills) clears in ~31-59 s across runs.
4. **APK export** — `--headless --path . --export-debug "Android"
   build/009-shooter.apk` -> exit 0. Log: `build/export.log` (apksigner
   "Signed" + verify DONE). File: `build/009-shooter.apk`,
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
  inventory append path. Gun (2 shots/s) killed too slowly; bullets fly
  120 px/s with +/-5 deg spread, so the harness fights point-blank
  (~35-55 px) with velocity lead (clamp 0.6 s).
- **Harness redesign (parent acceptance)**: the original survival-kiting
  bot was flaky (movement-gate bug, hard position clamp, unpinned RNG) —
  worker PASS did not reproduce. Replaced with a deterministic
  point-blank hunt + god-mode HP refill: verifies spawn/damage/death/
  split/wave mechanics without testing bot skill. Player navigation and
  survival are NOT covered by this regression (documented gap).
- **Renderer**: kept Forward Plus (no headless/import evidence of a
  problem; A54 is Vulkan-capable). Did NOT copy 002-obby's
  gl_compatibility switch.
- **ETC2/ASTC**: project-level import flag required in addition to the
  preset's etc2=true (002-obby already had it; easy to miss).

## Open items / not verified

- Player survival/navigation not regression-covered (harness god mode +
  teleport); human playtest pending.
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
%GODOT% --headless --path . --export-debug "Android" build/009-shooter.apk
```

Logs land in `build/` (gitignored): import.log, import2.log, smoke.log,
regression.log, export.log.

## A57 on-device test (2026-11-15 ~21:00-21:15, cykbot1)

Device: A57 `SM-A576B`, WiFi adb `<DEVICE_WIFI_ADB>` (USB also online).
Install needs `--no-incremental` (incremental install fails silently over
WiFi adb; adb daemon also restarted once mid-session, reconnect needed).

Verified on device:
- Install + launch OK. Godot 4.7.2 / Vulkan 1.4.304 Forward Mobile /
  Samsung Xclipse 550. **0 script errors** in logcat.
- Human play captured in logcat: tap 20:53:53 -> title music ("Lost
  Hope.ogg") switched to game music ("Deeper Into the Dungeon.ogg") =
  New Game pressed; ~17s play; touch events reach GodotInputHandler.
- Rendering OK: arena, player, HUD (HP 50/50, wave labels), both
  joysticks + WPN/DASH/pause all draw. Title screen "CYK SHOOTER" +
  New Game/Options/Quit renders after reinstall.

BUG FOUND + FIXED — wide-aspect touch layout:
- Symptom: right (aim) joystick rendered at ~52% screen width (bottom
  CENTER), not bottom-right. Measured knob centers on 2340x1080:
  left (326,828), right (1212,826).
- Cause: layout hard-coded for 480-wide 16:9 design. A57 is 19.5:9;
  `stretch/aspect="keep_height"` expands design width to 585, but the
  AimStick zone (240..480) and DASH/WPN/pause centers were fixed, so the
  right cluster floated near center instead of tracking the right edge.
  Also the first installed APK (built 20:03) predated the touch commit
  (20:08) — stale.
- Fix: `TouchControls.gd` now right-anchors at runtime from `size.x`:
  `dash_center=(w-36,122)`, `switch_center=(w-124,122)`,
  `pause_center=(w-28,18)`, AimStick zone `position=(w-240,120)`
  `size=(240,150)`. Re-layout on first valid size + any width change
  (`_physics_process`). At w=480 (16:9) identical to original.
- Regression: `build/verify_layout_fix.log` = SHOOTER_TEST_PASS
  (fails=0, kills=10, wave advanced, full touch chain). Rebuilt APK
  21:13 (debug-signed, apksigner verified), reinstalled, title OK.

OPEN (needs phone screen free — user was actively using A57, kept
returning to launcher; automated in-game touch test could not complete):
1. Visual confirm of new right-anchored layout IN-GAME on A57 (expected
   aim knob ~89% width). Math + headless confirm; on-device in-game
   screenshot not yet captured.
2. Real finger move/shoot/dash feel (human playtest).
3. **Green/white vertical stripes at screen bottom** (below arena, in
   the void): no "grass" asset in project; ScreenEffects is only a
   transparent flash ColorRect (no shader). Suspect background
   FloorLayer TileMap mobile-Vulkan artifact OR a tileset texture —
   UNCONFIRMED. Next: compare desktop vs mobile render of room_start,
   or toggle Background/FloorLayer to isolate.

Evidence: `build/a57_launch.log`, `build/a57_full.log`,
`build/verify_layout_fix.log`, `build/export_layout_fix.log`;
screenshots `agent-workspace/artifacts/tmp/a57_shot1-5.png`
(shot2/3 = old APK in-game w/ stripes + misplaced stick; shot4 = new
APK title; shot5 = launcher, user took phone). Measurement scripts:
`artifacts/tmp/measure_sticks*.py`.

Reproduce layout fix verify:
```bat
%GODOT% --headless --fixed-fps 60 --path . res://tools/test_shooter.tscn
%GODOT% --headless --path . --export-debug "Android" build/009-shooter.apk
adb -s <DEVICE_WIFI_ADB> install -r --no-incremental build/009-shooter.apk
```

## Renumber 003 → 009 verify (2026-11-15 ~21:30, cykbot1)

- Directory `projects/003-shooter` → `projects/009-shooter`; string rename
  in project.godot / export_presets.cfg / README / docs / tools harness;
  residual grep for `003-shooter` in project text = 0.
- Headless regression after rename: `build/verify_rename.log` =
  SHOOTER_TEST_PASS, fails=0, kills=10, wave advanced, full touch chain.
- Re-export: `build/export_rename.log` apksigner "Signed";
  `build/009-shooter.apk` = 37,813,170 bytes. Package/label unchanged.
- GitHub org serials at rename time: 001/002/004/005/006/008 taken
  (008-shmup = the other wave's shmup, already renumbered on GitHub);
  009 free. Catalog row for this game not added yet (still unpublished).
- A57 still has the pre-rename install (same package `com.cykagent.shooter`);
  `install -r --no-incremental build/009-shooter.apk` updates it in place.

## Author credit + handoff docs (2026-11-15 ~22:10, cykbot1)

- In-game: "by cykbot1" under the CYK SHOOTER header on title.tscn (Header
  CenterContainer -> VBoxContainer + Author label). project.godot gained
  config/description with author + base attribution.
- README: author in Credits + Handoff/debugging section (touch-layer map,
  harness assists, known issues incl. stripes + right-stick visual confirm).
- Sanitized this file for future publication: A57 WiFi adb IP ->
  `<DEVICE_WIFI_ADB>`, agent workspace path -> `agent-workspace` (device
  facts stay in MEMORY.md only).
- Verify: `build/verify_author_smoke.log` boots to title (Music start -
  title), 0 parse/script errors; `build/verify_author_reg.log` =
  SHOOTER_TEST_PASS (kills=10, wave advanced, full touch chain).
- APK rebuilt with credit: `build/export_author.log`; A57 install still
  pending owner go-ahead.
- Lineage fix (same evening): the README joystick credit originally said
  `002-obby` was "same author, MIT" — wrong on both counts: 001/002 are
  by cykbot9 (per the cykgames catalog and owner), and 002 has no LICENSE
  file. Corrected to "(by cykbot9)"; 009 itself remains cykbot1.
