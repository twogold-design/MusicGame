extends SceneTree
# HISTORICAL dynamic-play scheduling experiment, kept for timing evidence.
# Current production validation is tools/test_groove_stems.gd and its report
# artifacts/groove-stem-gating-results.txt. Failures here describe old methods.

var host
var lines: Array[String] = []
var failures := 0
var mode := "current"
var indices := [3,4,5]
var bed_samples := PackedVector2Array()
var notes: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]

func _initialize() -> void:
	call_deferred("run")

func report(message: String) -> void:
	lines.append(message)
	print(message)

func check(ok: bool,message: String) -> void:
	if not ok: failures += 1
	report(("PASS " if ok else "FAIL ")+message)

func first_onset(samples: PackedVector2Array) -> int:
	for index in range(samples.size()):
		if absf(samples[index].x)>0.0005 or absf(samples[index].y)>0.0005: return index
	return -1

func create_capture(name: String) -> AudioEffectCapture:
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,name)
	AudioServer.set_bus_send(index,"Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(index,capture)
	return capture

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/groove-audio-test-roaming"):
		push_error("Refusing normal save directory")
		quit(2)
		return
	report("Actual three-cue mixer capture / mode="+mode+" / "+Engine.get_version_info().string)
	host = load("res://main.tscn").instantiate()
	host.set_process(false)
	root.add_child(host)
	host.set_process(false)
	host.set_process_input(false)
	host.muted = false
	host.set_audio()
	host.offset_ms = 0
	host.easy = true
	var combat = host.combat
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	var chart: Array = combat.make_chart()
	check(chart.size()==metadata.cues.size(),"chart cue count matches metadata")
	var matched := 0
	for i in range(mini(chart.size(),metadata.cues.size())):
		var cue: Dictionary = chart[i]
		var expected: Dictionary = metadata.cues[i]
		if absf(float(cue.beat)-float(expected.beat))<0.00001 and absf(float(cue.time)-float(expected.time))<0.00001 and cue.type==expected.action and (cue.type=="dash" or int(cue.sample)==int(expected.sample_index)): matched += 1
	check(matched==64,"all 64 cue beats/types/times/shot indices match metadata")
	var bed_capture := create_capture("GrooveBedCapture")
	var captures: Array[AudioEffectCapture] = []
	for i in range(3): captures.append(create_capture("GrooveNote%d"%i))
	combat.music.bus = "GrooveBedCapture"
	for i in range(3): combat.melody_players[int(chart[indices[i]].sample)].bus = "GrooveNote%d"%i
	combat.start()
	combat.hp = 999
	combat.max_hp = 999
	var started := Time.get_ticks_usec()
	var last := started
	var requested := [false,false,false]
	var submitted := [false,false,false]
	var executed := [false,false,false]
	report("mix_rate=%s output_latency=%s" % [AudioServer.get_mix_rate(),AudioServer.get_output_latency()])
	while (Time.get_ticks_usec()-started)/1000000.0<8.0:
		await process_frame
		var tick := Time.get_ticks_usec()
		var delta := (tick-last)/1000000.0
		last = tick
		if mode!="current":
			for i in range(3):
				if not submitted[i]: combat.cues[indices[i]].sound = true
		combat.update(delta)
		if mode!="current":
			for i in range(3):
				if not submitted[i]: combat.cues[indices[i]].sound = false
		for i in range(3):
			var cue: Dictionary = combat.cues[indices[i]]
			if not requested[i] and combat.now()>=float(cue.time)-0.145:
				requested[i] = true
				report("REQUEST cue=%.3f heard=%.6f raw=%.6f" % [cue.time,combat.now(),combat.music.get_playback_position()])
				if mode!="current": cue.sound = true
				combat.request_action("shot")
				if mode!="current" and not submitted[i]: cue.sound = false
			if mode!="current" and requested[i] and not submitted[i]:
				var horizon: float = combat.now()
				if mode=="heard-pluslat": horizon += AudioServer.get_output_latency()
				elif mode=="raw": horizon = combat.music.get_playback_position()
				if horizon>=float(cue.time): combat.play_cue_sound(cue)
			if cue.sound and not submitted[i]:
				submitted[i] = true
				report("SUBMIT cue=%.3f wall=%.6f heard=%.6f raw=%.6f nextmix=%.6f" % [cue.time,(tick-started)/1000000.0,combat.now(),combat.music.get_playback_position(),AudioServer.get_time_to_next_mix()])
			if int(cue.status)==2 and not executed[i]:
				executed[i] = true
				report("EXECUTE cue=%.3f heard=%.6f" % [cue.time,combat.now()])
		bed_samples.append_array(bed_capture.get_buffer(bed_capture.get_frames_available()))
		for i in range(3): notes[i].append_array(captures[i].get_buffer(captures[i].get_frames_available()))
	combat.stop()
	var bed_onset := first_onset(bed_samples)
	var absolute_error_sum := 0.0
	for i in range(3):
		var note_onset := first_onset(notes[i])
		var target: float = chart[indices[i]].time
		check(requested[i] and submitted[i] and executed[i],"cue %.3f buffered, played and executed"%target)
		if bed_onset>=0 and note_onset>=0:
			var difference := (note_onset-bed_onset)/AudioServer.get_mix_rate()
			var error := (difference-target)*1000
			absolute_error_sum += absf(error)
			report("CAPTURE cue=%.3f bed_frame=%d note_frame=%d actual_delta=%.9f error_ms=%.3f"%[target,bed_onset,note_onset,difference,error])
			check(absf(error)<35,"cue %.3f aligns within 35ms"%target)
		else: report("UNAVAILABLE capture has no usable signal")
	report("MEAN_ABSOLUTE_CAPTURE_ERROR_MS %.3f"%(absolute_error_sum/3))
	check(bed_capture.get_discarded_frames()==0,"bed capture discarded no frames")
	for capture in captures: check(capture.get_discarded_frames()==0,"note capture discarded no frames")
	host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	report("RESULT failures=%d"%failures)
	var output := FileAccess.open("res://artifacts/groove-audio-%s-results.txt"%mode,FileAccess.WRITE)
	output.store_string("\n".join(lines)+"\n")
	output.close()
	quit(1 if failures else 0)
