extends SceneTree

var host
var wreck
var failures := 0
var lines: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	if not ok: failures += 1
	var line := ("PASS " if ok else "FAIL ")+label
	lines.append(line)
	print(line)

func prop(kind: String,variant := 0) -> Dictionary:
	for item in wreck.objects:
		if item.kind==kind and item.variant==variant: return item
	return {}

func tap(id: int) -> void:
	wreck.target_id = id
	wreck.press()
	wreck.release()
	wreck.update(0.12)

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains(".runtime/wreck3d-test-roaming"):
		push_error("Use the isolated wreck3d-test-roaming directory")
		quit(2)
		return
	host = load("res://main.tscn").instantiate()
	root.add_child(host)
	host.set_process(false)
	host.muted = true
	host.set_audio()
	wreck = host.combat
	wreck.start()
	var shop_id: int = wreck.stage.get_instance_id()
	check(wreck.view.own_world_3d and wreck.camera.current,"real 3D scene and camera")
	check(wreck.stage.find_children("*","MeshInstance3D",true,false).size()>200,"3D shop contains the dressed meshes")
	var television := prop("television")
	wreck.target_id = television.id
	wreck.press()
	check(wreck.elapsed==0.0 and wreck.total_smashes==1 and television.hp<television.maxhp,"first press hits immediately at time zero")
	wreck.update(0.17)
	wreck.release()
	check(wreck.heavy_hits==0 and television.alive,"short press only lands the first tap")
	var other_id: int = prop("vending").id
	wreck.target_id = television.id
	wreck.press()
	check(not television.alive and wreck.charging,"tap can destroy the held target")
	wreck.target_id = other_id
	var next_hp: float = wreck.objects[other_id].hp
	wreck.update(0.76)
	wreck.release()
	check(wreck.heavy_hits==1 and wreck.objects[other_id].hp==next_hp and wreck.hit3d==television.pos,"heavy release stays with destroyed target's rubble")
	check(wreck.broken==1 and not wreck.physical.is_empty(),"break creates physical fragments once")
	var body: RigidBody3D = wreck.physical[0].body
	check(body.get_child(0) is MeshInstance3D and body.get_child(1) is CollisionShape3D,"physical fragment has mesh and collision shape")

	wreck.pause_game()
	var previous_time: float = wreck.elapsed
	var previous_position := body.position
	await physics_frame
	await physics_frame
	wreck.update(1.0)
	check(body.freeze and body.position.is_equal_approx(previous_position) and wreck.elapsed==previous_time and wreck.music.stream_paused,"pause freezes physics, play time and audio")
	wreck.resume_game()
	check(not body.freeze and not wreck.music.stream_paused,"resume releases fragments and audio")
	wreck.update(61.0)
	check(host.screen=="combat_play" and wreck.stage.get_instance_id()==shop_id,"no timed end or room switch after a minute")

	for variant in range(3):
		var actor := prop("dummy",variant)
		wreck.target_id = actor.id
		wreck.press()
		wreck.update(0.14)
		var side: float = actor.slap_side
		check(wreck.palm.visible and not wreck.hammer.visible and wreck.state().nameTag==actor.title,"NPC %d retains its name during palm impact" % variant)
		wreck.update(0.22)
		var partial_power: float = wreck.charge_level()
		wreck.update(0.47)
		check(partial_power>0.0 and partial_power<wreck.charge_level(),"NPC %d charge ramps up" % variant)
		wreck.release()
		wreck.update(0.10)
		var head: Node3D = actor.visual.get_node("Head")
		var reaction: bool = [
			absf(actor.visual.rotation.y)>0.2,
			actor.visual.position.y>actor.pos.y+0.1,
			absf(head.rotation.y)>0.1
		][variant]
		check(reaction and actor.slap_side==-side,"NPC %d has its own charged reaction and reverses direction" % variant)
		wreck.target_id = television.id
		check(wreck.state().nameTag==actor.title,"NPC %d keeps the name when the target changes mid-reaction" % variant)
		wreck.update(0.8)
		check(actor.alive and is_zero_approx(head.rotation.z) and not wreck.palm.visible,"NPC %d resets and can be slapped again" % variant)
	check(wreck.slaps==6,"only actual slaps count")

	var vending := prop("vending")
	tap(vending.id)
	tap(vending.id)
	tap(vending.id)
	check(not vending.alive and wreck.impact_label=="汽水喷泉！","vending machine scatters its cans and shows its special reaction")
	var arcade := prop("arcade")
	var neighbor := prop("arcade",1)
	tap(arcade.id)
	tap(arcade.id)
	tap(arcade.id)
	check(not arcade.alive and neighbor.hp<neighbor.maxhp and wreck.chain_hits==1,"destroying an arcade cabinet bumps its nearest neighbor")
	var safe := prop("safe")
	wreck.target_id = safe.id
	wreck.press()
	wreck.update(0.8)
	wreck.release()
	check(safe.revealed and wreck.crates_revealed==1 and wreck.objects.back().title=="现金盒","strong hit on the safe reveals a breakable cash box")

	var expected_cash: int = wreck.cash
	for coin in wreck.loot: expected_cash += int(coin.value)
	wreck.action("combat_finish")
	check(host.screen=="combat_result" and wreck.won and wreck.cash==expected_cash and wreck.loot.is_empty(),"manual finish settles flying loot")
	wreck.finish(true)
	check(wreck.cash==expected_cash and not wreck.music.playing,"finish is idempotent and stops music")
	wreck.start()
	check(wreck.stage.get_instance_id()!=shop_id and wreck.broken==0 and wreck.slaps==0 and wreck.cash==0 and wreck.physical.is_empty(),"restart clears shop damage and counters")

	wreck.stop()
	host.queue_free()
	wreck = null
	host = null
	body = null
	await process_frame
	await create_timer(0.35).timeout
	print("%d checks, %d failures" % [lines.size(),failures])
	quit(0 if failures==0 else 1)
