extends Node
## Headless gameplay regression for 003-shooter.
## Loads arena room_0 directly, then verifies:
##   1. Joystick output math (adapted 480x270 constants)
##   2. Player movement via the project's real Input actions
##   3. Dash (action_2) triggers the dash resource
##   4. Touch chain: TouchControls sticks -> TouchState -> PlayerInput
##      -> InputResource (auto-fire included)
##   5. ArenaEntry area triggers fight mode (real ArenaStarter path)
##   6. Combat: enemies spawn, shots fire, enemies die, wave counter advances
## Aim is injected straight into InputResource (headless has no mouse);
## movement/shoot/dash go through Input.action_press with the project's
## actual action names registered by ActionResource at boot.
## HARNESS ASSIST: player HP is buffed 50 -> 200 for the combat phase (the
## simple bot cannot survive a full wave otherwise); all enemy/combat/wave
## mechanics run unmodified. RNG is seeded for reproducibility.
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/test_shooter.tscn
## Prints SHOOTER_TEST_PASS / SHOOTER_TEST_FAIL, exit code 0 / 1.

const ROOM_PATH := "res://addons/top_down/scenes/levels/room_0.tscn"
const ACTION_RES_PATH := "res://addons/top_down/resources/global_resources/action_resource.tres"
const PLAYER_REF_PATH := "res://addons/top_down/resources/ReferenceNodeResources/player_reference.tres"
const WEAPON_DB_PATH := "res://addons/top_down/resources/ItemCollectionResource/weapon_database.tres"
const FIGHT_MODE_PATH := "res://addons/top_down/resources/arena_resources/fight_mode_resource.tres"
const ENEMY_COUNT_PATH := "res://addons/top_down/resources/arena_resources/enemy_count_resource.tres"
const WAVE_NUMBER_PATH := "res://addons/top_down/resources/arena_resources/wave_number_resource.tres"
const REMAINING_PATH := "res://addons/top_down/resources/arena_resources/remaining_wave_count_resource.tres"

const ARENA_CENTER := Vector2(460, 158)
## Thin trigger strip south of the north door (room_0 ArenaEntry polygon 1).
const ENTRY_POINT := Vector2(315, 60)
const COMBAT_MAX_SECS := 60.0

var _fails := 0
var _shots := 0
var _kills := 0
var _hits := 0
var _dist_sum := 0.0
var _dist_n := 0


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		print("SHOOTER_FAIL: ", what)
	else:
		print("SHOOTER_OK: ", what)


func _ready() -> void:
	# Watchdog: never hang headless CI even if the coroutine dies on an error.
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("SHOOTER_TEST_FAIL watchdog timeout")
		get_tree().quit(1))
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _secs(s: float) -> void:
	await _frames(int(s * 60.0))


func _set_move(dir: Vector2) -> void:
	_set_action("left", dir.x < -0.35)
	_set_action("right", dir.x > 0.35)
	_set_action("up", dir.y < -0.35)
	_set_action("down", dir.y > 0.35)


