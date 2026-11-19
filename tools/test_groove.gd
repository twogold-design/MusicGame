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

func cue_at(beat_number: float) -> int:
	for i in range(combat.cues.size()):
		if is_equal_approx(float(combat.cues[i].beat),beat_number): return i
	return -1

func request(at: float, kind := "shot") -> void:
	combat.elapsed = at
	combat.request_action(kind)

func enemy(id: int, pos: Vector2, health := 20) -> Dictionary:
	return {"id":id,"pos":pos,"hp":health,"maxhp":health,"boss":false,"radius":26.0,"flash":0.0,"armed":false,"lock":Vector2.DOWN}

func resolve(at: float) -> void:
	combat.elapsed = at
	combat.resolve_cues()

func run() -> void:
	output.append("MEOW BEAT strict groove / actual main.tscn and rhythm_combat.gd")
	output.append("Godot " + Engine.get_version_info().string)
	output.append("Isolated saves: " + OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/groove-test-roaming"):
		push_error("Refusing to test against non-isolated saves")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	combat = game.combat
	reset()
	check(combat.cues.size() == 64, "production chart contains64 cues")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	check(metadata.cues.size() == 64 and metadata.bpm == 120 and metadata.combat_start == 2 and metadata.combat_end == 32, "audio metadata has64 cues at120BPM and2..32s combat")
	var shot_count := 0
	var dash_count := 0
	var half_count := 0
	var previous_time := -1.0
	for i in range(combat.cues.size()):
		var c: Dictionary = combat.cues[i]
		var m: Dictionary = metadata.cues[i]
		check(int(m.stem_channel) == i%2 and m.stem_path == ("response_even.wav" if i%2 == 0 else "response_odd.wav"), "cue%02d response stem matches global-index parity" % i)
		var legal: bool = c.time > previous_time and is_equal_approx(float(c.time),2+float(c.beat)*0.5)
		legal = legal and is_equal_approx(float(c.beat),float(m.beat)) and is_equal_approx(float(c.time),float(m.time)) and c.type == m.action
		if c.type == "shot":
			shot_count += 1
			legal = legal and int(c.sample) == int(m.sample_index) and m.sample == "shot_%d.wav" % int(c.sample)
			legal = legal and ResourceLoader.exists("res://assets/audio/groove/shot_%d.wav" % int(c.sample))
		else:
			dash_count += 1
			legal = legal and m.sample == "dash.wav" and m.sample_index == -1
		if fposmod(float(c.beat),1.0) > 0:
			half_count += 1
			legal = legal and float(c.beat) in [43.5,47.5,51.5,55.5] and c.type == "shot"
		elif c.beat < 8: legal = legal and c.type == "shot"
		else: legal = legal and c.type == ("dash" if int(c.beat)%4 == 2 else "shot")
		legal = legal and c.status == 0 and not c.sound
		check(legal, "cue%02d beat%04.1f: ordered time, action and sample match independent audio metadata" % [i,float(c.beat)])
		previous_time = c.time
	check(shot_count == 51 and dash_count == 13 and half_count == 4, "chart has51 shots,13 dashes and4 half-beat accents")
	check(absf(combat.music.stream.get_length()-float(metadata.duration)) < 0.001, "bed WAV duration matches audio metadata")

	reset()
	combat.elapsed = 2.0
	combat.music.play(5.0)
	await create_timer(0.025).timeout
	var current_audio: float = combat.audio_time()
	combat.request_action("shot")
	check(current_audio > 4.9 and combat.cues[6].status == 2 and combat.cues[0].status == 0, "request judges current audio clock despite3-second-stale cached elapsed")
	combat.music.stop()
	reset()
	var target := enemy(1,Vector2(750,450))
	combat.enemies = [target]
	request(2.0-0.149)
	check(combat.cues[0].status == 1 and combat.on_time == 0 and target.hp == 20 and combat.traces.is_empty(), "correct early press buffers without firing or damaging")
	check(combat.prepared_flash == 1 and combat.feedback.contains("已准备"), "early buffer immediately acknowledges input")
	resolve(1.999)
	check(target.hp == 20 and combat.cues[0].status == 1, "buffer does not execute before target beat")
	resolve(2.0)
	check(combat.cues[0].status == 2 and target.hp == 14 and combat.on_time == 1 and combat.perfect_shots == 1, "beat boundary executes immediate6-damage hitscan exactly once")
	resolve(2.02)
	request(2.03)
	check(target.hp == 14 and combat.on_time == 1 and combat.perfect_shots == 1, "repeat press and frame cannot execute consumed cue twice")

	for simple in [true,false]:
		var early: float = 0.15 if simple else 0.11
		var late: float = 0.14 if simple else 0.10
		reset(simple)
		request(3.0-early+0.001)
		check(combat.cues[2].status == 1 and combat.wrong_inputs == 0, "%s early window accepts at inner edge" % str(simple))
		reset(simple)
		request(3.0-early-0.001)
		check(combat.cues[2].status == 0 and combat.wrong_inputs == 1 and combat.traces.is_empty(), "%s too-early press rejects without attack" % str(simple))
		reset(simple)
		request(3.0+late-0.001)
		check(combat.cues[2].status == 2 and combat.on_time == 1, "%s late inner edge executes immediately" % str(simple))
		reset(simple)
		request(3.0+late+0.001)
		check(combat.cues[2].status == 0 and combat.wrong_inputs == 1 and combat.traces.is_empty(), "%s too-late press rejects without attack" % str(simple))
	reset()
	combat.streak = 4
	request(7.0,"shot") # beat10 is dash
	check(combat.cues[10].status == 0 and combat.wrong_inputs == 1 and combat.streak == 0 and combat.traces.is_empty() and combat.dash_total == 0, "wrong action breaks streak and neither attacks nor consumes cue")
	request(7.01,"dash")
	check(combat.cues[10].status == 2 and combat.dash_total == 1, "corrected action can recover inside same cue window")
	reset()
	request(3.25)
	check(combat.wrong_inputs == 1 and combat.on_time == 0 and combat.traces.is_empty(), "between-window input gives rejection but no weak/free attack")

	reset()
	request(23.5)
	var regular_index := cue_at(43.0)
	var half_index := cue_at(43.5)
	request(23.61)
	check(combat.cues[regular_index].status == 2 and combat.cues[half_index].status == 0 and combat.on_time == 1, "consumed nearest cue blocks spam from stealing overlapping later half cue")
	request(23.64)
	check(combat.cues[half_index].status == 1 and combat.on_time == 1, "later half cue accepts when it becomes genuinely nearer")
	request(23.65)
	resolve(23.75)
	check(combat.cues[half_index].status == 2 and combat.on_time == 2, "buffered half cue executes once at its250ms accent")
	reset()
	request(23.625)
	check(combat.cues[regular_index].status == 2 and combat.cues[half_index].status == 0, "equidistant overlap deterministically selects earlier cue")

	reset()
	for i in range(16):
		var cue: Dictionary = combat.cues[i]
		request(float(cue.time),str(cue.type))
	check(combat.on_time == 16 and combat.streak == 16 and combat.max_streak == 16 and combat.overdrives == 2, "two groups of8 consecutive cue actions including dashes trigger two overdrives")
	check(combat.dash_total == 2 and combat.perfect_shots == 14 and combat.missed_cues == 0, "mixed streak counts shot and dash cues rather than only shots")
	check(is_equal_approx(combat.overdrive_until,float(combat.cues[15].time)+2), "overdrive lasts four120BPM beats")
	reset()
	request(2.0)
	request(2.5)
	resolve(3.141)
	check(combat.cues[2].status == 3 and combat.missed_cues == 1 and combat.streak == 0, "late-window expiry marks one missed cue and breaks streak")
	resolve(3.2)
	check(combat.missed_cues == 1, "miss is not repeated on following frames")
	request(3.5)
	check(combat.streak == 1, "first successful action after missed cue restarts streak")
	request(3.75)
	check(combat.streak == 0 and combat.wrong_inputs == 1, "off-window action immediately breaks recovered streak")

	reset()
	combat.elapsed = 7.0
	combat.hurt()
	var protected_hp: int = combat.hp
	resolve(7.141)
	check(combat.cues[10].status == 3 and combat.hp == protected_hp, "missed dash respects active damage invulnerability")
	reset()
	resolve(5.99)
	combat.hurt()
	check(combat.hp == 5, "initial8-beat tutorial is damage-free below6s")
	resolve(7.139)
	check(combat.cues[10].status == 0 and combat.hp == 5, "dash wave cannot damage before easy140ms late tolerance ends")
	request(7.139,"dash")
	check(combat.cues[10].status == 2 and combat.hp == 5 and combat.dash_total == 1, "late dash inside tolerance succeeds without premature wave damage")
	reset()
	resolve(7.141)
	check(combat.cues[10].status == 3 and combat.hp == 4, "missing dash after full window causes one damage")
	resolve(7.3)
	check(combat.hp == 4, "missed dash cannot damage twice")
	reset(false)
	resolve(7.099)
	check(combat.hp == 4 and combat.cues[10].status == 0, "normal100ms dash tolerance remains safe at inner edge")
	request(7.099,"dash")
	check(combat.hp == 4 and combat.cues[10].status == 2, "normal late dash is accepted before penalty")

	reset()
	var first := enemy(1,Vector2(750,450))
	var second := enemy(2,Vector2(900,450))
	combat.enemies = [first,second]
	request(2.0)
	check(first.hp == 14 and second.hp == 14 and combat.shots.is_empty() and combat.traces.size() == 1, "cue hit is immediate piercing hitscan; no damage-bearing travel projectile")
	combat.step_projectiles(0.3)
	check(first.hp == 14 and second.hp == 14, "visual hit trace cannot damage enemies again later")

	reset()
	request(1.99)
	combat.elapsed = 2.0
	combat.schedule_cue_audio()
	check(combat.cues[0].sound and combat.response_players[0].volume_db == -1 and combat.response_players[1].volume_db == -80, "early accepted cue opens only its phase-locked response channel")
	var sound_player: AudioStreamPlayer = combat.melody_players[int(combat.cues[0].sample)]
	sound_player.stop()
	combat.resolve_cues()
	check(combat.cues[0].status == 2 and combat.cues[0].sound and not sound_player.playing, "execution honors gated-response sound flag without doubling standalone melody")
	combat.play_cue_sound(combat.cues[0])
	check(not sound_player.playing, "direct duplicate sound request remains idempotent")
	reset()
	request(6.99,"dash")
	combat.elapsed = 7.0
	combat.schedule_cue_audio()
	combat.sounds.dash.stop()
	combat.resolve_cues()
	check(combat.cues[10].sound and combat.cues[10].status == 2 and not combat.sounds.dash.playing, "dash execution also prevents double-sounding pre-scheduled sample")
	reset()
	check(combat.response_players.size() == 2 and combat.response_players[0].playing and combat.response_players[1].playing and combat.response_players[0].volume_db == -80 and combat.response_players[1].volume_db == -80, "both response stems start running silently with each new round")
	check(absf(combat.response_players[0].stream.get_length()-34.0) < 0.001 and absf(combat.response_players[1].stream.get_length()-34.0) < 0.001, "response stems share34-second bed timeline")
	request(1.90)
	resolve(2.0)
	resolve(2.251)
	check(combat.response_players[0].volume_db == -80 and combat.response_players[1].volume_db == -80, "accepted note channel closes after250ms gate deadline")
	resolve(2.65)
	check(combat.cues[1].status == 3 and not combat.cues[1].sound and combat.response_players[1].volume_db == -80, "missed opposite-channel cue stays inaudible and never arms sound")
	resolve(3.15)
	check(combat.cues[2].status == 3 and not combat.cues[2].sound and combat.response_players[0].volume_db == -80, "missed next same-channel cue cannot leak through previous accepted gate")
	reset()
	request(2.05)
	check(combat.melody_players[int(combat.cues[0].sample)].playing and combat.response_players[0].volume_db == -80 and combat.response_players[1].volume_db == -80, "late valid input uses immediate independent sample while both stems remain gated")
	reset()
	request(6.90,"dash")
	resolve(7.0)
	resolve(7.251)
	check(combat.cues[10].sound and combat.response_players[0].volume_db == -80 and combat.response_players[1].volume_db == -80, "early dash response also closes without replaying or exposing following cues")
	reset()
	request(1.90)
	combat.stop()
	var stopped: bool = not combat.music.playing
	for audio in combat.response_players: stopped = stopped and not audio.playing and not audio.stream_paused
	for audio in combat.melody_players: stopped = stopped and not audio.playing
	for audio in combat.sounds.values(): stopped = stopped and not audio.playing
	check(stopped, "stop terminates bed, both gated stems, melody and effects")
	reset()
	check(combat.response_until[0] == -1 and combat.response_until[1] == -1 and combat.response_players[0].volume_db == -80 and combat.response_players[1].volume_db == -80 and not combat.cues[0].sound, "restart clears stale gate deadlines, open gain and accepted-cue flags")
	request(1.90)
	combat.finish(false)
	check(game.screen == "combat_result" and not combat.music.playing and not combat.response_players[0].playing and not combat.response_players[1].playing, "loss stops all response stems so queued music cannot leak after defeat")

	reset()
	combat.music.play()
	combat.melody_players[0].play()
	combat.sounds.dash.play()
	await process_frame
	request(2.90)
	combat.move_keys[KEY_D] = true
	combat.touch_dir = Vector2.UP
	combat.pause_game()
	var paused_time: float = combat.elapsed
	combat.update(1.0)
	check(combat.cues[2].status == 1 and combat.on_time == 0 and combat.elapsed == paused_time and combat.move_keys.is_empty() and combat.touch_dir == Vector2.ZERO, "pause preserves pending cue and freezes timing while clearing movement")
	check(combat.music.stream_paused and combat.melody_players[0].stream_paused and combat.sounds.dash.stream_paused, "pause freezes music, melody and dash sample streams")
	check(combat.response_players[0].stream_paused and combat.response_players[1].stream_paused and combat.response_players[0].volume_db == -1, "pause freezes both response stems while preserving pending open gate")
	combat.resume_game()
	check(not combat.music.stream_paused and not combat.melody_players[0].stream_paused and not combat.sounds.dash.stream_paused and combat.cues[2].status == 1, "resume restores music/sample streams and keeps pending cue")
	check(not combat.response_players[0].stream_paused and not combat.response_players[1].stream_paused and combat.response_players[0].volume_db == -1, "resume retains response gate and unpauses both stems")
	combat.music.stop()
	resolve(3.0)
	check(combat.cues[2].status == 2 and combat.on_time == 1, "pending action resolves once after resume")

	reset()
	for cue in combat.cues:
		request(float(cue.time),str(cue.type))
	resolve(31.7)
	check(combat.on_time == 64 and combat.missed_cues == 0 and combat.wrong_inputs == 0 and combat.streak == 64 and combat.overdrives == 8, "complete64-cue performance resolves all actions with8 overdrives and no misses")
	check(combat.perfect_shots == 51 and combat.dash_total == 13 and combat.next_cue == 64, "complete chart yields exactly51 shots and13 dashes")
	combat.finish(true)
	var finished_score: int = combat.score
	combat.finish(true)
	combat.request_action("shot")
	check(combat.score == finished_score and game.screen == "combat_result", "finish and post-result input cannot duplicate score")

	combat.stop()
	game.queue_free()
	combat = null
	game = null
	sound_player = null
	await process_frame
	await create_timer(0.35).timeout
	output.append("Cleanup: freed scene and references; waited350ms for pending audio playback retirement.")
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/groove-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
