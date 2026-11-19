extends SceneTree

var hosts: Array = []
var stats: Array = []
var lines: Array[String] = []
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func record(value: String) -> void:
	lines.append(value)
	print(value)

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	record(("PASS " if ok else "FAIL ") + description)

func circular_distance(a: float, b: float, length: float) -> float:
	var difference := absf(a-b)
	return minf(difference,absf(length-difference))

func run() -> void:
	record("Adventure actual audio runtime / " + Engine.get_version_info().string)
	record("Save isolation: " + OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/adventure-audio-test-roaming"):
		push_error("Refusing to run against normal user storage")
		quit(2)
		return
	for index in range(3):
		var host = load("res://main.tscn").instantiate()
		host.set_process(false)
		root.add_child(host)
		host.set_process(false)
		host.set_process_input(false)
		host.selected = index
		host.easy = true
		host.adventure.new_run(29781)
		host.adventure.player = host.adventure.HOME
		host.adventure.repaired = 3
		hosts.append(host)
		stats.append({"last":0.0,"backward":0,"max_step":0.0,"max_drift":0.0,"max_clock_error":0.0,"raw_max":0.0,"pause_elapsed":0.0,"pause_positions":[],"max_pause_position_change":0.0,"clock_after_pause":0.0})
		for stem in host.adventure.players:
			check(stem.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stem.stream.loop_begin == 0 and stem.stream.loop_end == int(round(host.adventure.loop_length*stem.stream.mix_rate)), "%s correct loop points: %d frames" % [host.IDS[index],stem.stream.loop_end])
	var beginning := Time.get_ticks_usec()
	var previous_wall := 0.0
	var pause_started := -1.0
	var resume_at := -1.0
	var pause_captured := false
	var announced := 0
	while true:
		await process_frame
		var wall := (Time.get_ticks_usec()-beginning)/1000000.0
		var delta := wall-previous_wall
		previous_wall = wall
		if pause_started<0 and wall>=11.0:
			pause_started = wall
			for i in range(hosts.size()):
				hosts[i].adventure.pause_game()
				stats[i].pause_elapsed = hosts[i].adventure.elapsed
			record("Pausing all twelve streams at wall %.3f" % wall)
		if pause_started>=0 and not pause_captured and wall>=pause_started+0.25:
			pause_captured = true
			for i in range(hosts.size()):
				for stem in hosts[i].adventure.players: stats[i].pause_positions.append(stem.get_playback_position())
		if pause_started>=0 and resume_at<0 and wall>=pause_started+1.1:
			resume_at = wall
			for i in range(hosts.size()):
				var adv = hosts[i].adventure
				check(adv.elapsed == stats[i].pause_elapsed, "%s elapsed is frozen during pause" % hosts[i].IDS[i])
				check(stats[i].max_pause_position_change < 0.003, "%s four player positions frozen during pause: %.6fs" % [hosts[i].IDS[i],stats[i].max_pause_position_change])
				adv.resume_game()
				stats[i].clock_after_pause = adv.elapsed
			record("Resuming all streams at wall %.3f" % wall)
		var paused := pause_started>=0 and resume_at<0
		var paused_seconds := (wall-pause_started if paused else resume_at-pause_started) if pause_started>=0 else 0.0
		for i in range(hosts.size()):
			var host = hosts[i]
			var adv = host.adventure
			var s: Dictionary = stats[i]
			adv.update(delta)
			if paused and pause_captured:
				for j in range(4): s.max_pause_position_change = maxf(s.max_pause_position_change,absf(adv.players[j].get_playback_position()-float(s.pause_positions[j])))
			if not paused:
				var clock_delta: float = adv.elapsed-float(s.last)
				if clock_delta < -0.0001: s.backward += 1
				s.max_step = maxf(s.max_step,clock_delta)
				var active_wall := wall-paused_seconds
				if wall>1.0: s.max_clock_error = maxf(s.max_clock_error,absf(adv.elapsed-active_wall))
				s.last = adv.elapsed
			var positions: Array[float] = []
			for stem in adv.players: positions.append(stem.get_playback_position())
			s.raw_max = maxf(s.raw_max,positions[0])
			for position in positions:
				s.max_drift = maxf(s.max_drift,circular_distance(positions[0],position,adv.loop_length))
		if wall>=float(announced+1)*5.0:
			announced += 1
			record("wall %.2f / elapsed [%0.3f, %0.3f, %0.3f] / wraps [%d,%d,%d]" % [wall,hosts[0].adventure.elapsed,hosts[1].adventure.elapsed,hosts[2].adventure.elapsed,hosts[0].adventure.wraps,hosts[1].adventure.wraps,hosts[2].adventure.wraps])
		if wall>=25.0: break
	for i in range(hosts.size()):
		var host = hosts[i]
		var adv = host.adventure
		var s: Dictionary = stats[i]
		record("METRICS %s %s" % [host.IDS[i],JSON.stringify({"elapsed":adv.elapsed,"wraps":adv.wraps,"loop_length":adv.loop_length,"maximum_raw_position":s.raw_max,"maximum_clock_step":s.max_step,"maximum_wall_clock_error":s.max_clock_error,"maximum_stem_drift":s.max_drift,"backward_steps":s.backward})])
		check(adv.elapsed > 2.0*adv.loop_length, "%s actually ran beyond two loops" % host.IDS[i])
		check(s.backward==0 and s.max_step<0.25, "%s audio_time remains monotonic without loop jumps" % host.IDS[i])
		check(s.max_clock_error<0.25, "%s musical clock matches active wall time within 250ms" % host.IDS[i])
		check(s.max_drift<0.03, "%s all four stems stay within 30ms" % host.IDS[i])
		check(adv.wraps==int(floor(adv.elapsed/adv.loop_length)) and s.raw_max<=adv.loop_length+0.05, "%s raw playback wraps and wrap count matches elapsed" % host.IDS[i])
		for stem in adv.players: check(stem.playing and not stem.stream_paused and absf(stem.volume_db+3.0)<0.01, "%s unlocked stem is still looping at -3dB" % host.IDS[i])
		adv.stop_audio()
		host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	record("RESULT: %d checks, %d failures" % [checks,failures])
	var report := FileAccess.open("res://artifacts/adventure-audio-results.txt",FileAccess.WRITE)
	report.store_string("\n".join(lines)+"\n")
	report.close()
	quit(1 if failures else 0)
