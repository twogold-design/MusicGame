extends SceneTree

var game
var combat
var checks := 0
var failures := 0
var output: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	var line := ("PASS " if ok else "FAIL ") + label
	output.append(line)
	print(line)

func reset(simple := true) -> void:
	game.easy = simple
	game.offset_ms = 0
	game.muted = true
	game.set_audio()
	combat.start()
	combat.music.stop()
	game.set_process(false)
	combat.player = Vector2(600,450)
	combat.aim = Vector2(1100,450)

func fire_at(at: float) -> void:
	combat.elapsed = at
	combat.shoot()

func target(id: int, pos: Vector2, health := 20, boss := false) -> Dictionary:
	return {"id":id,"pos":pos,"hp":health,"maxhp":health,"boss":boss,"radius":26.0,"flash":0.0,"armed":false,"lock":Vector2.DOWN}

func bullet(pos: Vector2) -> Dictionary:
	return {"pos":pos,"vel":Vector2.ZERO,"life":3.0,"radius":7.0}

func run() -> void:
	output.append("MEOW BEAT combat mechanics / actual main.tscn and rhythm_combat.gd")
	output.append("Godot " + Engine.get_version_info().string)
	output.append("Isolated saves: " + OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/combat-test-roaming"):
		push_error("Refusing to use non-isolated test saves")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	combat = game.combat

	reset()
	check(game.screen == "combat_play" and combat.hp == 5 and combat.elapsed == 0 and combat.streak == 0, "easy start resets five hearts, music time and streak")
	reset(false)
	check(combat.hp == 4, "challenge starts with four hearts")
	for simple in [true,false]:
		var width := 0.13 if simple else 0.10
		for side in [-1.0,1.0]:
			for within in [true,false]:
				reset(simple)
				var offset: float = side * (width - 0.001 if within else width + 0.001)
				fire_at(4.0 + offset)
				check(combat.perfect_shots == (1 if within else 0) and combat.normal_shots == (0 if within else 1), "%s %s timing at signed %.3fs" % ["easy" if simple else "normal","inside" if within else "outside",offset])
	reset()
	fire_at(1.99)
	check(combat.shots.is_empty(), "four-beat preparation cannot fire combat projectiles")
	fire_at(2.0)
	check(combat.perfect_shots == 1 and combat.last_perfect_beat == 0, "first combat downbeat fires a strong wave")
	fire_at(32.0)
	check(combat.perfect_shots == 1 and combat.shots.size() == 1, "shooting stops at combat time32s")

	reset()
	combat.elapsed = 2.0
	combat.music.play(5.0)
	await create_timer(0.035).timeout
	var actual_audio: float = combat.audio_time()
	combat.shoot()
	check(actual_audio > 4.9 and combat.last_perfect_beat >= 5 and combat.perfect_shots == 1, "shoot uses current audio time even when cached elapsed is three seconds stale")
	combat.music.stop()
	reset()
	game.offset_ms = 150
	fire_at(4.15)
	check(combat.perfect_shots == 1 and combat.last_perfect_beat == 4, "positive150ms input calibration shifts strong window")

	reset()
	fire_at(3.0)
	fire_at(3.01)
	fire_at(3.12)
	check(combat.perfect_shots == 1 and combat.shots.size() == 1, "multiple clicks in one strong window cannot duplicate strong wave")
	fire_at(3.5)
	check(combat.perfect_shots == 2 and combat.streak == 2, "next distinct beat can produce next strong wave")
	reset()
	fire_at(2.85)
	check(combat.normal_shots == 1, "off-beat first click creates weak shot")
	fire_at(3.0)
	check(combat.perfect_shots == 1 and combat.normal_shots == 1 and combat.shots.size() == 2, "weak cooldown cannot swallow following correctly timed wave")
	reset()
	fire_at(3.14)
	fire_at(3.34)
	check(combat.normal_shots == 1, "weak-only clicks200ms apart are limited by220ms cooldown")
	fire_at(3.365)
	check(combat.normal_shots == 2, "weak cooldown allows next shot after220ms")

	reset()
	for i in range(8): fire_at(3.0 + i*0.5)
	check(combat.streak == 8 and combat.perfect_shots == 8 and combat.overdrives == 1, "eight consecutive distinct beats activate one overdrive")
	check(combat.shots.size() == 10 and is_equal_approx(combat.overdrive_until,8.5), "trigger shot becomes three-way and overdrive lasts exactly four beats")
	fire_at(7.0)
	check(combat.shots.size() == 13 and combat.overdrives == 1, "following overdrive beat emits three strong projectiles")
	fire_at(8.5)
	check(combat.shots.size() == 14, "shot at overdrive expiry returns to one projectile")
	reset()
	fire_at(3.0)
	fire_at(3.5)
	fire_at(4.5)
	check(combat.streak == 1, "skipping a musical beat resets next strong streak to1")
	reset()
	fire_at(3.0)
	fire_at(3.5)
	fire_at(3.72)
	check(combat.streak == 0 and combat.normal_shots == 1, "accepted off-beat weak shot breaks strong streak")
	reset()
	fire_at(3.0)
	combat.elapsed = 4.05
	combat.update(0)
	check(combat.streak == 0, "missed beat clears stale streak even without another shot")

	reset()
	var first := target(1,Vector2(680,450))
	var second := target(2,Vector2(760,450))
	combat.enemies = [first,second]
	fire_at(3.0)
	combat.step_projectiles(0.2)
	check(first.hp == 14 and second.hp == 14 and combat.shots.size() == 1, "strong wave deals6 and penetrates two enemies")
	combat.shots[0].pos = Vector2(680,450)
	combat.step_projectiles(0)
	check(first.hp == 14 and second.hp == 14, "same piercing projectile cannot damage the same enemy twice")
	reset()
	first = target(1,Vector2(680,450))
	second = target(2,Vector2(760,450))
	combat.enemies = [first,second]
	fire_at(3.2)
	combat.step_projectiles(0.2)
	check(first.hp == 18 and second.hp == 20 and combat.shots.is_empty(), "weak shot deals2 and stops on first hit")
	reset()
	first = target(1,Vector2(680,450),6)
	combat.enemies = [first]
	fire_at(3.0)
	combat.step_projectiles(0.2)
	check(combat.enemies.is_empty() and combat.kills == 1 and combat.score == 230, "enemy kill awards one hit reward and one kill reward")
	combat.step_projectiles(0.2)
	check(combat.kills == 1 and combat.score == 230, "dead enemy cannot award repeated kill score")
	reset()
	first = target(3,Vector2(800,450),60,true)
	combat.enemies = [first]
	for i in range(10):
		combat.streak = 0 # Isolate exact6 damage from the separate three-way mechanic.
		fire_at(3.0 + i*0.5)
		combat.step_projectiles(0.2)
	check(combat.boss_defeated and combat.kills == 1 and combat.enemies.is_empty(), "ten individual6-damage waves defeat60HP boss")

	reset()
	combat.elapsed = 4.0
	combat.move_keys[KEY_W] = true
	combat.move_dir = Vector2.ZERO # Dash must use current key state before next render frame.
	combat.bullets = [bullet(combat.player+Vector2(80,0)),bullet(combat.player+Vector2(200,0))]
	combat.dash()
	check(combat.dash_dir == Vector2.UP and combat.dash_total == 1 and is_equal_approx(combat.dash_ready,5.0), "dash follows move direction and starts one-second cooldown")
	check(combat.bullets.size() == 1 and combat.dash_cancelled == 1 and combat.score == 30, "on-beat dash cancels only nearby hostile bullets")
	combat.hurt()
	check(combat.hp == 5, "dash invulnerability prevents immediate contact damage")
	combat.bullets = [bullet(combat.player)]
	combat.elapsed = 4.1
	combat.step_projectiles(0)
	check(combat.hp == 5 and combat.bullets.is_empty() and combat.dash_cancelled == 2, "active dash passes through and destroys colliding bullet")
	combat.elapsed = 4.25
	combat.hurt()
	check(combat.hp == 4, "damage resumes after dash protection expires")
	combat.elapsed = 4.5
	combat.dash()
	check(combat.dash_total == 1, "dash cannot repeat during cooldown")
	combat.elapsed = 5.0
	combat.move_keys.clear()
	combat.move_dir = Vector2.ZERO
	combat.aim = combat.player-Vector2(200,0)
	combat.dash()
	check(combat.dash_total == 2 and combat.dash_dir == Vector2.LEFT, "ready dash without movement uses aim direction")

	reset()
	combat.music.play()
	await process_frame
	combat.elapsed = 6.0
	combat.beat = 8
	combat.move_keys[KEY_D] = true
	combat.move_dir = Vector2.RIGHT
	combat.touch_dir = Vector2.UP
	combat.touch_id = 3
	var original_player: Vector2 = combat.player
	combat.pause_game()
	combat.update(0.5)
	check(game.screen == "combat_pause" and combat.music.stream_paused and combat.elapsed == 6.0 and combat.beat == 8 and combat.player == original_player, "pause freezes audio, time, beat and player")
	check(combat.move_keys.is_empty() and combat.move_dir == Vector2.ZERO and combat.touch_dir == Vector2.ZERO and combat.touch_id == -1, "pause clears all keyboard and touch movement state")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	combat.input(key)
	check(combat.move_keys.is_empty(), "movement pressed during pause cannot rearm movement")
	combat.resume_game()
	check(game.screen == "combat_play" and not combat.music.stream_paused and combat.move_keys.is_empty(), "resume unpauses without inherited paused movement")
	combat.music.stop()

	reset()
	var capped := true
	for at in range(39):
		combat.on_beat(at)
		capped = capped and combat.enemies.size() == mini(8,at+2)
	check(capped, "first40-beat wave adds one target each beat, starts with2 and caps regular enemies at8")
	combat.enemies.pop_front()
	combat.on_beat(39)
	check(combat.enemies.size() == 8, "next beat replaces a defeated enemy without exceeding regular-enemy cap")
	var spawn_positions: Array[Vector2] = [Vector2(1110,430),Vector2(330,400),Vector2(720,245),Vector2(960,640),Vector2(450,630),Vector2(1040,265),Vector2(425,270),Vector2(720,650)]
	for slot in range(spawn_positions.size()):
		combat.enemies.clear()
		combat.player = spawn_positions[slot]
		combat.next_id = slot
		combat.spawn_enemy(false)
		var farthest := 0.0
		for candidate in spawn_positions: farthest = maxf(farthest,candidate.distance_to(combat.player))
		var spawned: Vector2 = combat.enemies[0].pos
		check(spawned.distance_to(combat.player) >= 170 and is_equal_approx(spawned.distance_to(combat.player),farthest), "spawn slot%d occupied by player relocates enemy to farthest safe candidate" % slot)

	reset()
	combat.on_beat(0)
	check(combat.enemies.size() == 2, "two enemies enter on first combat beat")
	combat.on_beat(3)
	check(combat.enemies[0].armed and combat.bullets.is_empty(), "enemy locks aim one beat before firing")
	var locked: Vector2 = combat.enemies[0].lock
	var armed_count: int = combat.enemies.size()
	combat.player += Vector2(100,100)
	combat.on_beat(4)
	check(combat.bullets.size() == armed_count and combat.bullets[0].vel.normalized().is_equal_approx(locked), "only warned enemies fire and attack follows announced direction rather than secretly retargeting")
	combat.on_beat(40)
	var bosses := 0
	var boss_hp := 0
	for enemy in combat.enemies:
		if enemy.boss:
			bosses += 1
			boss_hp = enemy.hp
	check(bosses == 1 and boss_hp == 60, "beat40 spawns one60HP boss")
	combat.on_beat(59)
	check(game.screen == "combat_play", "beat59 does not finish early")
	combat.on_beat(60)
	check(game.screen == "combat_result" and combat.won and not combat.boss_defeated, "beat60 grants survival clear without boss kill")
	var final_score: int = combat.score
	combat.finish(true)
	check(combat.score == final_score, "repeated finish cannot add survival bonus twice")

	reset()
	combat.hp = 1
	combat.elapsed = 6.0
	combat.bullets = [bullet(combat.player)]
	combat.update(0)
	check(combat.hp == 0 and game.screen == "combat_result" and not combat.won, "last-heart bullet damage ends run as defeat")
	reset(false)
	check(combat.hp == 4 and combat.score == 0 and combat.shots.is_empty() and combat.bullets.is_empty() and combat.enemies.is_empty() and combat.overdrives == 0 and not combat.boss_defeated and combat.dash_total == 0, "restart clears combat state and reapplies selected difficulty")

	combat.stop()
	game.queue_free()
	combat = null
	game = null
	await process_frame
	await create_timer(0.35).timeout
	output.append("Cleanup: released scene/references and allowed350ms for audio mixer retirement.")
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/combat-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
