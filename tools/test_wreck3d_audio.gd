extends SceneTree

var host
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/wreck3d-audio-test-roaming"):
		push_error("Use the isolated wreck3d-audio-test-roaming directory")
		quit(2)
		return
	host = load("res://main.tscn").instantiate()
	root.add_child(host)
	host.muted = false
	host.set_audio()
	var wreck = host.combat
	wreck.start()
	var stream: AudioStreamWAV = wreck.music.stream
	check(stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_begin==stream.mix_rate*2 and stream.loop_end==stream.mix_rate*50,"mixed track loops from the first playable bar")
	var legacy_tracks: Array = wreck.response_players+wreck.melody_players
	check(legacy_tracks.all(func(player): return not player.playing),"legacy tracks stay silent")
	var target: Dictionary = wreck.objects[wreck.target_id]
	wreck.press()
	wreck.release()
	check(wreck.demo_sounds[target.material].playing,"material sound plays on immediate hit")
	for item in wreck.objects:
		if item.kind=="dummy":
			wreck.target_id = item.id
			break
	await create_timer(0.14).timeout
	wreck.press()
	wreck.release()
	check(wreck.demo_sounds.slap.playing,"slap plays its own sound")
	var before_seek: float = wreck.elapsed
	wreck.music.seek(stream.get_length()-0.12)
	await create_timer(0.35).timeout
	check(wreck.music.playing and wreck.music.get_playback_position()<3.0 and wreck.elapsed>before_seek and wreck.rhythm_time>=50.0,"audio loop preserves the continuous beat clock")
	wreck.press()
	wreck.release()
	wreck.pause_game()
	check(wreck.music.stream_paused and wreck.demo_sounds.slap.stream_paused,"pause applies to music and sound effects")
	wreck.resume_game()
	check(not wreck.music.stream_paused and not wreck.demo_sounds.slap.stream_paused,"resume applies to music and sound effects")
	wreck.finish(true)
	check(not wreck.music.playing and not wreck.demo_sounds.slap.playing,"leaving the session stops music and effects")
	legacy_tracks.clear()
	wreck = null
	host.queue_free()
	host = null
	await process_frame
	await create_timer(0.35).timeout
	quit(0 if failures==0 else 1)
