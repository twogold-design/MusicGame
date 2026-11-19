extends SceneTree

var game
var wreck
var checks := 0
var failures := 0
var output: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	var line := ("PASS " if ok else "FAIL ")+label
	output.append(line)
	print(line)

func reset() -> void:
	game.easy = true
	game.offset_ms = 0
	game.muted = true
	game.set_audio()
	wreck.start()
	wreck.music.stop()
	game.set_process(false)

func prop(kind: String) -> int:
	for item in wreck.objects:
		if item.kind == kind: return int(item.id)
	return -1

func frame(at: float,delta := 0.0) -> void:
	wreck.elapsed = at
	wreck.update(delta)

func tap(at: float) -> void:
	wreck.elapsed = at
	wreck.press("test")
	wreck.release("test")

func run() -> void:
	output.append("MEOW BEAT true3D / actual main.tscn and rhythm_wreck3d.gd")
	output.append("Godot "+Engine.get_version_info().string)
	output.append("Isolated saves: "+OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/wreck3d-test-roaming"):
		push_error("Refusing non-isolated saves")
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	game.set_process(false)
	root.add_child(game)
	game.set_process(false)
	game.records = {}
	wreck = game.combat
	reset()
	await process_frame
	check(wreck.view is SubViewport and wreck.view.own_world_3d and wreck.stage is Node3D and wreck.camera is Camera3D and wreck.camera.current,"real private3D viewport contains stage and active camera")
	check(wreck.stage.find_children("*","MeshInstance3D",true,false).size() > 100 and wreck.stage.find_children("*","StaticBody3D",true,false).size() > 20,"shop consists of real meshes and solid3D collision bodies")
	check(wreck.avatar is Node3D and wreck.hammer is Node3D and wreck.indicator is MeshInstance3D,"avatar, hammer and target indicator are actual3D nodes")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/wreck3d/metadata.json"))
	check(wreck.music.stream.resource_path == "res://assets/audio/wreck3d/bed.wav" and absf(wreck.music.stream.get_length()-52.0) < 0.001,"start preserves new52-second backing rather than old34-second track")
	check(wreck.cues.size() == 102 and meta.cue_count == 102 and meta.combat_end == 50,"48-second mode has102 cues and ends at50s")
	check(wreck.beat_guide is AudioStreamPlayer and wreck.beat_guide.playing and absf(wreck.beat_guide.stream.get_length()-52.0) < 0.001,"new52-second beat-guide voice starts with the round")
	var near: Dictionary = wreck.beat_ring(1.95)
	var exact: Dictionary = wreck.beat_ring(2.0)
	var reopen: Dictionary = wreck.beat_ring(2.15)
	var approaching: Dictionary = wreck.beat_ring(2.40)
	check(not near.flash and float(near.radius) > wreck.TARGET_RING and float(near.radius) < wreck.TARGET_RING+6,"ring1.95s approaches fixed inner ring before downbeat")
	check(exact.flash and is_equal_approx(float(exact.radius),wreck.TARGET_RING),"ring2.00s exactly coincides and flashes on downbeat")
	check(not reopen.flash and not approaching.flash and float(reopen.radius) > float(approaching.radius) and float(approaching.radius) > float(near.radius),"ring2.15s reopens then shrinks consistently through2.40s toward next beat")
	game.offset_ms = 100
	var shifted: Dictionary = wreck.beat_ring(2.10)
	check(shifted.flash and is_equal_approx(float(shifted.radius),wreck.TARGET_RING),"positive100ms calibration shifts visual coincidence to2.10s")
	game.offset_ms = 0
	for i in range(wreck.cues.size()):
		var cue: Dictionary = wreck.cues[i]
		var m: Dictionary = meta.cues[i]
		check(is_equal_approx(float(cue.time),float(m.time)) and is_equal_approx(float(cue.beat),float(m.beat)) and cue.voice == m.voice and int(cue.sample) == int(m.sample_index) and cue.type == "tap","cue%03d matches extended audio metadata time/voice/sample" % i)
	var identity: int = wreck.stage.get_instance_id()
	for at in [2.0,12.0,22.0,34.0,49.9]:
		frame(at)
		check(wreck.stage.get_instance_id() == identity and wreck.shop_identity == identity and wreck.room == 0,"one unchanged shop identity at%.1fs; no timed room switch" % at)
	check(game.screen == "combat_play","scene remains playable past old32-second endpoint")

	reset()
	var monitor := prop("monitor")
	var initial_parts: int = wreck.meshes_below(wreck.objects[monitor].visual).size()
	var health: float = wreck.objects[monitor].hp
	wreck.hit3d = wreck.objects[monitor].pos
	wreck.damage_object(monitor,0.65,false)
	check(is_equal_approx(float(wreck.objects[monitor].hp),health-0.65) and wreck.objects[monitor].alive and wreck.physical.size() == 1 and wreck.meshes_below(wreck.objects[monitor].visual).size() == initial_parts-1,"nonlethal furniture damage detaches one actual mesh while reducingHP")
	var body: RigidBody3D = wreck.physical[0].body
	check(body is RigidBody3D and body.get_child(0) is MeshInstance3D and body.get_child(1) is CollisionShape3D and body.collision_mask == 1,"detached furniture fragment has real rigid body, mesh and collision shape")
	var before_death: int = wreck.physical.size()
	wreck.damage_object(monitor,100,true)
	check(not wreck.objects[monitor].alive and wreck.meshes_below(wreck.objects[monitor].visual).is_empty() and wreck.physical.size() > before_death and wreck.broken == 1,"lethal furniture damage physically detaches remaining parts exactly once")
	var after_death: int = wreck.physical.size()
	var death_score: int = wreck.score
	wreck.damage_object(monitor,100,true)
	check(wreck.physical.size() == after_death and wreck.broken == 1 and wreck.score == death_score,"repeated damage to dead furniture cannot duplicate parts or score")
	await physics_frame
	await physics_frame
	body.position = Vector3(0,4,6.5)
	body.rotation = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false
	for i in range(30): await physics_frame
	check(body.position.y < 3.7,"real physics steps make detached fragment fall under gravity")
	wreck.pause_game()
	check(wreck.beat_guide.stream_paused,"pause freezes guide audio together with physical world")
	await physics_frame
	await physics_frame
	var frozen_position: Vector3 = body.position
	var frozen_elapsed: float = wreck.elapsed
	for i in range(12): await physics_frame
	wreck.update(0.5)
	check(body.freeze and body.position.distance_to(frozen_position) < 0.0001 and wreck.elapsed == frozen_elapsed,"pause freezes actual rigid-body position and gameplay clock across physics frames")
	wreck.resume_game()
	check(not wreck.beat_guide.stream_paused,"resume restores guide audio playback state")
	check(not body.freeze,"resume restores fragment dynamic physics")
	for i in range(180): await physics_frame
	check(is_instance_valid(body) and body.position.y > -0.05 and body.position.y < 1.5 and body.linear_velocity.length() < 0.5,"physical fragment lands on solid floor and persists")

	reset()
	var safe := prop("safe")
	var base_count: int = wreck.objects.size()
	wreck.damage_object(safe,float(wreck.objects[safe].maxhp)*0.5,true)
	check(wreck.crates_revealed == 1 and wreck.objects.size() == base_count+1 and wreck.objects[safe].revealed and wreck.objects[-1].title == "现金盒","half-damaged safe reveals one real new cash-box prop")
	wreck.damage_object(safe,0.1,false)
	check(wreck.crates_revealed == 1 and wreck.objects.size() == base_count+1,"repeated damage cannot repeatedly reveal same safe contents")
	var cash_box: int = wreck.objects.size()-1
	wreck.damage_object(cash_box,2.3,false)
	check(wreck.crates_revealed == 1 and wreck.objects.size() == base_count+1,"revealed cash box cannot recursively generate another cash box")
	wreck.damage_object(cash_box,100,true)
	var pending_value := 0
	for coin in wreck.loot: pending_value += int(coin.value)
	for i in range(60): frame(3.0,0.05)
	check(wreck.cash == pending_value and wreck.loot.is_empty() and wreck.looted > 0,"loot from revealing and breaking cash box automatically reaches player with exact total value")
	var collected: int = wreck.cash
	var looted_count: int = wreck.looted
	for i in range(20): frame(3.0,0.05)
	check(wreck.cash == collected and wreck.looted == looted_count,"collected coins cannot award money twice")
	wreck.spawn_loot(Vector3(1,1,1),101)
	var split_total := 0
	for coin in wreck.loot: split_total += int(coin.value)
	check(split_total == 101,"uneven-value coin split preserves101 currency exactly")

	reset()
	var dummy := prop("dummy")
	wreck.target_id = dummy
	var head: Node3D = wreck.objects[dummy].visual.get_node("Head")
	var dummy_hp: float = wreck.objects[dummy].hp
	tap(2.25)
	frame(2.25,0)
	check(wreck.slaps == 1 and wreck.objects[dummy].hp < dummy_hp and wreck.slap_flash > 0 and wreck.palm.visible,"same tap automatically becomes one visible palm slap against selected dummy")
	check(absf(head.rotation.z) > 0.1 and not wreck.hammer.visible,"dummy Head joint visibly rotates and hammer hides during slap")
	tap(2.75)
	check(wreck.slaps == 2,"next single-key hit increments slap count once")
	frame(3.0,0.4)
	check(is_zero_approx(head.rotation.z) and not wreck.palm.visible,"dummy head and palm recover after slap animation")

	reset()
	tap(1.90)
	check(wreck.cues[0].status == 1 and wreck.resolved == 0 and wreck.guide_label == "准备好了" and wreck.guide_label_time > 0,"early buffered tap displays preparation rather than failure feedback")
	frame(2.0)
	check(wreck.cues[0].status == 2 and wreck.guide_label == "准拍！" and wreck.resolved == 1,"buffered action changes to successful beat feedback when its beat arrives")
	reset()
	tap(2.18)
	check(wreck.weak_hits == 1 and wreck.total_smashes == 1 and wreck.guide_label == "晚了一点" and wreck.guide_label_time > 0,"late offbeat tap still weak-smashes and explicitly reports late timing")
	reset()
	tap(2.32)
	check(wreck.weak_hits == 1 and wreck.total_smashes == 1 and wreck.guide_label == "早了一点" and wreck.guide_label_time > 0,"early offbeat tap still weak-smashes and explicitly reports early timing")
	reset()
	for cue in wreck.cues:
		if float(cue.beat) < 15.0: cue.status = 2
	tap(9.50)
	frame(9.901)
	check(wreck.streak == 1 and wreck.missed == 0,"skipping optional15.5-beat accent preserves regular-beat streak and miss count")
	tap(10.0)
	check(wreck.streak == 2 and wreck.resolved == 2,"next regular downbeat continues streak after omitted optional halfbeat")

	reset()
	wreck.spawn_loot(Vector3(0,1,0),71)
	wreck.finish(true)
	check(wreck.cash == 71 and wreck.loot.is_empty(),"finish settles outstanding automatic pickup rewards")
	var settled_cash: int = wreck.cash
	wreck.finish(true)
	check(wreck.cash == settled_cash,"repeated finish cannot double-settle coins")
	var previous_stage: int = wreck.stage.get_instance_id()
	reset()
	await process_frame
	check(wreck.stage.get_instance_id() != previous_stage and wreck.cash == 0 and wreck.slaps == 0 and wreck.crates_revealed == 0 and wreck.physical.is_empty() and wreck.loot.is_empty() and wreck.broken == 0,"restart builds fresh shop and clears physical debris, coins and progress")
	var run_identity: int = wreck.stage.get_instance_id()
	for cue in wreck.cues:
		frame(float(cue.time))
		tap(float(cue.time))
		wreck.resolve_cues()
	frame(50.0)
	check(game.screen == "combat_result" and wreck.won and wreck.resolved == 102,"full102-tap48-second run reaches successful result")
	check(wreck.stage.get_instance_id() == run_identity and wreck.shop_identity == run_identity and wreck.room == 0,"full performance retains one continuous3D scene throughout")
	check(wreck.broken > 0 and wreck.physical.size() > 0 and wreck.cash > 0,"full performance creates physical destruction and automatic loot")
	var stopped: bool = not wreck.music.playing
	for audio in wreck.response_players+wreck.melody_players+wreck.sounds.values()+wreck.demo_sounds.values(): stopped = stopped and not audio.playing
	check(stopped,"final result stops all backing, response and effects audio")
	check(not wreck.beat_guide.playing,"final result also stops beat-guide voice")

	wreck.stop()
	game.queue_free()
	body = null
	head = null
	wreck = null
	game = null
	await process_frame
	await create_timer(0.35).timeout
	output.append("Cleanup: scene/references freed;350ms audio retirement delay.")
	var summary := "RESULT: %d checks, %d failures" % [checks,failures]
	output.append(summary)
	print(summary)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/wreck3d-mechanics.txt",FileAccess.WRITE)
	file.store_string("\n".join(output)+"\n")
	quit(0 if failures == 0 else 1)