func _set_action(action: StringName, pressed: bool) -> void:
	if pressed:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	else:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _run() -> void:
	# Pin the global RNG so wave composition / spread are reproducible.
	seed(20261115)
	# --- 1. Joystick math (scaled constants: KNOB_MAX 26, deadzone 0.12) ---
	_expect(Joystick.compute_output(Vector2.ZERO) == Vector2.ZERO, "joystick zero input")
	_expect(Joystick.compute_output(Vector2(2, 0)) == Vector2.ZERO, "joystick deadzone 2px")
	_expect(Joystick.compute_output(Vector2(26, 0)).distance_to(Vector2(1, 0)) < 0.001, "joystick full right")
	_expect(Joystick.compute_output(Vector2(-26, 0)).distance_to(Vector2(-1, 0)) < 0.001, "joystick full left")
	_expect(Joystick.compute_output(Vector2(0, -26)).distance_to(Vector2(0, -1)) < 0.001, "joystick full up")
	_expect(Joystick.compute_output(Vector2(300, 0)).distance_to(Vector2(1, 0)) < 0.001, "joystick overtravel clamped")
	var diag := Joystick.compute_output(Vector2(13, 13))
	_expect(absf(diag.x - diag.y) < 0.001 and diag.length() > 0.6 and diag.length() < 0.75, "joystick diagonal rescale")
	var prev := 0.0
	for i in range(0, 27):
		var m := Joystick.compute_output(Vector2(i, 0)).x
		_expect(m >= prev - 0.0001, "joystick monotonic at %d" % i)
		prev = m
	var joy := Joystick.new()
	joy.size = Vector2(240, 150)
	joy.home_center = Vector2(66, 82)
	add_child(joy)
	var home := joy.home_center
	joy.press_at(home, 0)
	_expect(joy.active and joy.output == Vector2.ZERO, "joystick center press = zero")
	joy.drag_to(home + Vector2(26, 0))
	_expect(absf(joy.output.x - 1.0) < 0.001, "joystick drag right -> x=1")
	joy.drag_to(home + Vector2(200, 0))
	_expect(absf(joy.output.x - 1.0) < 0.001, "joystick far drag keeps full magnitude")
	_expect(joy.center().distance_to(home) <= Joystick.MAX_DRIFT + 0.001, "joystick disc stays anchored")
	joy.release_touch()
	_expect(not joy.active and joy.output == Vector2.ZERO, "joystick release zeroes output")
	joy.queue_free()

	# --- 2. Register input actions exactly like the boot screen does ---
	var action_res: ActionResource = load(ACTION_RES_PATH)
	action_res.load_resource()
	_expect(InputMap.has_action(action_res.action_1_action), "actions registered (action_1)")
	_expect(InputMap.has_action(action_res.pause_action), "actions registered (pause)")

	# --- 3. Load the arena room ---
	var room: Node = load(ROOM_PATH).instantiate()
	add_child(room)
	await _frames(10)

	var player_ref: ReferenceNodeResource = load(PLAYER_REF_PATH)
	var player: Node2D = player_ref.node
	_expect(player != null, "player spawned in room_0")
	if player == null:
		_finish()
		return
	var rn: ResourceNode = player.get_node("ResourceNode")
	var input_res: InputResource = rn.get_resource("input")
	var health: HealthResource = rn.get_resource("health")
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")

	# Equip the assault rifle (same inventory path the pickups use; 10 shots/s
	# makes the bot's kill rate representative of real play).
	var db: ItemCollectionResource = load(WEAPON_DB_PATH)
	var inventory: ItemCollectionResource = rn.get_resource("weapons")
	inventory.append(db.list[2])
	await _frames(2)
	_expect(weapon_manager.current_weapon != null, "assault rifle equipped via inventory")
	if weapon_manager.current_weapon == null:
		_finish()
		return
	var trigger: WeaponTrigger = weapon_manager.current_weapon.get_node("WeaponTrigger")
	trigger.shoot_event.connect(func() -> void: _shots += 1)
	# Diagnostic: count landed hits through the weapon's damage report callback.
	var dd: DamageDataResource = weapon_manager.current_weapon.damage_data_resource
	var orig_cb: Callable = dd.report_callback
	dd.report_callback = func(data: DamageDataResource) -> void:
		_hits += 1
		if orig_cb.is_valid():
			orig_cb.call(data)

	var spawner: EnemySpawner = room.get_node("EnemyManager/EnemySpawner")
	spawner.enemy_killed.connect(func(_e: ActiveEnemy) -> void: _kills += 1)

	# --- 4. Movement through real actions ---
	var p0: Vector2 = player.global_position
	Input.action_press("right")
	await _secs(1.0)
	Input.action_release("right")
	var moved := player.global_position.distance_to(p0)
	_expect(moved > 20.0, "player moved via 'right' action (%.1f px)" % moved)

	# --- 5. Dash (needs a held movement axis) ---
	var dash_bool: BoolResource = rn.get_resource("dash")
	var dash_seen := false
	Input.action_press("up")
	Input.action_press("action_2")
	for i in range(30):
		await get_tree().physics_frame
		if dash_bool.value:
			dash_seen = true
	Input.action_release("action_2")
	Input.action_release("up")
	_expect(dash_seen, "dash triggered via action_2")

	# --- 6. Touch chain: sticks -> TouchState -> PlayerInput -> InputResource ---
	var touch_controls: TouchControls = room.get_node("UI/TouchControls")
	_expect(touch_controls != null, "TouchControls present in HUD")
	TouchState.touch_active = true
	await _frames(2)
	_expect(touch_controls.visible, "touch UI shows when touch_active")
	touch_controls.move_stick.press_at(touch_controls.move_stick.home_center, 900)
	touch_controls.move_stick.drag_to(touch_controls.move_stick.home_center + Vector2(26, 0))
	touch_controls.aim_stick.press_at(touch_controls.aim_stick.home_center, 901)
	touch_controls.aim_stick.drag_to(touch_controls.aim_stick.home_center + Vector2(26, 0))
	await _frames(3)
	_expect(input_res.axis.distance_to(Vector2.RIGHT) < 0.01, "touch move axis reaches InputResource")
	_expect(input_res.aim_direction.distance_to(Vector2.RIGHT) < 0.01, "touch aim reaches InputResource")
	_expect(input_res.action_1 == true, "touch auto-fire while aim held")
	touch_controls.move_stick.release_touch()
	touch_controls.aim_stick.release_touch()
	await _frames(3)
	_expect(input_res.axis == Vector2.ZERO, "touch release zeroes movement")
	_expect(input_res.action_1 == false, "touch release stops auto-fire")
	TouchState.touch_active = false
	await _frames(2)

	# --- 7. ArenaEntry trigger (real ArenaStarter path) ---
	var fight_mode: BoolResource = load(FIGHT_MODE_PATH)
	_expect(fight_mode.value == false, "fight mode off before entry")
	player.global_position = ENTRY_POINT
	await _frames(10)
	_expect(fight_mode.value == true, "ArenaEntry body trigger started fight mode")
	player.global_position = ARENA_CENTER
	await _frames(2)

	# --- 8. Combat: auto-aim nearest enemy (with projectile lead), kite, hold fire ---
	# HARNESS ASSIST (documented): the simple bot cannot out-survive 4-way
	# spawns + slime splits for a full wave, so player HP is buffed 50 -> 200.
	# Every combat mechanic (spawn, damage, death, drops, wave counting) runs
	# unmodified; only the bot's survivability is assisted.
	health.max_hp = 200.0
	health.hp = 200.0
	print("SHOOTER_NOTE: harness buffs player HP 50 -> 200 (bot survival assist)")
	var wave_number: IntResource = load(WAVE_NUMBER_PATH)
	var remaining: IntResource = load(REMAINING_PATH)
	var enemy_count: IntResource = load(ENEMY_COUNT_PATH)
	_expect(remaining.value == 4, "wave queue initialized (4 waves)")
	Input.action_press("action_1")
	var max_active := 0
	var frames := 0
	var max_frames := int(COMBAT_MAX_SECS * 60.0)
	var last_report := 0
	var enemy_prev: Dictionary = {}
	var last_kills := 0
	var retreat_until := 0
	var dash_ability: DashAbility = player.get_node("DashAbility")
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		if health.is_dead:
			break
		var nearest: Node2D = null
		var nd := 1e9
		var target: Node2D = null
		var target_hp := 1e9
		var target_dist := 1e9
		var threat_sum := Vector2.ZERO
		var threat_count := 0
		for e in ActiveEnemy.active_instances:
			if not is_instance_valid(e):
				continue
			var d: float = e.global_position.distance_to(player.global_position)
			if d < nd:
				nd = d
				nearest = e
			if d < 60.0:
				threat_sum += e.global_position
				threat_count += 1
			# Focus fire: finish the weakest branch in range first (slimes
			# split into 4 smalls, so spreading damage prolongs every fight).
			if d < 100.0:
				var ern: ResourceNode = e.get_node_or_null("ResourceNode")
				if ern == null:
					continue
				var eh: HealthResource = ern.get_resource("health")
				if eh != null and eh.hp < target_hp:
					target_hp = eh.hp
					target = e
					target_dist = d
		max_active = maxi(max_active, ActiveEnemy.active_instances.size())
		if target == null:
			target = nearest
			target_dist = nd
		if target != null:
			_dist_sum += target_dist
			_dist_n += 1
			# Bullets fly at 120 px/s; lead the target using its measured velocity.
			var vel := Vector2.ZERO
			if enemy_prev.has(target):
				vel = (target.global_position - enemy_prev[target]) * 60.0
			var lead := clampf(target_dist / 120.0, 0.0, 0.4)
			var aim_point := target.global_position + vel * lead
			input_res.set_aim_direction((aim_point - player.global_position).normalized())
		for e in ActiveEnemy.active_instances:
			if is_instance_valid(e):
				enemy_prev[e] = e.global_position
		# Bot policy: fight inside ~65px (weapon spread is +/-5 deg, so long
		# shots miss). When threatened, sample 16 escape directions and pick
		# the one maximizing distance to the nearest enemy (slime splits spawn
		# 4 fresh smalls point-blank on every slime kill -> retreat after kills).
		if _kills > last_kills:
			last_kills = _kills
			retreat_until = frames + 30
		var dir := Vector2.ZERO
		var threatened := nd < 50.0 or frames < retreat_until
		if threatened and nearest != null:
			var best_score := -1e9
			for i in range(16):
				var cand := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
				var probe := player.global_position + cand * 45.0
				if probe.x < 200.0 or probe.x > 660.0 or probe.y < 40.0 or probe.y > 300.0:
					continue
				var worst := 1e9
				for e in ActiveEnemy.active_instances:
					if is_instance_valid(e):
						worst = minf(worst, probe.distance_to(e.global_position))
				if worst > best_score:
					best_score = worst
					dir = cand
			if dir == Vector2.ZERO:
				dir = (player.global_position - nearest.global_position).normalized()
			# Dash escape when something is on top of us and dash is ready.
			if nd < 32.0 and not dash_ability.is_cooldown:
				Input.action_press("action_2")
			else:
				Input.action_release("action_2")
		else:
			Input.action_release("action_2")
			if target == null:
				var t := float(frames) / 60.0
				var orbit := ARENA_CENTER + Vector2(cos(t * 0.9), sin(t * 0.9)) * 60.0
				dir = orbit - player.global_position
			elif target_dist > 65.0:
				dir = target.global_position - player.global_position
			else:
				var away := (player.global_position - target.global_position).normalized()
				dir = (target.global_position - player.global_position).rotated(PI / 2.0).normalized() * 0.7 + away * 0.3
		if dir.length() > 1.0:
			dir = dir.normalized()
		else:
			dir = Vector2.ZERO
		# Keep the bot on the open floor; slide along the boundary instead of
		# bouncing back to center (spawn points sit near the room edges).
		var next := player.global_position + dir * 30.0
		var clamped := Vector2(clampf(next.x, 200.0, 660.0), clampf(next.y, 40.0, 300.0))
		if clamped != next:
			dir = (clamped - player.global_position)
			if dir.length() > 1.0:
				dir = dir.normalized()
			else:
				dir = Vector2.ZERO
		_set_move(dir)
		if frames - last_report >= 300:
			last_report = frames
			print("SHOOTER_PROGRESS t=%.0fs kills=%d shots=%d wave=%d remaining=%d active=%d hp=%.0f" % [
				float(frames) / 60.0, _kills, _shots, wave_number.value,
				remaining.value, ActiveEnemy.active_instances.size(), health.hp])
		if wave_number.value >= 1 and _kills >= 10:
			break
	Input.action_release("action_1")
	_set_move(Vector2.ZERO)
	await _frames(2)

	_expect(_shots > 0, "shots fired (%d)" % _shots)
	_expect(max_active > 0, "enemies spawned (max active %d)" % max_active)
	_expect(_kills > 0, "enemies killed (%d)" % _kills)
	_expect(_kills >= 10, "wave 1 cleared (kills=%d, enemy_count=%d)" % [_kills, enemy_count.value])
	_expect(wave_number.value >= 1, "wave counter advanced (wave=%d remaining=%d)" % [wave_number.value, remaining.value])
	_expect(not health.is_dead, "player survived (hp=%.0f)" % health.hp)
	_finish()


func _finish() -> void:
	var hit_rate := 0.0
	if _shots > 0:
		hit_rate = 100.0 * float(_hits) / float(_shots)
	var avg_dist := 0.0
	if _dist_n > 0:
		avg_dist = _dist_sum / float(_dist_n)
	print("SHOOTER_SUMMARY fails=%d shots=%d hits=%d hit_rate=%.1f%% kills=%d avg_engage_dist=%.0fpx" % [_fails, _shots, _hits, hit_rate, _kills, avg_dist])
	if _fails == 0:
		print("SHOOTER_TEST_PASS")
	else:
		print("SHOOTER_TEST_FAIL count=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
