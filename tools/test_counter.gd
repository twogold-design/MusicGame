extends SceneTree

var game
var counter
var checks := 0
var failures := 0
var output: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	var line := ("PASS " if ok else "FAIL ")+label
	output.append(line)
	print(line)

func reset(simple := true) -> void:
	game.easy = simple
	game.offset_ms = 0
	game.muted = true
	game.set_audio()
	counter.start()
	counter.music.stop()
	game.set_process(false)

func cue_at(b: float) -> int:
	for i in range(counter.cues.size()):
		if is_equal_approx(float(counter.cues[i].beat),b): return i
	return -1

func before(index: int) -> void:
	# Isolate a later phrase from unrelated prior misses, without invoking rewards.
	for i in range(index): counter.cues[i].status = 2

func down(at: float,source := "test") -> void:
	counter.elapsed = at
	counter.press(source)

func up(at: float,source := "test") -> void:
	counter.elapsed = at
	counter.release(source)

func resolve(at: float) -> void:
	counter.elapsed = at
	counter.resolve_cues()

func key(pressed: bool,code := KEY_SPACE,echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	counter.input(event)

func all_stopped() -> bool:
	if counter.music.playing: return false
	for audio in counter.response_players+counter.melody_players+counter.sounds.values():
		if audio.playing or audio.stream_paused: return false
	return true

func run() -> void:
	output.append("MEOW BEAT single-key counter / actual main.tscn and rhythm_counter.gd")
	output.append("Godot "+Engine.get_version_info().string)
	output.append("Isolated saves: "+OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/counter-test-roaming"):
		push_error("Refusing to use non-isolated save directory")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	counter = game.combat
	reset()
	check(counter.cues.size() == 64 and counter.hp == 8, "single-key mode starts64 cues with8 easy hearts")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	var counts := {"tap":0,"hold":0,"release":0}
	var last_time := -1.0
	for i in range(counter.cues.size()):
		var cue: Dictionary = counter.cues[i]
		var audio: Dictionary = meta.cues[i]
		var legal: bool = cue.time > last_time and is_equal_approx(float(cue.time),2+float(cue.beat)*0.5)
		legal = legal and is_equal_approx(float(cue.time),float(audio.time)) and is_equal_approx(float(cue.beat),float(audio.beat)) and cue.voice == audio.action
		legal = legal and int(audio.stem_channel) == i%2
		if cue.voice == "shot": legal = legal and int(cue.sample) == int(audio.sample_index)
		var expected := "hold" if float(cue.beat) in [13.0,29.0,45.0,57.0] else ("release" if float(cue.beat) in [14.0,30.0,46.0,58.0] else "tap")
		legal = legal and cue.type == expected and cue.status == 0 and not cue.sound
		counts[cue.type] += 1
		check(legal,"cue%02d beat%04.1f: timing, voice, sample/stem and tap/hold/release match intended chart" % [i,float(cue.beat)])
		last_time = cue.time
	check(counts.tap == 56 and counts.hold == 4 and counts.release == 4, "chart includes56 taps and4 complete head/tail hold pairs")
	check(absf(counter.music.stream.get_length()-float(meta.duration)) < 0.001 and counter.response_players.size() == 2, "backing and dual response stems use existing audio timeline")

	reset()
	down(1.90)
	check(counter.cues[0].status == 1 and counter.resolved == 0 and counter.flying.is_empty() and counter.press_flash == 1, "early tap gives immediate feedback and buffers without attacking")
	up(1.91)
	resolve(1.999)
	check(counter.resolved == 0,"buffer waits until exact presentation beat")
	resolve(2.0)
	check(counter.cues[0].status == 2 and counter.resolved == 1 and counter.score == 70 and counter.flying.size() == 1, "buffered tap executes once at beat after physical release")
	resolve(2.01)
	down(2.02)
	up(2.03)
	check(counter.resolved == 1 and counter.flying.size() == 1,"consumed cue cannot be hit again by repeat frame or extra click")
	for simple in [true,false]:
		var width := 0.15 if simple else 0.11
		reset(simple)
		down(2+width-0.001)
		check(counter.resolved == 1 and counter.cues[0].status == 2,"%s late input inside window executes immediately" % str(simple))
		reset(simple)
		down(2+width+0.001)
		check(counter.resolved == 0 and counter.wrong == 1 and counter.press_flash == 1,"%s outside-window press rejects but still responds visually" % str(simple))
	reset()
	down(2.25)
	up(2.26)
	check(counter.wrong == 1 and counter.hp == 8 and counter.score == 0,"offbeat input breaks rhythm without additionalHP punishment")

	for head_beat in [13.0,29.0,45.0,57.0]:
		reset()
		var head := cue_at(head_beat)
		before(head)
		var at: float = counter.cues[head].time
		down(at)
		check(counter.holding == head and counter.cues[head].status == 2 and counter.resolved == 1,"hold beat%02d begins on same single key" % int(head_beat))
		up(at+0.5)
		check(counter.holding == -1 and counter.cues[head+1].status == 2 and counter.resolved == 2 and counter.heavy_hits == 1 and counter.missed == 0,"hold beat%02d releases on next beat for one heavy counter" % int(head_beat))
	reset()
	before(13)
	down(8.5)
	up(8.60)
	check(counter.cues[14].status == 3 and counter.missed == 1 and counter.hp == 7 and counter.heavy_hits == 0,"early release penalizes one long enemy exactly once")
	resolve(9.20)
	up(9.21)
	check(counter.missed == 1 and counter.hp == 7,"failed long tail cannot apply a second delayed penalty")
	reset()
	before(13)
	resolve(8.651)
	check(counter.cues[13].status == 3 and counter.cues[14].status == 3 and counter.missed == 1 and counter.hp == 7,"missing hold head consumes head and tail with oneHP loss")
	resolve(9.20)
	check(counter.missed == 1 and counter.hp == 7,"unplayed hold tail stays consumed after its later deadline")
	reset()
	before(13)
	down(8.40)
	up(8.90)
	check(counter.cues[13].status == 1 and counter.cues[14].status == 1 and counter.resolved == 0,"early head and tail inputs can independently buffer without premature heavy attack")
	resolve(8.5)
	resolve(9.0)
	check(counter.resolved == 2 and counter.heavy_hits == 1 and counter.missed == 0,"buffered long head and release execute at their respective beats")

	reset()
	down(2.0,"mouse")
	down(2.01,"key")
	up(2.02,"key")
	check(counter.resolved == 1 and counter.active_input == "mouse","secondary input cannot duplicate hit or release primary input")
	up(2.03,"mouse")
	check(counter.active_input.is_empty(),"matching source releases active input")
	counter.elapsed = 2.5
	key(true,KEY_J)
	key(true,KEY_J,true)
	key(false,KEY_J)
	check(counter.resolved == 2 and counter.active_input.is_empty(),"J key handles one tap and ignores keyboard auto-repeat")
	reset()
	var position_before: Vector2 = counter.HIT
	counter.elapsed = 2.0
	key(true,KEY_W)
	key(false,KEY_W)
	check(counter.resolved == 0 and counter.wrong == 0 and counter.HIT == position_before,"movement keys have no gameplay requirement or movement effect")
	key(true)
	key(false)
	check(counter.resolved == 1,"Space alone hits without mouse aim or movement state")
	reset()
	before(cue_at(43.0))
	down(23.5)
	up(23.51)
	down(23.61)
	up(23.62)
	check(counter.resolved == 1 and counter.cues[cue_at(43.5)].status == 0,"repeat click near consumed half-beat overlap cannot steal later cue")
	down(23.65)
	up(23.66)
	resolve(23.75)
	check(counter.resolved == 2,"half-beat double tap is playable with same single button")

	reset()
	before(13)
	counter.music.play()
	await process_frame
	down(8.5)
	# AudioStreamPlayer exposes paused state only for an active playback.
	# Exercise every stream with active voices rather than testing idle getters.
	for audio in counter.response_players+counter.melody_players+counter.sounds.values(): audio.play()
	counter.pause_game()
	var frozen: float = counter.elapsed
	counter.update(0.75)
	check(game.screen == "combat_pause" and counter.elapsed == frozen and counter.holding == 13 and counter.recovery_hold and counter.active_input.is_empty(),"pause freezes time and retains long-note recovery state")
	var all_paused: bool = counter.music.stream_paused
	for audio in counter.response_players+counter.melody_players+counter.sounds.values(): all_paused = all_paused and audio.stream_paused
	check(all_paused,"pause freezes backing, responses, melody and effect players")
	counter.resume_game()
	counter.music.stop()
	down(8.7)
	check(not counter.recovery_hold and counter.holding == 13 and counter.resolved == 1 and counter.wrong == 0,"resume re-hold restores existing long enemy without new hit or rejection")
	up(9.0)
	check(counter.heavy_hits == 1 and counter.resolved == 2 and counter.missed == 0,"recovered hold completes normally at tail")

	reset()
	down(1.9)
	counter.finish(false)
	check(game.screen == "combat_result" and all_stopped() and counter.holding == -1 and counter.active_input.is_empty(),"defeat stops all audio and clears pending physical input")
	var failed_score: int = counter.score
	counter.finish(true)
	check(counter.score == failed_score and not counter.won,"duplicate finish cannot turn defeat into victory or award score")
	reset(false)
	check(counter.hp == 5 and counter.score == 0 and counter.resolved == 0 and counter.missed == 0 and counter.heavy_hits == 0 and counter.holding == -1 and counter.active_input.is_empty() and counter.response_until == [-1.0,-1.0],"restart resets long state, scores, gating and selected normalHP")
	check(counter.response_players[0].volume_db == -80 and counter.response_players[1].volume_db == -80 and counter.response_players[0].playing and counter.response_players[1].playing,"restart launches response stems silently without stale open gate")

	reset()
	for i in range(counter.cues.size()):
		var cue: Dictionary = counter.cues[i]
		counter.elapsed = cue.time
		if cue.type == "release": key(false)
		else:
			key(true)
			if cue.type == "tap": key(false)
		counter.resolve_cues()
	check(counter.resolved == 64 and counter.missed == 0 and counter.wrong == 0 and counter.perfect == 64 and counter.streak == 64,"all64 actions resolve perfectly using only Space press/release events")
	check(counter.heavy_hits == 4 and counter.boss_hp == 0 and counter.boss_defeated,"complete single-key performance delivers4 heavy counters and defeats final boss")
	counter.elapsed = 32.0
	counter.update(0)
	check(game.screen == "combat_result" and counter.won and all_stopped(),"full performance reaches victory at32s and stops audio cleanly")
	var final_score: int = counter.score
	counter.finish(true)
	key(true)
	check(counter.score == final_score,"repeated victory or result-screen input cannot duplicate reward")

	counter.stop()
	game.queue_free()
	counter = null
	game = null
	await process_frame
	await create_timer(0.35).timeout
	output.append("Cleanup: freed scene/references and allowed350ms for audio mixer retirement.")
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/counter-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
