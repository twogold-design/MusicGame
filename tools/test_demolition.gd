extends SceneTree

var game
var demo
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

func reset() -> void:
	game.easy = true
	game.muted = true
	game.offset_ms = 0
	game.set_audio()
	demo.start()
	demo.music.stop()
	game.set_process(false)

func resolve(at: float) -> void:
	demo.elapsed = at
	demo.resolve_cues()

func frame(at: float,delta := 0.0) -> void:
	demo.elapsed = at
	demo.update(delta)

func tap(at: float,source := "test") -> void:
	demo.elapsed = at
	demo.press(source)
	demo.release(source)

func room_item(kind: String,which_room := 0) -> int:
	for item in demo.objects:
		if item.room == which_room and item.kind == kind: return int(item.id)
	return -1

func audio_stopped() -> bool:
	if demo.music.playing: return false
	for audio in demo.response_players+demo.melody_players+demo.sounds.values()+demo.demo_sounds.values():
		if audio.playing: return false
	return true

func run() -> void:
	output.append("MEOW BEAT demolition mechanics / actual main.tscn and rhythm_demolition.gd")
	output.append("Godot "+Engine.get_version_info().string)
	output.append("Isolated saves: "+OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/demolition-test-roaming"):
		push_error("Refusing non-isolated saves")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	demo = game.combat
	reset()
	check(demo.room == 0 and demo.target_id == 0 and demo.broken == 0 and demo.debris.is_empty(),"new round starts in intact living room with automatic target")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/groove/metadata.json"))
	var chart_ok: bool = demo.cues.size() == 64
	for i in range(demo.cues.size()):
		var cue: Dictionary = demo.cues[i]
		var m: Dictionary = meta.cues[i]
		chart_ok = chart_ok and cue.type == "tap" and cue.kind == "tap" and is_equal_approx(float(cue.time),float(m.time)) and cue.voice == m.action
	check(chart_ok,"all64 audio-aligned cues accept same tap; no mandatory hold/release pattern")
	var room_counts := [0,0,0]
	var wall_counts := [0,0,0]
	var object_ok := true
	for item in demo.objects:
		room_counts[int(item.room)] += 1
		if item.kind == "wall": wall_counts[int(item.room)] += 1
		else: object_ok = object_ok and demo.art.has(item.kind)
		object_ok = object_ok and item.hp > 0 and item.hp == item.maxhp and item.alive
	check(object_ok and wall_counts == [3,3,3] and room_counts == [10,11,10],"three rooms contain31 live textured furniture/wall objects with valid health")

	var sofa := room_item("sofa")
	var initial_hp: float = demo.objects[sofa].hp
	demo.damage_object(sofa,0.55,false)
	check(is_equal_approx(float(demo.objects[sofa].hp),initial_hp-0.55) and demo.objects[sofa].alive and demo.objects[sofa].flash == 1 and demo.debris.size() == 3,"weak hit changes real furnitureHP, exposes crack ratio and spawns3 chips")
	var cracks := int(ceil((1-float(demo.objects[sofa].hp)/float(demo.objects[sofa].maxhp))*5))
	check(cracks > 0,"damaged furniture has positive renderer crack count")
	demo.debris.clear()
	demo.impact_pos = demo.objects[sofa].rect.get_center()
	demo.damage_object(sofa,100,true)
	check(not demo.objects[sofa].alive and demo.objects[sofa].hp == 0 and demo.broken == 1 and demo.debris.size() == 16,"lethal hit replaces sofa with16 original-image fragments")
	var uv_total := 0.0
	var unique_regions: Array = []
	var uv_ok := true
	for piece in demo.debris:
		var uv: Rect2 = piece.uv
		uv_total += uv.get_area()
		uv_ok = uv_ok and uv.position.x >= 0 and uv.position.y >= 0 and uv.end.x <= 1 and uv.end.y <= 1 and not unique_regions.has(uv)
		uv_ok = uv_ok and piece.kind == "sofa" and piece.room == 0 and piece.size == demo.objects[sofa].rect.size/4
		unique_regions.append(uv)
	check(uv_ok and is_equal_approx(uv_total,1) and unique_regions.size() == 16,"fragmentUVs partition full original sofa texture into16 unique quarters-grid regions")
	var dead_score: int = demo.score
	demo.damage_object(sofa,100,true)
	check(demo.debris.size() == 16 and demo.broken == 1 and demo.score == dead_score,"dead object cannot break or score twice")
	for i in range(600): frame(3.0,1.0/60.0)
	var all_rest := true
	for piece in demo.debris: all_rest = all_rest and piece.rest and is_equal_approx(float(piece.pos.y),float(piece.ground))
	check(all_rest and demo.debris.size() == 16,"all16 debris fragments land and persist instead of fading away")
	var resting_positions: Array = []
	for piece in demo.debris: resting_positions.append(piece.pos)
	for i in range(60): frame(3.0,1.0/60.0)
	var stayed := true
	for i in range(demo.debris.size()): stayed = stayed and demo.debris[i].pos == resting_positions[i]
	check(stayed,"settled fragments remain stable on floor")

	reset()
	sofa = room_item("sofa")
	demo.target_id = sofa
	tap(2.25)
	check(is_equal_approx(float(demo.objects[sofa].hp),5.5-0.55) and demo.weak_hits == 1 and demo.total_smashes == 1,"offbeat input still immediately damages selected furniture by0.55")
	reset()
	sofa = room_item("sofa")
	demo.target_id = sofa
	tap(2.0)
	check(is_equal_approx(float(demo.objects[sofa].hp),5.5-2.4) and demo.resolved == 1,"on-beat tap immediately deals2.4 damage on same target")
	reset()
	sofa = room_item("sofa")
	demo.apply_smash(sofa,"heavy",false)
	check(is_equal_approx(float(demo.objects[sofa].hp),5.5-2.4) and demo.heavy_hits == 1,"offbeat heavy remains useful with2.4 damage")
	reset()
	sofa = room_item("sofa")
	demo.apply_smash(sofa,"heavy",true)
	check(not demo.objects[sofa].alive and demo.heavy_hits == 1,"on-beat heavy deals5.8 and destroys5.5HP sofa")

	reset()
	sofa = room_item("sofa")
	demo.target_id = sofa
	demo.elapsed = 2.25
	demo.press("test")
	check(demo.charging and demo.locked_target == sofa,"holding begins after initial tap and locks automatic target")
	demo.elapsed = 2.56
	demo.release("test")
	check(demo.heavy_hits == 1 and demo.total_smashes == 2 and not demo.charging and demo.locked_target == -1,"arbitrary310ms hold release adds heavy smash without fixed long-enemy cue")
	reset()
	sofa = room_item("sofa")
	demo.target_id = sofa
	demo.elapsed = 2.25
	demo.press()
	demo.elapsed = 2.52
	demo.release()
	check(demo.heavy_hits == 0 and demo.total_smashes == 1,"short270ms tap-release does not accidentally heavy smash")
	reset()
	demo.elapsed = 2.0
	demo.press()
	demo.release()
	check(demo.broken == 1 and demo.target_id != 0 and demo.objects[demo.target_id].alive,"single-key automatic target advances after furniture breaks")
	game.buttons.clear()
	sofa = room_item("sofa")
	demo.elapsed = 2.25
	demo.pointer_down(demo.objects[sofa].rect.get_center(),"mouse")
	demo.release("mouse")
	check(demo.target_id == sofa and demo.objects[sofa].hp < demo.objects[sofa].maxhp,"optional furniture click selects and strikes in one action")

	reset()
	sofa = room_item("sofa")
	var cabinet := room_item("cabinet")
	var cabinet_hp: float = demo.objects[cabinet].hp
	demo.streak = 4
	demo.apply_smash(sofa,"tap",true)
	check(demo.chain_hits > 0 and demo.objects[cabinet].hp < cabinet_hp and demo.shockwaves.size() == 1,"fourth rhythm hit damages actual neighboring furniture through chain shockwave")
	var wall := room_item("wall")
	demo.damage_object(wall,100,true)
	check(not demo.objects[wall].alive and demo.wall_breaks == 1 and demo.destruction() > 0,"destroyed wall records real hole state and contributes to destruction percentage")
	var old_debris: int = demo.debris.size()
	frame(11.999)
	check(demo.room == 0,"living room remains until just before12-second boundary")
	frame(12.0)
	check(demo.room == 1 and demo.transition == 1 and demo.objects[demo.target_id].room == 1,"12-second boundary moves to office with new automatic target")
	frame(21.999)
	check(demo.room == 1,"office remains until just before22-second boundary")
	frame(22.0)
	check(demo.room == 2 and demo.objects[demo.target_id].room == 2 and demo.debris.size() == old_debris,"22-second boundary moves to arcade while retaining previous-room debris")

	reset()
	var safe_hp: int = demo.hp
	resolve(20.0)
	check(demo.hp == safe_hp and demo.missed > 0 and game.screen == "combat_play","missing many rhythm cues cannot causeHP loss or failure")
	reset()
	for item in demo.objects:
		if item.room == 0: item.alive = false
	demo.debris.append({"pos":Vector2(720,650),"vel":Vector2.ZERO,"angle":0.0,"spin":0.0,"size":Vector2(20,20),"uv":Rect2(0,0,0.25,0.25),"kind":"sofa","room":0,"color":Color.WHITE,"ground":650.0,"rest":true})
	demo.apply_smash(-1,"heavy",true)
	frame(3.0,1.0/60.0)
	check(not demo.debris[0].rest and demo.debris[0].pos.y < 650,"smashing cleared-room rubble wakes settled debris and launches it again")

	reset()
	sofa = room_item("sofa")
	demo.damage_object(sofa,0.5,false)
	demo.music.play()
	for audio in demo.response_players+demo.melody_players+demo.sounds.values()+demo.demo_sounds.values(): audio.play()
	await process_frame
	demo.elapsed = 3.0
	demo.press("test")
	demo.pause_game()
	var frozen: Array = demo.debris.duplicate(true)
	var frozen_objects: Array = demo.objects.duplicate(true)
	demo.update(0.5)
	var paused_all: bool = demo.music.stream_paused
	for audio in demo.response_players+demo.melody_players+demo.sounds.values()+demo.demo_sounds.values(): paused_all = paused_all and audio.stream_paused
	check(demo.elapsed == 3.0 and demo.debris == frozen and demo.objects == frozen_objects and not demo.charging,"pause freezes room physics, furniture and time and cancels unfinished charge")
	check(paused_all,"pause freezes backing, responses, melody and material effects")
	demo.resume_game()
	var resumed_all: bool = not demo.music.stream_paused
	for audio in demo.response_players+demo.melody_players+demo.sounds.values()+demo.demo_sounds.values(): resumed_all = resumed_all and not audio.stream_paused
	check(resumed_all and game.screen == "combat_play","resume restores all audio streams")
	reset()
	check(demo.broken == 0 and demo.wall_breaks == 0 and demo.chain_hits == 0 and demo.heavy_hits == 0 and demo.debris.is_empty() and demo.shockwaves.is_empty() and not demo.charging and demo.room == 0,"restart restores intact rooms and clears debris, chains and heavy-charge state")
	reset()
	for cue in demo.cues:
		frame(float(cue.time))
		tap(float(cue.time))
		demo.resolve_cues()
	frame(32.0)
	check(game.screen == "combat_result" and demo.won and demo.resolved == 64,"full64-tap single-key performance completes all3 rooms and ends successfully")
	check(demo.broken > 0 and demo.chain_hits > 0 and demo.destruction() > 0 and demo.debris.size() > 0,"complete rhythm run produces real broken objects, chains and persistent debris")
	check(audio_stopped(),"result screen stops all material and music audio")
	var final_score: int = demo.score
	demo.finish(true)
	check(demo.score == final_score,"repeated finish cannot duplicate destruction score")

	demo.stop()
	game.queue_free()
	demo = null
	game = null
	await process_frame
	await create_timer(0.35).timeout
	output.append("Cleanup: freed scene/references and allowed350ms for audio mixer retirement.")
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/demolition-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
