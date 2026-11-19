extends SceneTree

var host
var lines: Array[String] = []
var checks := 0
var failures := 0
var mixed := PackedVector2Array()
var bed_samples := PackedVector2Array()
var stems: Array = [PackedVector2Array(),PackedVector2Array()]
var sfx_samples := PackedVector2Array()

func _initialize() -> void:
	call_deferred("run")

func report(message: String) -> void:
	lines.append(message)
	print(message)

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1
	report(("PASS " if ok else "FAIL ")+message)

func capture_bus(name: String,master := false) -> AudioEffectCapture:
	var index := 0
	if not master:
		AudioServer.add_bus()
		index = AudioServer.bus_count-1
		AudioServer.set_bus_name(index,name)
		AudioServer.set_bus_send(index,"Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(index,capture)
	return capture

func onset(samples: PackedVector2Array,first := 0,last := -1) -> int:
	for i in range(first,samples.size() if last<0 else mini(last,samples.size())):
		if maxf(absf(samples[i].x),absf(samples[i].y))>0.0005: return i
	return -1

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/demolition-audio-test-roaming"):
		push_error("Refusing normal save directory")
		quit(2)
		return
	report("DEMOLITION FORMAL MIXED AUDIO CAPTURE / "+Engine.get_version_info().string)
	report("Isolated save: "+OS.get_user_data_dir())
	host = load("res://main.tscn").instantiate()
	host.set_process(false)
	root.add_child(host)
	host.set_process(false)
	host.set_process_input(false)
	host.easy = true
	host.offset_ms = 0
	host.muted = false
	host.set_audio()
	var demo = host.combat
	check(demo.get_script().resource_path=="res://scripts/rhythm_demolition.gd","main actually runs demolition class")
	var master_capture := capture_bus("",true)
	var bed_capture := capture_bus("DemolitionBed")
	var even_capture := capture_bus("DemolitionEven")
	var odd_capture := capture_bus("DemolitionOdd")
	var material_capture := capture_bus("DemolitionSFX")
	demo.music.bus = "DemolitionBed"
	demo.response_players[0].bus = "DemolitionEven"
	demo.response_players[1].bus = "DemolitionOdd"
	for audio in demo.demo_sounds.values(): audio.bus = "DemolitionSFX"
	demo.start()
	demo.hp = 999
	check(demo.cues.size()==64,"all 64 response cue slots retained")
	for name in demo.demo_sounds:
		check(demo.demo_sounds[name].stream.get_length()<0.29,"%s material voice has bounded short duration"%name)
	var beginning := Time.get_ticks_usec()
	var last := beginning
	var tapped := false
	var heavy_pressed := false
	var heavy_released := false
	var stress_hits := 0
	var stress_next := 6.11
	var tail_checked := false
	var sfx_heard := false
	var sfx_tail_peak := 0.0
	var pause_start := -1.0
	var pause_captured := false
	var resumed := false
	var pause_positions: Array[float] = []
	var paused_elapsed := 0.0
	var paused_materials: Array[AudioStreamPlayer] = []
	var maximum_drift := 0.0
	var maximum_active_materials := 0
	var duplicate_early_voice := false
	var total_peak := 0.0
	var clipped_frames := 0
	while (Time.get_ticks_usec()-beginning)/1000000.0<11.5:
		await process_frame
		var tick := Time.get_ticks_usec()
		demo.update((tick-last)/1000000.0)
		last = tick
		var time: float = demo.now()
		if not tapped and time>=3.355:
			tapped = true
			demo.press("audio_test")
			demo.release("audio_test")
			report("TAP queued cue=3.500 heard=%.6f target=%d"%[demo.now(),demo.target_id])
			check(demo.cues[3].sound and int(demo.cues[3].status)==1,"ordinary tap arms the scheduled melody")
		if not heavy_pressed and time>=4.855:
			heavy_pressed = true
			demo.press("audio_test")
			report("HEAVY PRESS heard=%.6f charge=%.6f"%[demo.now(),demo.charge_start])
		if not heavy_released and time>=5.355:
			heavy_released = true
			demo.release("audio_test")
			report("HEAVY RELEASE queued cue=5.500 heard=%.6f"%demo.now())
			check(demo.cues[7].kind=="heavy" and demo.cues[7].sound,"held release queues an on-beat heavy smash")
		if time<5.8:
			for audio in demo.melody_players:
				if audio.playing: duplicate_early_voice = true
			if demo.sounds.dash.playing: duplicate_early_voice = true
		if time>=stress_next and stress_next<7.81:
			demo.press("stress_test")
			demo.release("stress_test")
			stress_next += 0.155
			stress_hits += 1
		var active := 0
		for audio in demo.demo_sounds.values():
			if audio.playing: active += 1
		maximum_active_materials = maxi(maximum_active_materials,active)
		if time>8.35 and not tail_checked:
			tail_checked = true
			check(active==0,"all material/thump players stop after the last short tail")
		if pause_start<0 and time>=5.58:
			for audio in demo.demo_sounds.values():
				if audio.playing: paused_materials.append(audio)
			demo.pause_game()
			pause_start = (tick-beginning)/1000000.0
			paused_elapsed = demo.elapsed
		elif pause_start>=0 and not pause_captured and (tick-beginning)/1000000.0-pause_start>0.15:
			pause_captured = true
			pause_positions = [demo.music.get_playback_position(),demo.response_players[0].get_playback_position(),demo.response_players[1].get_playback_position()]
		elif pause_start>=0 and not resumed and (tick-beginning)/1000000.0-pause_start>0.4:
			var difference := maxf(absf(pause_positions[0]-demo.music.get_playback_position()),maxf(absf(pause_positions[1]-demo.response_players[0].get_playback_position()),absf(pause_positions[2]-demo.response_players[1].get_playback_position())))
			check(demo.elapsed==paused_elapsed and difference<0.001,"pause freezes formal bed and both response stems")
			var materials_paused := not paused_materials.is_empty()
			for audio in paused_materials: materials_paused = materials_paused and audio.stream_paused
			check(materials_paused,"pause freezes the %d material/thump voices active at the impact"%paused_materials.size())
			demo.resume_game()
			resumed = true
		var raw: float = demo.music.get_playback_position()
		for audio in demo.response_players: maximum_drift = maxf(maximum_drift,absf(raw-audio.get_playback_position()))
		var mix_chunk := master_capture.get_buffer(master_capture.get_frames_available())
		for frame in mix_chunk:
			var peak := maxf(absf(frame.x),absf(frame.y))
			total_peak = maxf(total_peak,peak)
			if peak>=1.0: clipped_frames += 1
		mixed.append_array(mix_chunk)
		bed_samples.append_array(bed_capture.get_buffer(bed_capture.get_frames_available()))
		stems[0].append_array(even_capture.get_buffer(even_capture.get_frames_available()))
		stems[1].append_array(odd_capture.get_buffer(odd_capture.get_frames_available()))
		var sfx_chunk := material_capture.get_buffer(material_capture.get_frames_available())
		for frame in sfx_chunk:
			if maxf(absf(frame.x),absf(frame.y))>0.001: sfx_heard = true
			if time>8.4: sfx_tail_peak = maxf(sfx_tail_peak,maxf(absf(frame.x),absf(frame.y)))
		sfx_samples.append_array(sfx_chunk)
	report("MIX measured_peak=%.6f clipped_frames=%d captured_frames=%d stress_inputs=%d max_active_material_players=%d post_tail_sfx_peak=%.9f"%[total_peak,clipped_frames,mixed.size(),stress_hits,maximum_active_materials,sfx_tail_peak])
	check(total_peak>0.1 and total_peak<1.0 and clipped_frames==0,"actual full master mix including destruction never clips")
	check(tapped and heavy_pressed and heavy_released and demo.heavy_hits>=1,"ordinary and heavy impacts actually execute")
	check(sfx_heard,"material and thump audio actually reaches the mix")
	check(stress_hits>=10 and sfx_tail_peak<0.0001,"rapid inputs never leave accumulating material tails")
	check(not duplicate_early_voice,"on-beat responses never double-play independent melody/dash samples")
	check(resumed and maximum_drift<0.001,"pause/resume keeps exact bed/response phase; max drift %.6fs"%maximum_drift)
	demo.stop()
	var rate := AudioServer.get_mix_rate()
	var bed_start := onset(bed_samples)
	check(bed_start>=0,"actual backing audio captured")
	if bed_start>=0:
		for target in [3.5,5.0,5.5]:
			var index := int(round((target-2.0)/0.5))
			var sample := onset(stems[index%2],int(bed_start+(target-0.12)*rate),int(bed_start+(target+0.12)*rate))
			if sample<0:
				check(false,"accepted response %.3f captured"%target)
			else:
				var delta := (sample-bed_start)/rate
				report("RESPONSE cue=%.3f bed_frame=%d note_frame=%d relative=%.9f error_ms=%.3f"%[target,bed_start,sample,delta,(delta-target)*1000])
				check(absf(delta-target)<0.003,"accepted response %.3f aligns with bed within 3ms"%target)
		for target in [2.0,2.5,3.0,4.0,4.5]:
			var index := int(round((target-2.0)/0.5))
			var sample := onset(stems[index%2],int(bed_start+(target-0.04)*rate),int(bed_start+(target+0.23)*rate))
			check(sample<0,"missed cue %.3f leaks no response melody"%target)
	for capture in [master_capture,bed_capture,even_capture,odd_capture,material_capture]: check(capture.get_discarded_frames()==0,"capture discarded no frames")
	host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	report("RESULT: %d checks, %d failures"%[checks,failures])
	var file := FileAccess.open("res://artifacts/demolition-audio-results.txt",FileAccess.WRITE)
	file.store_string("\n".join(lines)+"\n")
	file.close()
	quit(1 if failures else 0)
