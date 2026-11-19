extends SceneTree

var host
var lines: Array[String] = []
var checks := 0
var failures := 0
var mixed := PackedVector2Array()
var bed_samples := PackedVector2Array()
var guide_samples := PackedVector2Array()
var stems: Array = [PackedVector2Array(),PackedVector2Array()]

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

func raw_rms(data: PackedFloat32Array,first: int,count: int) -> float:
	var sum := 0.0
	for i in range(first,mini(first+count,data.size())): sum += float(data[i])*float(data[i])
	return sqrt(sum/maxi(1,count))

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/wreck3d-audio-test-roaming"):
		push_error("Refusing normal save directory")
		quit(2)
		return
	report("WRECK3D ACTUAL INPUT + MASTER MIX + BREAK AUDIO CAPTURE / "+Engine.get_version_info().string)
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
	var game = host.combat
	check(game.get_script().resource_path=="res://scripts/rhythm_wreck3d.gd","main uses the actual 3D wrecking class")
	check(game.stage is Node3D and game.camera is Camera3D and game.view is SubViewport,"actual 3D stage, camera and viewport exist")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/wreck3d/metadata.json"))
	var chart: Array = game.make_chart()
	check(chart.size()==102,"actual chart has 96 quarter cues plus six optional halfbeats")
	var consistent := 0
	for i in range(chart.size()):
		var cue: Dictionary = chart[i]
		var source: Dictionary = metadata.cues[i]
		if absf(float(cue.time)-float(source.time))<0.000001 and absf(float(cue.beat)-float(source.beat))<0.000001 and int(cue.sample)==int(source.sample_index) and cue.voice==source.voice and i%2==int(source.stem_channel) and cue.type=="tap": consistent += 1
	check(consistent==102,"every global index, sample_index, voice, time and stem channel matches PCM metadata")
	for audio in [game.music,game.response_players[0],game.response_players[1],game.beat_guide]:
		check(absf(audio.stream.get_length()-52.0)<0.0001,"bed/response/guide stream has exact 52 second duration")
	var master_capture := capture_bus("",true)
	var bed_capture := capture_bus("Wreck3DBed")
	var even_capture := capture_bus("Wreck3DEven")
	var odd_capture := capture_bus("Wreck3DOdd")
	var guide_capture := capture_bus("Wreck3DGuide")
	game.music.bus = "Wreck3DBed"
	game.response_players[0].bus = "Wreck3DEven"
	game.response_players[1].bus = "Wreck3DOdd"
	game.beat_guide.bus = "Wreck3DGuide"
	game.start()
	game.hp = 999
	var stage_identity: int = game.stage.get_instance_id()
	var selected_times := [3.5,5.0,5.5,19.5]
	var indices: Array[int] = []
	for target in selected_times:
		for i in range(chart.size()):
			if absf(float(chart[i].time)-target)<0.000001: indices.append(i)
	var tapped := false
	var heavy_pressed := false
	var heavy_released := false
	var break_tapped := false
	var began := Time.get_ticks_usec()
	var last := began
	var maximum_peak := 0.0
	var clipped_frames := 0
	var maximum_drift := 0.0
	var maximum_guide_drift := 0.0
	var independent_voice := false
	var pause_start := -1.0
	var pause_captured := false
	var paused_elapsed := 0.0
	var pause_positions: Array[float] = []
	var resumed := false
	var heard_material := false
	report("mix_rate=%s output_latency=%s"%[AudioServer.get_mix_rate(),AudioServer.get_output_latency()])
	while (Time.get_ticks_usec()-began)/1000000.0<23.0:
		await process_frame
		var tick := Time.get_ticks_usec()
		game.update((tick-last)/1000000.0)
		last = tick
		var time: float = game.now()
		if not tapped and time>=3.355:
			tapped = true
			game.press("capture")
			game.release("capture")
			report("TAP cue=3.500 heard=%.6f raw=%.6f"%[game.now(),game.music.get_playback_position()])
		if not heavy_pressed and time>=4.855:
			heavy_pressed = true
			game.press("capture")
		if not heavy_released and time>=5.355:
			heavy_released = true
			game.release("capture")
			report("HEAVY RELEASE cue=5.500 heard=%.6f"%game.now())
		if not break_tapped and time>=19.355:
			break_tapped = true
			game.press("capture")
			game.release("capture")
			report("BREAK TAP cue=19.500 heard=%.6f"%game.now())
		for audio in game.melody_players:
			if audio.playing: independent_voice = true
		if game.sounds.dash.playing: independent_voice = true
		for audio in game.demo_sounds.values():
			if audio.playing: heard_material = true
		var raw: float = game.music.get_playback_position()
		for audio in game.response_players: maximum_drift = maxf(maximum_drift,absf(raw-audio.get_playback_position()))
		maximum_guide_drift = maxf(maximum_guide_drift,absf(raw-game.beat_guide.get_playback_position()))
		var wall := (tick-began)/1000000.0
		if pause_start<0 and time>=20.7:
			game.pause_game()
			pause_start = wall
			paused_elapsed = game.elapsed
		elif pause_start>=0 and not pause_captured and wall-pause_start>0.15:
			pause_captured = true
			pause_positions = [game.music.get_playback_position(),game.response_players[0].get_playback_position(),game.response_players[1].get_playback_position(),game.beat_guide.get_playback_position()]
		elif pause_start>=0 and not resumed and wall-pause_start>0.4:
			var drift := maxf(absf(pause_positions[0]-game.music.get_playback_position()),maxf(absf(pause_positions[1]-game.response_players[0].get_playback_position()),absf(pause_positions[2]-game.response_players[1].get_playback_position())))
			drift = maxf(drift,absf(pause_positions[3]-game.beat_guide.get_playback_position()))
			check(game.elapsed==paused_elapsed and drift<0.001,"pause freezes musical time and all four 52s streams including guide")
			game.resume_game()
			resumed = true
		var chunk := master_capture.get_buffer(master_capture.get_frames_available())
		for frame in chunk:
			var peak := maxf(absf(frame.x),absf(frame.y))
			maximum_peak = maxf(maximum_peak,peak)
			if peak>=1: clipped_frames += 1
		mixed.append_array(chunk)
		bed_samples.append_array(bed_capture.get_buffer(bed_capture.get_frames_available()))
		stems[0].append_array(even_capture.get_buffer(even_capture.get_frames_available()))
		stems[1].append_array(odd_capture.get_buffer(odd_capture.get_frames_available()))
		guide_samples.append_array(guide_capture.get_buffer(guide_capture.get_frames_available()))
	check(tapped and heavy_pressed and heavy_released and break_tapped and game.heavy_hits>=1,"ordinary tap, charged heavy and break tap really execute")
	check(heard_material,"real 3D destruction sound reaches the master path")
	check(game.stage.get_instance_id()==stage_identity,"one continuous 3D stage survives all tested music sections")
	check(resumed and maximum_drift<0.001,"bed and response streams start in phase and retain phase after pause")
	check(resumed and maximum_guide_drift<0.001,"guide starts in phase and remains aligned after pause; maximum raw drift %.6fs"%maximum_guide_drift)
	check(not independent_voice,"early response never doubles an independent sample")
	report("MASTER_WITH_GUIDE peak=%.6f clipped_frames=%d captured_frames=%d max_response_drift=%.6f max_guide_drift=%.6f"%[maximum_peak,clipped_frames,mixed.size(),maximum_drift,maximum_guide_drift])
	check(maximum_peak>0.1 and maximum_peak<1 and clipped_frames==0,"actual complete master mix with guide, music, response and 3D impact does not clip")
	game.stop()
	check(not game.beat_guide.playing,"formal stop also stops the guide")
	var start := onset(bed_samples)
	var rate := AudioServer.get_mix_rate()
	check(start>=0,"actual bed signal captured")
	if start>=0:
		for target in [0.0,0.5,1.0,1.5,2.0,3.5,18.0,19.5,20.0]:
			var first := maxi(0,int(start+(target-0.04)*rate))
			var last_sample := int(start+(target+0.16)*rate)
			var guide_onset := onset(guide_samples,first,last_sample)
			if guide_onset<0:
				check(false,"guide cue %.3f actually captured"%target)
			else:
				var actual_time := (guide_onset-start)/rate
				report("GUIDE_CAPTURE time=%.3f bed_frame=%d guide_frame=%d relative=%.9f error_ms=%.3f"%[target,start,guide_onset,actual_time,(actual_time-target)*1000])
				check(absf(actual_time-target)<0.003,"guide cue %.3f aligns with bed within 3ms"%target)
		for i in range(selected_times.size()):
			var target := float(selected_times[i])
			var sample := onset(stems[indices[i]%2],int(start+(target-0.12)*rate),int(start+(target+0.12)*rate))
			if sample<0:
				check(false,"response %.3f audible"%target)
			else:
				var relative := (sample-start)/rate
				report("CAPTURE cue_index=%d time=%.3f bed_frame=%d response_frame=%d relative=%.9f error_ms=%.3f"%[indices[i],target,start,sample,relative,(relative-target)*1000])
				check(absf(relative-target)<0.003,"response %.3f aligns with bed within 3ms"%target)
		for target in [2.0,2.5,3.0,4.0,4.5,9.75,17.75,18.0,18.5]:
			var index := -1
			for i in range(chart.size()):
				if absf(float(chart[i].time)-target)<0.00001: index = i
			var sample := onset(stems[index%2],int(start+(target-0.04)*rate),int(start+(target+0.225)*rate))
			check(sample<0,"unarmed cue %.3f leaks no response melody"%target)
		# Actual captured break audio, before the later pause. Compare low-band
		# kick onset against the quiet middle of that same quarter note.
		var low := PackedFloat32Array()
		low.resize(bed_samples.size())
		var filter := 0.0
		var coefficient := 1-exp(-TAU*220/rate)
		for i in range(bed_samples.size()):
			filter += coefficient*(float(bed_samples[i].x)-filter)
			low[i] = filter
		var minimum := INF
		var sum := 0.0
		for step in range(5):
			var time := 18.0+step*0.5
			var pulse := raw_rms(low,int(start+(time+0.007)*rate),int(0.068*rate))
			var quiet := raw_rms(low,int(start+(time+0.17)*rate),int(0.055*rate))
			var ratio := pulse/maxf(0.00001,quiet)
			minimum = minf(minimum,ratio)
			sum += ratio
			report("BREAK beat_time=%.3f kick_lowband_rms=%.6f between_rms=%.6f ratio=%.3f"%[time,pulse,quiet,ratio])
		check(minimum>1.7,"actual break retains clear quarter-note kick pulse; minimum RMS ratio %.3f"%minimum)
	for capture in [master_capture,bed_capture,even_capture,odd_capture,guide_capture]: check(capture.get_discarded_frames()==0,"audio capture discarded no frames")
	host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	report("RESULT: %d checks, %d failures"%[checks,failures])
	var file := FileAccess.open("res://artifacts/wreck3d-audio-results.txt",FileAccess.WRITE)
	file.store_string("\n".join(lines)+"\n")
	file.close()
	quit(1 if failures else 0)
