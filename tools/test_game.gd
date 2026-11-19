extends SceneTree

var game
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

func reset_game(track := 0, simple := true) -> void:
	game.selected = track
	game.easy = simple
	game.offset_ms = 0
	game.start_song()
	game.music.stop()
	game.set_process(false)
	game.muted = true
	game.set_audio()

func advance(at: float) -> void:
	# Keep the player's active flag true during a manual frame, avoiding its
	# intentional end-of-audio path while controlling the musical clock exactly.
	game.music.play()
	game.clock_time = at
	game._process(0.0)
	game.music.stop()

func first_hold() -> Dictionary:
	for note in game.notes:
		if float(note.duration) > 0.0: return note
	return {}

func run() -> void:
	output.append("MEOW BEAT mechanics / actual main.tscn methods / Godot " + Engine.get_version_info().string)
	output.append("Isolated save directory: " + OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\", "/").contains(".runtime/test-roaming"):
		push_error("Refusing to run against a non-isolated save directory")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}

	for index in range(3):
		for simple in [true, false]:
			reset_game(index, simple)
			var previous := -1.0
			var occupied := [-1.0,-1.0,-1.0,-1.0]
			var legal := true
			var units := 0
			for note in game.notes:
				var at := float(note.time)
				var lane := int(note.lane)
				var length := float(note.duration)
				legal = legal and lane >= 0 and lane < 4 and at >= 3 and at >= previous and length >= 0 and at + length <= game.duration - 2
				legal = legal and at >= float(occupied[lane]) + 0.1
				occupied[lane] = at + length
				previous = at
				units += 2 if length > 0 else 1
			check(legal and units == game.total_units and game.notes.size() > 50, "chart %s/%s: %d notes, %d scoring units; ordered, bounded, no hold overlap" % [game.IDS[index], "easy" if simple else "normal", game.notes.size(), units])
			check(absf(game.music.stream.get_length() - game.duration) < 0.002, "WAV duration matches chart %s/%s" % [game.IDS[index], str(simple)])

	for simple in [true, false]:
		var thresholds := [0.0, 0.10 if simple else 0.09, 0.16 if simple else 0.14]
		for quality in range(3):
			for direction in [-1.0, 1.0]:
				reset_game(0, simple)
				var n: Dictionary = game.notes[0]
				game.clock_time = float(n.time) + float(thresholds[quality]) * direction
				game.press_lane(int(n.lane))
				var counts := [game.perfect, game.great, game.good]
				check(counts[quality] == 1 and game.resolved == 1 and game.score > 0, "%s %s at signed offset %.3f" % ["easy" if simple else "normal", ["PERFECT","GREAT","GOOD"][quality], float(thresholds[quality]) * direction])
				game.press_lane(int(n.lane))
				check(game.resolved == 1, "held/repeated press cannot score the same note twice")
				game.release_lane(int(n.lane))
				check(game.resolved == 1 and not game.held[int(n.lane)], "tap release clears held without extra judgement")
		reset_game(0, simple)
		var n: Dictionary = game.notes[0]
		game.clock_time = float(n.time) - game.hit_window() - 0.02
		game.press_lane(int(n.lane))
		check(game.resolved == 0 and int(n.state) == 0, "press outside %s early window does not score" % str(simple))
		game.release_lane(int(n.lane))
		advance(float(n.time) + game.hit_window() + 0.02)
		check(game.missed == 1 and game.resolved == 1 and int(n.state) == 3, "overdue note receives exactly one MISS")

	reset_game()
	var first: Dictionary = game.notes[0]
	game.clock_time = float(first.time)
	game.press_lane((int(first.lane) + 1) % 4)
	check(game.resolved == 0, "wrong lane cannot collect a note")
	game.release_lane((int(first.lane) + 1) % 4)
	game.offset_ms = 150
	game.clock_time = float(first.time) + 0.15
	game.press_lane(int(first.lane))
	check(game.perfect == 1, "positive 150ms calibration shifts input judgement correctly")

	reset_game()
	var hold: Dictionary = first_hold()
	game.clock_time = float(hold.time)
	game.press_lane(int(hold.lane))
	check(game.perfect == 1 and int(hold.state) == 1, "long note head awards one unit and enters held state")
	game.clock_time = float(hold.time) + float(hold.duration) * 0.3
	game.release_lane(int(hold.lane))
	check(game.missed == 1 and game.resolved == 2 and int(hold.state) == 2, "early release misses only long note tail")
	game.release_lane(int(hold.lane))
	check(game.resolved == 2, "repeated release never repeats tail judgement")

	reset_game()
	hold = first_hold()
	game.clock_time = float(hold.time)
	game.press_lane(int(hold.lane))
	game.clock_time = float(hold.time) + float(hold.duration) - 0.10
	game.release_lane(int(hold.lane))
	check(game.perfect == 2 and game.missed == 0, "long note release within 110ms tail tolerance succeeds")

	reset_game()
	hold = first_hold()
	for note in game.notes:
		if note != hold: note.state = 2
	game.clock_time = float(hold.time)
	game.press_lane(int(hold.lane))
	advance(float(hold.time) + float(hold.duration) + 0.01)
	check(game.perfect == 2 and game.resolved == 2 and int(hold.state) == 2, "held long note automatically completes at its tail")

	reset_game()
	hold = first_hold()
	for note in game.notes:
		if note != hold: note.state = 2
	game.clock_time = float(hold.time)
	game.press_lane(int(hold.lane))
	game.clock_time += 0.1
	var pause_at: float = game.clock_time
	game.music.play()
	game.pause_game()
	game._process(0.5)
	check(game.screen == "pause" and game.music.stream_paused and game.clock_time == pause_at and game.resolved == 1, "pause freezes musical time and active long note")
	game.resume_game()
	check(game.screen == "play" and not game.music.stream_paused and game.resume_grace > pause_at, "resume restores play and grants time to re-hold")
	advance(pause_at + 0.05)
	check(game.missed == 0 and int(hold.state) == 1, "no phantom miss immediately after resuming a held note")
	game.press_lane(int(hold.lane))
	advance(float(hold.time) + float(hold.duration) + 0.01)
	check(game.perfect == 2 and game.missed == 0, "re-hold after pause completes the long note")

	reset_game()
	for i in range(15): game.judge("PERFECT", i % 4)
	check(game.fever_count == 1 and game.is_fever() and game.energy == 0, "15 perfect hits trigger a single energy burst")
	var before: int = game.score
	game.judge("PERFECT",0)
	check(game.score - before == 2200, "energy burst doubles the current combo multiplier")
	game.clock_time = game.fever_until + 0.01
	check(not game.is_fever(), "energy burst expires after eight beats")
	game.judge("MISS",0)
	check(game.combo == 0 and game.best_combo == 16, "MISS breaks combo while retaining best combo")

	for index in range(3):
		for simple in [true,false]:
			reset_game(index,simple)
			first = game.notes[0]
			game.clock_time = float(first.time)
			game.press_lane(int(first.lane))
			game.release_lane(int(first.lane))
			game.finish_song()
			check(game.screen == "result" and game.resolved == game.total_units and game.perfect + game.great + game.good + game.missed == game.total_units, "finish resolves every head and tail exactly once: %s/%s" % [game.IDS[index],str(simple)])
			var count: int = game.resolved
			game.finish_song()
			check(game.resolved == count, "repeated finish is judgement-idempotent")

	output.append("RESULT: %d checks, %d failures" % [checks,failures])
	print(output[-1])
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var report := FileAccess.open("res://artifacts/mechanics-results.txt",FileAccess.WRITE)
	report.store_string("\n".join(output) + "\n")
	report.close()
	game.music.stop()
	for player in game.hit_players: player.stop()
	game.queue_free()
	await process_frame
	# Allow the headless audio mixer to retire the many short test playbacks.
	await create_timer(0.3).timeout
	quit(1 if failures else 0)
