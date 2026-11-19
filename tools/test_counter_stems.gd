extends SceneTree

var host
var lines: Array[String] = []
var checks := 0
var failures := 0
var bed_samples := PackedVector2Array()
var stem_samples: Array = [PackedVector2Array(),PackedVector2Array()]

func _initialize() -> void:
	call_deferred("run")

func report(message: String) -> void:
	lines.append(message)
	print(message)

func check(ok: bool,message: String) -> void:
	checks += 1
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

func onset(samples: PackedVector2Array,first := 0,last := -1) -> int:
	for i in range(first,samples.size() if last<0 else mini(last,samples.size())):
		if maxf(absf(samples[i].x),absf(samples[i].y))>0.0005: return i
	return -1

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/counter-audio-test-roaming"):
		push_error("Refusing normal save directory")
		quit(2)
		return
	report("COUNTER FORMAL INPUT + RESPONSE STEM MIXER CAPTURE / "+Engine.get_version_info().string)
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
	var counter = host.combat
	check(counter.get_script().resource_path=="res://scripts/rhythm_counter.gd","main actually uses rhythm_counter.gd")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	var chart: Array = counter.make_chart()
	check(chart.size()==64 and chart.size()==metadata.cues.size(),"64 global cue indices preserved")
	var consistent := 0
	var hold_count := 0
	var release_count := 0
	for i in range(chart.size()):
		var cue: Dictionary = chart[i]
		var original: Dictionary = metadata.cues[i]
		if absf(float(cue.time)-float(original.time))<0.000001 and absf(float(cue.beat)-float(original.beat))<0.000001 and cue.voice==original.action and (cue.voice=="dash" or int(cue.sample)==int(original.sample_index)) and i%2==int(original.stem_channel): consistent += 1
		if cue.type=="hold":
			hold_count += 1
			check(chart[i+1].type=="release" and chart[i+1].voice=="dash" and cue.voice=="shot","hold at beat %.1f retains melody head and clap release"%cue.beat)
		elif cue.type=="release": release_count += 1
	check(consistent==64,"all cue times, voices, note samples and stem channels match original PCM")
	check(hold_count==4 and release_count==4,"four hold/release pairs preserve all 64 cue slots")
	var bed_capture := capture_bus("CounterTestBed")
	var captures := [capture_bus("CounterTestEven"),capture_bus("CounterTestOdd")]
	counter.music.bus = "CounterTestBed"
	for i in range(2): counter.response_players[i].bus = "CounterTestEven" if i==0 else "CounterTestOdd"
	counter.start()
	counter.hp = 999
	var chosen_indices := [3,13,14]
	var chosen_times := [3.5,8.5,9.0]
	var accepted := [false,false,false]
	var duplicate_voice := false
	var pause_start := -1.0
	var pause_captured := false
	var resumed := false
	var pause_positions: Array[float] = []
	var pause_elapsed := 0.0
	var phase_drift := 0.0
	var beginning := Time.get_ticks_usec()
	var last := beginning
	report("mix_rate=%s output_latency=%s"%[AudioServer.get_mix_rate(),AudioServer.get_output_latency()])
	while (Time.get_ticks_usec()-beginning)/1000000.0<12.0:
		await process_frame
		var tick := Time.get_ticks_usec()
		counter.update((tick-last)/1000000.0)
		last = tick
		for i in range(3):
			if not accepted[i] and counter.now()>=float(chosen_times[i])-0.145:
				accepted[i] = true
				if i==2: counter.release("audio_test")
				else:
					counter.press("audio_test")
					if i==0: counter.release("audio_test")
				var cue: Dictionary = counter.cues[chosen_indices[i]]
				report("INPUT index=%d type=%s cue=%.3f heard=%.6f raw=%.6f channel=%d gate_db=%.1f"%[chosen_indices[i],cue.type,cue.time,counter.now(),counter.music.get_playback_position(),chosen_indices[i]%2,counter.response_players[chosen_indices[i]%2].volume_db])
				check(int(cue.status)==1 and cue.sound,"formal %s input queues and opens its response gate"%cue.type)
				if i==1: check(counter.holding==13 and counter.active_input=="audio_test","hold keeps input active until its tail")
				if i==2: check(counter.holding<0 and counter.active_input.is_empty(),"release consumes the held tail and clears held input")
		for player in counter.melody_players:
			if player.playing: duplicate_voice = true
		if counter.sounds.dash.playing: duplicate_voice = true
		var raw: float = counter.music.get_playback_position()
		for player in counter.response_players: phase_drift = maxf(phase_drift,absf(raw-player.get_playback_position()))
		var wall := (tick-beginning)/1000000.0
		if pause_start<0 and counter.now()>=9.6:
			counter.pause_game()
			pause_start = wall
			pause_elapsed = counter.elapsed
		elif pause_start>=0 and not pause_captured and wall-pause_start>0.15:
			pause_captured = true
			pause_positions = [counter.music.get_playback_position(),counter.response_players[0].get_playback_position(),counter.response_players[1].get_playback_position()]
		elif pause_start>=0 and not resumed and wall-pause_start>0.4:
			var change := maxf(absf(pause_positions[0]-counter.music.get_playback_position()),maxf(absf(pause_positions[1]-counter.response_players[0].get_playback_position()),absf(pause_positions[2]-counter.response_players[1].get_playback_position())))
			check(counter.elapsed==pause_elapsed and change<0.001,"pause freezes elapsed and all three formal audio streams")
			counter.resume_game()
			resumed = true
		bed_samples.append_array(bed_capture.get_buffer(bed_capture.get_frames_available()))
		for i in range(2): stem_samples[i].append_array(captures[i].get_buffer(captures[i].get_frames_available()))
	check(not duplicate_voice,"accepted tap/hold/release never double-play an independent note or dash")
	check(counter.heavy_hits==1,"held tail resolves exactly one heavy hit")
	for index in chosen_indices: check(int(counter.cues[index].status)==2,"accepted cue %d executes once"%index)
	check(counter.response_players[0].volume_db==-80 and counter.response_players[1].volume_db==-80,"formal gates close after accepted note tails")
	check(resumed and phase_drift<0.001,"pause/resume retains stem/bed phase; max raw drift %.6fs"%phase_drift)
	counter.stop()
	var rate := AudioServer.get_mix_rate()
	var bed_onset := onset(bed_samples)
	var errors: Array[float] = []
	check(bed_onset>=0,"actual bed audio captured")
	if bed_onset>=0:
		for i in range(3):
			var target := float(chosen_times[i])
			var first := int(bed_onset+(target-0.12)*rate)
			var last_sample := int(bed_onset+(target+0.12)*rate)
			var sample := onset(stem_samples[chosen_indices[i]%2],first,last_sample)
			if sample<0:
				check(false,"cue %.3f actually audible"%target)
				continue
			var relative := (sample-bed_onset)/rate
			var error := (relative-target)*1000
			errors.append(absf(error))
			report("CAPTURE index=%d type=%s bed_frame=%d response_frame=%d relative=%.9fs target=%.3fs error=%.3fms"%[chosen_indices[i],chart[chosen_indices[i]].type,bed_onset,sample,relative,target,error])
			check(absf(error)<3,"formal %s sample aligns within 3ms"%chart[chosen_indices[i]].type)
		for time in [2.0,2.5,3.0,4.0,5.0,8.0]:
			var index := int(round((time-2.0)/0.5))
			var first := int(bed_onset+(time-0.04)*rate)
			var last_sample := int(bed_onset+(time+0.23)*rate)
			check(onset(stem_samples[index%2],first,last_sample)<0,"missed cue %.3f never leaks from the response track"%time)
	for capture in captures: check(capture.get_discarded_frames()==0,"response capture discarded no frames")
	check(bed_capture.get_discarded_frames()==0,"bed capture discarded no frames")
	if errors.size()==3: report("MEAN_ABSOLUTE_CAPTURE_ERROR_MS %.3f"%(errors.reduce(func(a,b): return a+b,0.0)/3))
	host.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	report("RESULT: %d checks, %d failures"%[checks,failures])
	var file := FileAccess.open("res://artifacts/counter-audio-results.txt",FileAccess.WRITE)
	file.store_string("\n".join(lines)+"\n")
	file.close()
	quit(1 if failures else 0)
