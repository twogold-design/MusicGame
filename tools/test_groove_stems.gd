extends SceneTree

var host
var lines: Array[String] = []
var failures := 0
var bed_samples := PackedVector2Array()
var stem_samples: Array = [PackedVector2Array(),PackedVector2Array()]

func _initialize() -> void:
	call_deferred("run")

func report(message: String) -> void:
	lines.append(message)
	print(message)

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	report(("PASS " if ok else "FAIL ")+message)

func capture_bus(name: String) -> AudioEffectCapture:
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,name)
	AudioServer.set_bus_send(index,"Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(index,capture)
	return capture

func onset(samples: PackedVector2Array, first := 0, last := -1) -> int:
	for i in range(first,samples.size() if last<0 else mini(last,samples.size())):
		if maxf(absf(samples[i].x),absf(samples[i].y))>0.0005: return i
	return -1

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/groove-audio-test-roaming"):
		push_error("Refusing normal save directory")
		quit(2)
		return
	report("FORMAL RUNTIME response_players gate / actual mixer capture")
	host = load("res://main.tscn").instantiate()
	host.set_process(false)
	root.add_child(host)
	host.set_process(false)
	host.set_process_input(false)
	host.muted = false
	host.set_audio()
	var combat = host.combat
	var bed_capture := capture_bus("StemTestBed")
	var captures := [capture_bus("StemTestEven"),capture_bus("StemTestOdd")]
	var tracks: Array[AudioStreamPlayer] = combat.response_players
	for channel in range(2): tracks[channel].bus = "StemTestEven" if channel==0 else "StemTestOdd"
	combat.music.bus = "StemTestBed"
	combat.start()
	combat.hp = 999
	combat.max_hp = 999
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	var target_cues := [metadata.cues[3],metadata.cues[4],metadata.cues[5]]
	var opened := [false,false,false]
	var closed := [false,false,false]
	var late_requested := false
	var pause_started := -1.0
	var pause_snapshot: Array[float] = []
	var pause_elapsed := 0.0
	var pause_captured := false
	var resumed := false
	var early_independent_play := false
	var beginning := Time.get_ticks_usec()
	var last := beginning
	report("mix_rate=%s latency=%s"%[AudioServer.get_mix_rate(),AudioServer.get_output_latency()])
	while (Time.get_ticks_usec()-beginning)/1000000.0<8.0:
		await process_frame
		var tick := Time.get_ticks_usec()
		combat.update((tick-last)/1000000.0)
		last = tick
		if combat.now()<4.95:
			for note in combat.melody_players:
				if note.playing: early_independent_play = true
		for i in range(3):
			var cue: Dictionary = target_cues[i]
			var channel := int(cue.stem_channel)
			if not opened[i] and combat.now()>=float(cue.time)-0.145:
				opened[i] = true
				combat.request_action("shot")
				report("FORMAL REQUEST cue=%.3f heard=%.6f bed_raw=%.6f stem_raw=%.6f channel=%d gate_db=%.1f"%[cue.time,combat.now(),combat.music.get_playback_position(),tracks[channel].get_playback_position(),channel,tracks[channel].volume_db])
				check(combat.cues[int(cue.index)].sound and tracks[channel].volume_db>-2,"formal early request arms the response stem")
			if opened[i] and not closed[i] and combat.now()>=float(cue.time)+float(cue.note_duration):
				closed[i] = true
				report("FORMAL TAIL cue=%.3f heard=%.6f gate_db=%.1f"%[cue.time,combat.now(),tracks[channel].volume_db])
		if not late_requested and combat.now()>=5.055:
			late_requested = true
			combat.request_action("shot")
			report("FORMAL LATE cue=5.000 heard=%.6f gates=[%.1f,%.1f] independent=%s"%[combat.now(),tracks[0].volume_db,tracks[1].volume_db,combat.melody_players[int(combat.cues[6].sample)].playing])
			check(combat.cues[6].sound and int(combat.cues[6].status)==2 and tracks[0].volume_db==-80 and tracks[1].volume_db==-80,"late input uses immediate sample without opening a response stem")
			check(combat.melody_players[int(combat.cues[6].sample)].playing,"late sample actually starts")
		if pause_started<0 and combat.now()>=5.7:
			combat.pause_game()
			pause_started = (tick-beginning)/1000000.0
			pause_elapsed = combat.elapsed
			pause_snapshot = [combat.music.get_playback_position(),tracks[0].get_playback_position(),tracks[1].get_playback_position()]
		elif pause_started>=0 and not pause_captured and (tick-beginning)/1000000.0-pause_started>0.15:
			pause_captured = true
			# Pause requests take effect on the next audio mix callback.
			pause_snapshot = [combat.music.get_playback_position(),tracks[0].get_playback_position(),tracks[1].get_playback_position()]
			report("PAUSE settled raw bed=%.6f even=%.6f odd=%.6f elapsed=%.6f"%[pause_snapshot[0],pause_snapshot[1],pause_snapshot[2],combat.elapsed])
		elif pause_started>=0 and not resumed and (tick-beginning)/1000000.0-pause_started>0.4:
			var position_error := maxf(absf(pause_snapshot[0]-combat.music.get_playback_position()),maxf(absf(pause_snapshot[1]-tracks[0].get_playback_position()),absf(pause_snapshot[2]-tracks[1].get_playback_position())))
			check(combat.elapsed==pause_elapsed and position_error<0.001,"formal pause freezes bed, both response stems and elapsed")
			combat.resume_game()
			resumed = true
		bed_samples.append_array(bed_capture.get_buffer(bed_capture.get_frames_available()))
		for i in range(2): stem_samples[i].append_array(captures[i].get_buffer(captures[i].get_frames_available()))
	check(tracks[0].volume_db==-80 and tracks[1].volume_db==-80,"formal runtime closes both response gates after tails")
	check(not early_independent_play,"accepted early cues never replay independent samples")
	check(resumed and absf(combat.music.get_playback_position()-tracks[0].get_playback_position())<0.001 and absf(combat.music.get_playback_position()-tracks[1].get_playback_position())<0.001,"formal resume preserves bed/response phase")
	combat.stop()
	for audio in tracks: audio.stop()
	var bed_onset := onset(bed_samples)
	var rate := AudioServer.get_mix_rate()
	var errors: Array[float] = []
	if bed_onset<0: report("UNAVAILABLE no bed audio captured")
	else:
		for cue in target_cues:
			var at := int(bed_onset+(float(cue.time)-0.12)*rate)
			var end := int(bed_onset+(float(cue.time)+0.12)*rate)
			var note_onset := onset(stem_samples[int(cue.stem_channel)],at,end)
			if note_onset<0:
				check(false,"cue %.3f audible response captured"%cue.time)
				continue
			var relative := (note_onset-bed_onset)/rate
			var error := (relative-float(cue.time))*1000
			errors.append(absf(error))
			report("CAPTURE cue=%.3f bed_frame=%d note_frame=%d delta=%.9f error_ms=%.3f"%[cue.time,bed_onset,note_onset,relative,error])
			check(absf(error)<3,"cue %.3f pre-rendered response aligns within 3ms"%cue.time)
		for absent_time in [2.0,2.5,3.0,5.0,5.5]:
			var channel := int(round((absent_time-2.0)/0.5))%2
			var first := int(bed_onset+(absent_time-0.05)*rate)
			var last_sample := int(bed_onset+(absent_time+0.23)*rate)
			check(onset(stem_samples[channel],first,last_sample)<0,"unarmed/late cue %.3f never leaks from response stem"%absent_time)
	for channel in range(2): check(captures[channel].get_discarded_frames()==0,"capture channel %d discarded no frames"%channel)
	if not errors.is_empty(): report("MEAN_ABSOLUTE_CAPTURE_ERROR_MS %.3f"%(errors.reduce(func(a,b): return a+b,0.0)/errors.size()))
	host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	report("RESULT failures=%d"%failures)
	var file := FileAccess.open("res://artifacts/groove-stem-gating-results.txt",FileAccess.WRITE)
	file.store_string("\n".join(lines)+"\n")
	file.close()
	quit(1 if failures else 0)
