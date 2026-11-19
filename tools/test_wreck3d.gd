extends SceneTree

var host
var wreck
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)

func prop(kind: String,variant := 0) -> Dictionary:
	for item in wreck.objects:
		if item.kind==kind and item.variant==variant: return item
	return {}

func at(seconds: float) -> void:
	wreck.elapsed = seconds
	wreck.update(0.0)

func tap(id: int,seconds: float) -> void:
	at(seconds)
	wreck.target_id = id
	wreck.press()
	wreck.release()

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
	wreck.music.stop()
	var shop_id: int = wreck.stage.get_instance_id()
	check(wreck.view.own_world_3d and wreck.camera.current,"one 3D shop with active camera")
	var television := prop("television")
	check(wreck.attack_style(television.id)=="tap","small items use a single tap")
	wreck.target_id = television.id
	at(1.80)
	var far: Vector3 = wreck.indicator.get_child(0).position
	at(2.00)
	var close: Vector3 = wreck.indicator.get_child(0).position
	check(far.distance_to(close)>0.2 and wreck.target_light.light_energy>1.5,"scene cues converge and flash on the beat")
	tap(television.id,2.18)
	check(wreck.resolved==0 and is_equal_approx(television.hp,3.0),"off-beat tap still hits but takes less damage")
	tap(television.id,2.5)
	check(wreck.resolved==1 and not television.alive and wreck.broken==1,"timed tap breaks the target and counts")
	var body: RigidBody3D = wreck.physical[0].body
	check(body.get_child(0) is MeshInstance3D and body.get_child(1) is CollisionShape3D,"destruction still creates physical fragments")

	var arcade := prop("arcade")
	var neighbor := prop("arcade",1)
	tap(arcade.id,3.0)
	check(arcade.alive and wreck.double_target==arcade.id and wreck.cue_time(arcade.id)==3.25,"first arcade hit cues the eighth-note offbeat")
	tap(arcade.id,3.1)
	check(wreck.double_target==arcade.id and wreck.double_hits==0 and wreck.resolved==2,"extra presses on the same pulse cannot score it again")
	tap(arcade.id,3.25)
	check(not arcade.alive and wreck.double_hits==1 and wreck.resolved==3,"second tap on the offbeat finishes a double")
	check(wreck.chain_hits==1 and neighbor.hp<neighbor.maxhp,"arcade still chains into its neighbor")

	var safe := prop("safe")
	wreck.target_id = safe.id
	at(3.46)
	wreck.press()
	check(wreck.charging and safe.hp==safe.maxhp,"press on a hard prop winds up the hammer")
	at(4.0)
	check(wreck.charge_level()>0.45,"hold grows the charge")
	wreck.release()
	check(wreck.timed_heavies==1 and wreck.heavy_hits==1 and safe.hp<safe.maxhp,"release on the beat lands a timed heavy")
	at(4.2)
	wreck.press()
	at(4.68)
	var before: float = safe.hp
	wreck.release()
	check(wreck.timed_heavies==1 and wreck.heavy_hits==2 and before-safe.hp<10.0,"off-beat release lands a lighter heavy")
	check(wreck.crates_revealed==1 and wreck.objects.back().title=="现金盒","safe can still reveal a cash box")

	for variant in range(3):
		var actor := prop("dummy",variant)
		var downbeat := 5.0+2.0*variant
		tap(actor.id,downbeat)
		wreck.update(0.08)
		var side: float = actor.slap_side
		check(wreck.palm.visible and not wreck.hammer.visible and wreck.state().nameTag==actor.title,"NPC %d keeps its name on the first hit" % variant)
		tap(actor.id,downbeat+0.25)
		wreck.update(0.10)
		var head: Node3D = actor.visual.get_node("Head")
		var reaction: bool = [
			absf(actor.visual.rotation.y)>0.2,
			actor.visual.position.y>actor.pos.y+0.1,
			absf(head.rotation.y)>0.1
		][variant]
		check(reaction and actor.slap_side==-side and wreck.state().nameTag==actor.title,"NPC %d has its own double-slap reaction and retains its name" % variant)
		wreck.target_id = safe.id
		check(wreck.state().nameTag==actor.title,"NPC %d keeps name when retargeting mid-reaction" % variant)
		wreck.update(0.8)
		check(actor.alive and is_zero_approx(head.rotation.z) and not wreck.palm.visible,"NPC %d resets so another combo is possible" % variant)

	var vending := prop("vending")
	tap(vending.id,11.0)
	at(11.4)
	check(wreck.double_target==-1,"missed second cue expires without blocking other attacks")
	at(12.6)
	check(wreck.streak==0,"streak expires after a short rest")
	tap(vending.id,13.0)
	tap(vending.id,13.25)
	check(not vending.alive and wreck.impact_label=="汽水喷泉！","timed vending-machine combo still scatters cans")
	tap(prop("dummy").id,13.5)
	wreck.pause_game()
	var frozen_time: float = wreck.elapsed
	var position := body.position
	await physics_frame
	await physics_frame
	wreck.update(1.0)
	check(body.freeze and body.position.is_equal_approx(position) and wreck.elapsed==frozen_time and wreck.double_target==-1,"pause freezes physics and clears the half-finished combo")
	wreck.resume_game()
	check(not body.freeze,"resume releases fragments")
	at(63.0)
	check(host.screen=="combat_play" and wreck.stage.get_instance_id()==shop_id,"there is no timed cutoff or scene switch")

	var expected_cash: int = wreck.cash
	for coin in wreck.loot: expected_cash += int(coin.value)
	wreck.action("combat_finish")
	check(host.screen=="combat_result" and wreck.won and wreck.cash==expected_cash and wreck.loot.is_empty(),"manual finish settles flying loot")
	wreck.start()
	check(wreck.stage.get_instance_id()!=shop_id and wreck.broken==0 and wreck.slaps==0 and wreck.resolved==0 and wreck.double_hits==0,"restart clears shop and rhythm counters")

	wreck.music.stop()
	at(10.0)
	var first_relay: int = wreck.show_target
	tap(first_relay,10.0)
	var second_relay: int = wreck.show_target
	check(second_relay!=first_relay and wreck.target_id==second_relay and wreck.show_due==10.5,"funk phrase hands focus to a second prop on the next beat")
	at(10.5)
	wreck.pointer_down(wreck.action_hint_rect(second_relay).get_center(),"touch_1")
	wreck.release("touch_1")
	check(wreck.specials==1 and wreck.show_step==0 and wreck.impact_label=="换位接上！","tapping the in-world prompt lands the relay special")
	at(12.5)
	check(wreck.show_target>=0 and wreck.show_count==1,"a second opportunity arrives within the same phrase")

	at(18.0)
	var performer: Dictionary = wreck.objects[wreck.show_target]
	tap(performer.id,18.0)
	tap(performer.id,18.25)
	at(18.6)
	check(wreck.show_step==1 and wreck.show_due==19.0 and performer.visual.position.y>0.75,"double slap launches the manager into a timed return")
	check(wreck.state().nameTag==performer.title,"moving character retains its name")
	wreck.target_id = prop("safe").id
	performer.slap = 0.0
	check(wreck.state().nameTag==performer.title,"name survives target changes throughout the return")
	tap(performer.id,19.0)
	check(wreck.specials==2 and wreck.impact_label=="回弹全中！","third slap connects when the character lands")
	at(21.0)
	check(wreck.objects[wreck.show_target].variant==1,"encore uses a different character")

	at(26.03)
	var delivery_id: int = wreck.show_target
	var crate: Dictionary = wreck.objects[delivery_id]
	check(crate.kind=="charge_crate" and wreck.cue_time(delivery_id)==26.0,"drop delivers a purple crate with accented cue")
	wreck.press()
	at(26.5)
	wreck.release()
	check(crate.alive and crate.hp<crate.maxhp and wreck.specials==2,"ordinary downbeat cannot consume the special crate")
	at(26.58)
	wreck.press()
	at(27.0)
	wreck.release()
	check(not crate.alive and wreck.specials==3 and wreck.blast_queue.size()==3,"accented heavy queues a three-step blast")
	var old_chain: int = wreck.chain_hits
	at(27.25)
	check(wreck.blast_queue.size()==2 and wreck.chain_hits==old_chain+1,"first shock hits on its halfbeat")
	at(27.75)
	check(wreck.blast_queue.is_empty() and wreck.chain_hits==old_chain+3,"later shocks reach distinct props")
	at(29.0)
	check(wreck.show_target==delivery_id and crate.alive and crate.hp==crate.maxhp,"delivery reuses the same slot and leaves old debris")

	at(34.0)
	tap(wreck.show_target,34.0)
	check(wreck.show_due==34.75,"melodic lift changes relay timing to the later offbeat")
	at(42.0)
	check(wreck.cue_time(wreck.show_target)==42.5,"final fill shifts the blast accent")
	for item in wreck.objects:
		if item.alive and wreck.attack_style(item.id)=="tap": item.alive = false
	at(58.0)
	var refill: int = wreck.show_target
	check(wreck.objects[refill].kind=="relay_crate","later loops deliver fallback targets after the shop is smashed")
	tap(refill,58.0)
	check(wreck.objects[wreck.show_target].kind=="relay_crate" and wreck.show_target!=refill,"fallback produces a distinct relay partner")

	wreck.stop()
	host.queue_free()
	wreck = null
	host = null
	body = null
	await process_frame
	await create_timer(0.35).timeout
	print("%d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
