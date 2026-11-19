extends SceneTree

var game
var adv
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

func reset(simple := true, seed_number := 441) -> void:
	game.easy = simple
	game.selected = 0
	game.offset_ms = 0
	adv.new_run(seed_number)
	adv.stop_audio()
	game.set_process(false)
	game.muted = true
	game.set_audio()

func empty_arena() -> void:
	reset()
	adv.walls.clear()
	adv.pickups.clear()
	# Four distant tokens stop replenishment from obscuring controlled fixtures.
	for cell in [Vector2i(0,0),Vector2i(8,0),Vector2i(0,6),Vector2i(8,6)]:
		adv.pickups.append({"cell":cell,"value":1})
	adv.beat = 1
	adv.last_move = -99

func independent_reachable() -> Array[Vector2i]:
	var reached: Array[Vector2i] = [Vector2i(4,6)]
	var cursor := 0
	while cursor < reached.size():
		for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var cell: Vector2i = reached[cursor] + direction
			if cell.x < 0 or cell.x >= 9 or cell.y < 0 or cell.y >= 7: continue
			if adv.walls.has(cell) or reached.has(cell): continue
			reached.append(cell)
		cursor += 1
	return reached

func harmless_cell() -> Vector2i:
	return Vector2i(4,3)

func run() -> void:
	output.append("MEOW BEAT adventure mechanics / production main.tscn and adventure.gd")
	output.append("Godot " + Engine.get_version_info().string)
	output.append("Isolated saves: " + OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/adventure-test-roaming"):
		push_error("Refusing to test with non-isolated saves")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	adv = game.adventure

	for seed_number in range(100):
		reset(seed_number % 2 == 0, seed_number)
		var reached := independent_reachable()
		var legal: bool = reached.size() == 63 - adv.walls.size()
		legal = legal and reached.has(Vector2i(4,3)) and reached.has(Vector2i(4,0))
		var occupied: Array[Vector2i] = []
		var available := 0
		for item in adv.pickups:
			legal = legal and reached.has(item.cell) and not occupied.has(item.cell)
			legal = legal and item.cell != Vector2i(4,6) and item.cell != Vector2i(4,0) and item.cell != Vector2i(4,3)
			legal = legal and int(item.value) in [1,2]
			occupied.append(item.cell)
			available += int(item.value)
		check(legal and available >= 9 and adv.pickups.size() == 8, "seed %03d: all floor/targets reachable, 8 unique legal tokens and >=9 resource value" % seed_number)

	reset(true, 77)
	var first_layout: Array = adv.walls.duplicate()
	var first_items: Array = adv.pickups.duplicate(true)
	reset(true, 77)
	check(adv.walls == first_layout and adv.pickups == first_items, "fixed seed reproduces map and resource placement")
	check(adv.hearts == 4 and adv.max_beats == 192 and adv.charge == 2 and adv.beat == -5, "easy initialization: 4 hearts,192 beats,2 energy,count-in")
	reset(false)
	check(adv.hearts == 3 and adv.max_beats == 160, "normal initialization: 3 hearts,160 beats")

	empty_arena()
	adv.player = Vector2i(4,3)
	adv.bag = 2
	adv.collect_here()
	check(adv.bank == 2 and adv.bag == 0 and adv.repaired == 0, "sub-three delivery safely accumulates bank")
	for threshold in [3,6,9]:
		adv.bag = 1 if threshold == 3 else 3
		adv.hearts = 2
		adv.collect_here()
		check(adv.bank == threshold and adv.repaired == threshold / 3 and adv.bag == 0, "delivery unlocks correct voice at cumulative %d" % threshold)
		check(adv.hearts == 3 and game.screen == "adv_play", "repair heals once and still requires exit at bank %d" % threshold)
	var stored_score: int = adv.total_score
	adv.collect_here()
	check(adv.total_score == stored_score and adv.repaired == 3, "revisiting empty home does not duplicate repair rewards")
	adv.player = Vector2i(4,0)
	adv.collect_here()
	check(adv.won and game.screen == "adv_result", "open exit completes run only after all three voices repaired")
	var victory_score: int = adv.total_score
	adv.finish(true,"Repeated victory")
	check(adv.total_score == victory_score and adv.won, "repeated finish cannot award victory bonus twice")
	var full_mix := true
	for audio in adv.players: full_mix = full_mix and audio.volume_db == -3 and not audio.stream_paused
	check(full_mix, "victory exposes full mix and does not pause the celebration")

	empty_arena()
	adv.player = Vector2i(4,3)
	adv.bank = 2
	adv.bag = 5
	adv.hearts = 1
	adv.collect_here()
	check(adv.bank == 7 and adv.repaired == 2 and adv.hearts == 3, "one delivery crossing two repair thresholds heals for BOTH voices")
	check(adv.total_score == 2000, "two simultaneous repairs award both 500-point repair bonuses")
	check(adv.pickups.size() == 12, "two simultaneous repairs create two batches of four resources")
	adv.bag = 5
	adv.hearts = 4
	adv.collect_here()
	check(adv.bank == 9 and adv.hearts == 4, "bank and healing are capped at9 and mode heart maximum")

	empty_arena()
	adv.player = Vector2i(2,2)
	adv.pickups.append({"cell":adv.player,"value":2})
	adv.bag = 4
	adv.collect_here()
	var remaining_index: int = adv.pickup_at(adv.player)
	check(adv.bag == 5 and remaining_index >= 0 and adv.pickups[remaining_index].value == 1, "gold value is partially collected and remainder preserved")
	adv.collect_here()
	check(adv.bag == 5 and adv.pickups[remaining_index].value == 1, "full bag does not destroy ground token")
	adv.bag = 0
	adv.collect_here()
	check(adv.bag == 1 and adv.pickup_at(adv.player) == -1, "gold remainder can be collected later exactly once")

	empty_arena()
	adv.player = Vector2i(2,2)
	adv.walls.append(Vector2i(3,2))
	adv.dash_armed = true
	adv.move_player(Vector2i.RIGHT,false)
	check(adv.player == Vector2i(2,2) and adv.charge == 2 and adv.moves == 0, "blocked first dash step costs no energy and no move")
	adv.walls.clear()
	adv.walls.append(Vector2i(4,2))
	adv.move_player(Vector2i.RIGHT,false)
	check(adv.player == Vector2i(3,2) and adv.charge == 0 and adv.moves == 1, "dash stops at second-step wall and costs exactly2")
	adv.move_player(Vector2i.DOWN,true)
	check(adv.player == Vector2i(3,2) and adv.moves == 1, "multiple actions in same beat cannot create extra movement")

	empty_arena()
	adv.player = Vector2i(2,2)
	adv.pickups.append({"cell":Vector2i(3,2),"value":1})
	adv.pickups.append({"cell":Vector2i(4,2),"value":2})
	adv.dash_armed = true
	adv.move_player(Vector2i.RIGHT,false)
	check(adv.player == Vector2i(4,2) and adv.bag == 3 and adv.charge == 0, "dash collects intermediate and destination tokens")
	adv.charge = 4
	adv.beat += 1
	adv.move_player(Vector2i.DOWN,true)
	check(adv.charge == 4 and adv.perfect_moves == 1, "precise movement charges but never exceeds4")
	adv.charge = 1
	adv.toggle_dash()
	check(not adv.dash_armed and adv.charge == 1, "insufficient charge cannot arm a dash")
	empty_arena()
	adv.player = Vector2i(2,2)
	adv.beat = 20
	adv.elapsed = (24.5) * adv.beat_length
	adv.queue_move(Vector2i.RIGHT)
	check(adv.queued == Vector2i.RIGHT and adv.player == Vector2i(2,2), "off-beat direction is buffered without immediate movement")
	adv.advance_beat(21)
	check(adv.player == Vector2i(3,2) and adv.queued == Vector2i.ZERO and adv.moves == 1, "buffered direction executes once on next beat")

	empty_arena()
	adv.hazard_shift = 6 # strike12 scans column3
	adv.beat = 12
	adv.player = Vector2i(2,2)
	adv.dash_armed = true
	adv.move_player(Vector2i.RIGHT,false)
	adv.check_danger()
	check(adv.player == Vector2i(4,2) and adv.hearts == 4, "dash skips dangerous intermediate laser cell")
	adv.player = Vector2i(1,2)
	adv.charge = 2
	adv.dash_armed = true
	adv.last_move = -99
	adv.move_player(Vector2i.RIGHT,false)
	adv.check_danger()
	check(adv.player == Vector2i(3,2) and adv.hearts == 3, "dash landing on the attacking laser takes one damage")

	empty_arena()
	var preview_consistent := true
	for strike in range(12,193,4):
		adv.beat = strike - 4
		var preview: Array = adv.laser_cells(adv.next_strike())
		for step in range(strike-4,strike):
			adv.beat = step
			preview_consistent = preview_consistent and adv.next_strike() == strike and adv.laser_cells(adv.next_strike()) == preview
		adv.beat = strike
		preview_consistent = preview_consistent and adv.laser_cells(strike) == preview
	check(preview_consistent, "each steady-state laser strike matches its complete four-beat warning")
	var gentle_opening := true
	adv.repaired = 2
	for strike in [12,16,20,24,28]:
		var cells: Array = adv.laser_cells(strike)
		for cell in cells:
			gentle_opening = gentle_opening and cell.x == cells[0].x
	check(gentle_opening, "first32 beats remain single-column even when player repairs quickly")
	adv.repaired = 1
	adv.beat = 21
	var warned_before: Array = adv.laser_cells(adv.next_strike())
	adv.player = Vector2i(4,3)
	adv.bank = 5
	adv.bag = 1
	adv.collect_here()
	var warned_after: Array = adv.laser_cells(adv.next_strike())
	check(warned_before == warned_after, "repair during an active warning cannot change announced attack cells")

	empty_arena()
	adv.hazard_shift = 6
	adv.player = Vector2i(3,2)
	adv.bag = 5
	adv.beat = 11
	adv.check_danger()
	check(adv.hearts == 4 and adv.bag == 5, "laser preview does not inflict damage before strike")
	adv.beat = 12
	adv.check_danger()
	check(adv.hearts == 3 and adv.bag == 3 and adv.damage_taken == 1, "laser loses one heart and at most two carried tokens")
	adv.check_danger()
	check(adv.hearts == 3 and adv.damage_taken == 1, "same-beat overlap cannot apply duplicate damage")
	adv.repaired = 2
	# Repeat a real hit at beat24, then collide with actual bots on both protected beats.
	adv.beat = 24
	adv.immune_until = -1
	adv.player = adv.laser_cells(24)[0]
	adv.check_danger()
	var protected_hearts: int = adv.hearts
	check(adv.immune_until == 27, "a beat24 hit protects subsequent beats25 and26")
	var immune_ok := true
	for at in [25,26]:
		adv.beat = at
		var bots: Array = adv.speaker_cells(at)
		adv.player = bots[0]
		adv.check_danger()
		immune_ok = immune_ok and adv.hearts == protected_hearts
	check(immune_ok, "both protected beats block genuine speaker collisions")
	adv.beat = 27
	adv.player = adv.speaker_cells(27)[0]
	adv.bag = 1
	adv.check_danger()
	check(adv.hearts == protected_hearts - 1 and adv.bag == 0, "immunity expiry allows damage and bag never becomes negative")
	var before_home_hearts: int = adv.hearts
	adv.player = Vector2i(4,3)
	adv.immune_until = -1
	for at in range(12,80):
		adv.beat = at
		adv.check_danger()
	check(adv.hearts == before_home_hearts, "central home remains safe across laser and speaker phases")

	empty_arena()
	adv.hazard_shift = 6
	adv.player = Vector2i(3,2)
	adv.hearts = 1
	adv.beat = 12
	adv.check_danger()
	check(adv.hearts == 0 and not adv.won and game.screen == "adv_result", "last heart triggers failure")
	var death_damage: int = adv.damage_taken
	adv.check_danger()
	check(adv.damage_taken == death_damage and adv.hearts == 0, "result screen prevents further danger damage")

	empty_arena()
	adv.player = Vector2i(4,0)
	adv.collect_here()
	check(game.screen == "adv_play" and not adv.won, "locked exit cannot finish incomplete run")
	adv.player = harmless_cell()
	adv.advance_beat(adv.max_beats)
	check(game.screen == "adv_result" and not adv.won, "beat deadline produces timeout failure")

	empty_arena()
	adv.bank = 9
	adv.repaired = 3
	adv.player = Vector2i(4,1)
	adv.queued = Vector2i.UP
	adv.queued_perfect = false
	adv.advance_beat(adv.max_beats)
	check(adv.won and game.screen == "adv_result", "exit reached on final permitted beat wins before timeout")

	reset()
	for player_audio in adv.players: player_audio.play()
	await process_frame
	adv.queued = Vector2i.LEFT
	adv.beat = 20
	adv.elapsed = 14.4
	var before_pause_player: Vector2i = adv.player
	adv.pause_game()
	adv.update(1.5)
	var all_paused := true
	for player_audio in adv.players: all_paused = all_paused and player_audio.stream_paused
	check(game.screen == "adv_pause" and all_paused and adv.beat == 20 and adv.elapsed == 14.4 and adv.player == before_pause_player and adv.queued == Vector2i.ZERO, "pause freezes clock, movement and voices and clears buffered move")
	adv.resume_game()
	var none_paused := true
	for player_audio in adv.players: none_paused = none_paused and not player_audio.stream_paused
	check(game.screen == "adv_play" and none_paused, "resume restores game and all voices")
	adv.bank = 8
	adv.bag = 5
	adv.repaired = 2
	adv.hearts = 1
	adv.charge = 4
	adv.dash_armed = true
	adv.immune_until = 40
	adv.total_score = 9999
	reset(false, 776)
	check(adv.bank == 0 and adv.bag == 0 and adv.repaired == 0 and adv.hearts == 3 and adv.charge == 2 and not adv.dash_armed and adv.immune_until == -1 and adv.total_score == 0 and not adv.won, "restart clears previous run state and reapplies selected mode")

	adv.stop_audio()
	game.queue_free()
	adv = null
	game = null
	await process_frame
	# Tests start/stop hundreds of voices synchronously. Let the audio mixer
	# retire pending playback objects after the scene and its caches are freed.
	await create_timer(0.35).timeout
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append("Cleanup: freed test scene and references; waited 350ms for pending audio playback retirement.")
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/adventure-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
