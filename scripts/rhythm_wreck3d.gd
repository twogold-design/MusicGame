extends "res://scripts/rhythm_demolition.gd"

const PLAY_END := 50.0
const VIEW_RECT := Rect2(48,159,1344,590)
const RHYTHM_PANEL := Rect2(48,765,1344,115)
const TARGET_RING := 29.0
const PANEL_DARK := Color("302541")
const PEACH := Color("ffd3aa")
const MINT := Color("94fae0")
const CAMERA_ORBIT := Vector3(12.8,19.0,26.6)
const ShopDecor = preload("res://scripts/wreck3d_shop_decor.gd")
var view: SubViewport
var stage: Node3D
var camera: Camera3D
var avatar: Node3D
var hammer: Node3D
var indicator: MeshInstance3D
var physical: Array = []
var loot: Array = []
var waves3d: Array = []
var track: Dictionary = {}
var cash := 0
var slaps := 0
var looted := 0
var crates_revealed := 0
var base_camera := CAMERA_ORBIT
var hit3d := Vector3.ZERO
var impact_time := 0.0
var impact_strength := 0.0
var selected_visual := -1
var slap_flash := 0.0
var palm: MeshInstance3D
var shop_identity := 0
var beat_guide: AudioStreamPlayer
var guide_label := ""
var guide_color := GOLD
var guide_label_time := 0.0
var combat_backdrop := Color("29223d")
var meshes := preload("res://scripts/wreck3d_art.gd")

func _init(host) -> void:
	super(host)
	track = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/wreck3d/metadata.json"))
	music.stream = load("res://assets/audio/wreck3d/bed.wav")
	music.volume_db = -4
	for i in range(2): response_players[i].stream = load("res://assets/audio/wreck3d/response_%s.wav" % ("even" if i==0 else "odd"))
	for i in range(8): melody_players[i].stream = load("res://assets/audio/wreck3d/shot_%d.wav" % i)
	sounds.dash.stream = load("res://assets/audio/wreck3d/dash.wav")
	var clap := AudioStreamPlayer.new()
	clap.stream = load("res://assets/audio/demolition/slap.wav")
	clap.volume_db = -5
	clap.max_polyphony = 2
	h.add_child(clap)
	demo_sounds.slap = clap
	beat_guide = AudioStreamPlayer.new()
	beat_guide.stream = load("res://assets/audio/wreck3d/guide.wav")
	beat_guide.volume_db = -3
	h.add_child(beat_guide)
	view = SubViewport.new()
	view.size = Vector2i(VIEW_RECT.size)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	h.add_child(view)
	build_shop()

func make_chart() -> Array:
	var chart: Array = []
	for entry in track.cues:
		chart.append({"beat":float(entry.beat),"time":float(entry.time),"type":"tap","kind":"tap","target":-1,"status":0,"offset":0.0,"sound":false,"sample":int(entry.sample_index),"voice":str(entry.voice)})
	return chart

func build_room(_r: int) -> void:
	pass

func start() -> void:
	super.start()
	beat_guide.play()
	cash = 0
	slaps = 0
	looted = 0
	crates_revealed = 0
	guide_label = ""
	guide_label_time = 0
	impact_time = 0
	build_shop()
	shop_identity = stage.get_instance_id()
	target_id = pick_target()
	say("两圈重合时，按一下空格",GOLD,4)

func stop() -> void:
	super.stop()
	beat_guide.stop()
	beat_guide.stream_paused = false
	for entry in physical:
		if is_instance_valid(entry.body): entry.body.freeze = true

func mat(color: Color,glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.5
	return material

func box(parent: Node3D,pos: Vector3,size: Vector3,color: Color,glow := false) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	model.mesh = shape
	model.material_override = mat(color,glow)
	model.position = pos
	parent.add_child(model)
	return model

func collider(parent: Node3D,pos: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = size
	shape.shape = collision
	body.add_child(shape)
	parent.add_child(body)
	return body

func build_shop() -> void:
	if is_instance_valid(stage):
		view.remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	stage.name = "OneContinuousShop"
	view.add_child(stage)
	objects.clear()
	physical.clear()
	loot.clear()
	waves3d.clear()
	selected_visual = -1
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = combat_backdrop
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b8c9ee")
	settings.ambient_light_energy = 0.48
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-20,0)
	sun.light_color = Color("ffddb8")
	sun.light_energy = 0.52
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35,125,0)
	fill.light_color = Color("80b9ff")
	fill.light_energy = 0.24
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.position = CAMERA_ORBIT
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	frame_shop()
	camera.current = true
	ShopDecor.build(stage)
	collider(stage,Vector3(0,-0.3,0),Vector3(25,0.6,15))
	collider(stage,Vector3(0,1.5,-7.3),Vector3(25,3,0.35))
	collider(stage,Vector3(-12.3,1.5,0),Vector3(0.35,3,15))
	collider(stage,Vector3(12.5,1,0),Vector3(0.3,2,15))
	collider(stage,Vector3(0,1,7.5),Vector3(25,2,0.3))
	# All displays and characters coexist in this one cutaway shopping hall.
	for i in range(4):
		add_prop("arcade",Vector3(-9.7+i*2.1,0,-5.4),Vector3(1.65,2.7,1.2),8.5,"metal",60,"",i)
	add_prop("vending",Vector3(0.6,0,-5.3),Vector3(1.8,2.9,1.3),9.5,"glass",100)
	add_prop("safe",Vector3(5.1,0,-5.3),Vector3(2.2,2.7,1.8),36,"metal",650)
	add_prop("cabinet",Vector3(9.1,0,-5.1),Vector3(2,2.5,1.4),10,"wood",100)
	for i in range(3):
		add_prop("desk",Vector3(-8.8+i*3.8,0,-1.7),Vector3(2.6,1.2,1.4),7,"wood",30)
		add_prop("monitor",Vector3(-8.8+i*3.8,1.25,-1.7),Vector3(1.25,1.15,0.65),4,"glass",50)
	for i in range(3): add_prop("shelf",Vector3(4.2+i*2.7,0,-0.8),Vector3(2,2,1.05),11,"wood",130)
	add_prop("sofa",Vector3(-8,0,3.5),Vector3(3.5,1.6,1.6),11,"wood",50)
	add_prop("television",Vector3(-7.5,0,5.8),Vector3(2,1.6,0.7),5,"glass",70)
	add_prop("cabinet",Vector3(-3.8,0,3.5),Vector3(1.6,2,1.2),10,"wood",90)
	add_prop("desk",Vector3(0.2,0,4.5),Vector3(2.8,1.1,1.6),8,"wood",50)
	add_prop("television",Vector3(0.2,1.2,4.5),Vector3(1.7,1.35,0.6),4,"glass",60)
	for pos in [Vector3(-11,0,1),Vector3(11,0,4.8),Vector3(2,0,-4.6)]: add_prop("plant",pos,Vector3(1.1,1.8,1.1),3,"glass",20)
	add_prop("dummy",Vector3(5.2,0,3.5),Vector3(1.25,2.1,1.15),18,"slap",160,"催加班经理")
	add_prop("dummy",Vector3(8.6,0,4.7),Vector3(1.25,2.1,1.15),18,"slap",160,"插队大叔")
	add_prop("dummy",Vector3(-2.1,0,-5),Vector3(1.25,2.1,1.15),18,"slap",160,"开会达人")
	# Breakable architectural pieces expose a permanent hole in the facade.
	for x in [-8.0,0.0,8.0]: add_prop("wall",Vector3(x,0,-6.65),Vector3(2.6,2.8,0.3),18,"wood",40)
	avatar = meshes.create_hero()
	avatar.scale = Vector3.ONE*1.25
	stage.add_child(avatar)
	avatar.position = Vector3(-8,0,5)
	hammer = avatar.get_node_or_null("Hammer")
	indicator = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.73
	indicator.mesh = torus
	indicator.material_override = mat(GOLD,true)
	stage.add_child(indicator)
	palm = box(stage,Vector3.ZERO,Vector3(0.48,0.1,0.64),Color("f4d7aa"))
	palm.visible = false
	for i in range(4): box(palm,Vector3(-0.18+i*0.12,0,0.36),Vector3(0.085,0.09,0.25),Color("f4d7aa"))
	target_id = pick_target()

func frame_shop() -> void:
	camera.look_at(Vector3.ZERO)
	var right := camera.basis.x
	var up := camera.basis.y
	var bottom_left := Vector2(INF,INF)
	var top_right := Vector2(-INF,-INF)
	var corners := [
		Vector3(-12.8,-0.86,-7.8),Vector3(12.8,-0.86,-7.8),
		Vector3(-12.8,-0.86,7.8),Vector3(12.8,-0.86,7.8),
		Vector3(-12.5,3.32,-7.5),Vector3(12.5,3.32,-7.5),
		Vector3(-12.5,3.32,7.5),Vector3(-3.75,4.1,-7.0),
		Vector3(3.45,4.1,-7.0),
	]
	for point: Vector3 in corners:
		var projected := Vector2(point.dot(right),point.dot(up))
		bottom_left = bottom_left.min(projected)
		top_right = top_right.max(projected)
	var span := top_right-bottom_left
	var center := (bottom_left+top_right)*0.5
	var aspect := float(view.size.x)/view.size.y
	camera.size = maxf(span.y,span.x/aspect)*1.08
	base_camera = camera.position+right*center.x+up*center.y
	camera.position = base_camera

func add_prop(kind: String,pos: Vector3,size: Vector3,health: float,material: String,value: int,title := "",variant := 0) -> int:
	var visual: Node3D
	if kind=="wall":
		visual = Node3D.new()
		for x in range(3):
			for y in range(3):
				var tint := Color("3e5b71").lightened(0.035*(x+y))
				var center := Vector3((x-1)*size.x/3,(y+0.5)*size.y/3,0)
				var panel_size := Vector3(size.x/3-0.022,size.y/3-0.028,size.z)
				meshes.box(visual,"ShutterPanel",center,panel_size,mat(tint),0.032)
	else: visual = meshes.create_prop(kind,size,variant)
	visual.position = pos
	stage.add_child(visual)
	var solid := collider(stage,pos+Vector3(0,size.y*0.5,0),size*Vector3(0.9,1,0.9))
	objects.append({"id":objects.size(),"kind":kind,"pos":pos,"size":size,"hp":health,"maxhp":health,"material":material,"alive":true,"value":value,"visual":visual,"collider":solid,"flash":0.0,"title":title,"revealed":false,"slap":0.0,"origin":pos})
	return objects.size()-1

func pick_target() -> int:
	# Distance keeps the avatar in one coherent part of the same shop.
	var best := -1
	var cost := INF
	var from := avatar.position if is_instance_valid(avatar) else Vector3(-8,0,5)
	for item in objects:
		if not item.alive: continue
		var candidate: float = from.distance_to(item.pos)+(4 if item.kind=="wall" else 0)+(6 if item.kind=="safe" else 0)
		if candidate<cost:
			cost = candidate
			best = item.id
	return best

func valid_target(id: int) -> int:
	if id>=0 and id<objects.size() and objects[id].alive: return id
	return pick_target()

func strike(kind: String,id: int) -> void:
	var clock := now()
	if clock<INTRO-window_early() or clock>=PLAY_END: return
	var before := weak_hits
	var cue_index := closest_cue()
	super.strike(kind,id)
	if weak_hits==before: return
	var judged: float = clock-h.offset_ms/1000.0
	var offbeat := judged-roundf(judged/BEAT)*BEAT
	var label := "等下一拍"
	if cue_index<0: label = "早了一点" if offbeat<0 else "晚了一点"
	show_judgement(label,PEACH,0.5)

func accept(index: int) -> void:
	if now()<float(cues[index].time):
		show_judgement("准备好了",MINT,0.20)
	super.accept(index)

func execute_cue(index: int) -> void:
	if cues[index].status!=1: return
	var offset := float(cues[index].offset)
	var heavy: bool = cues[index].kind=="heavy"
	super.execute_cue(index)
	if offset>0.09:
		show_judgement("稍晚 · 接上了",PEACH,0.42)
	else:
		show_judgement("准拍 · 重砸！" if heavy else "准拍！",MINT,0.42)

func miss_cue(index: int,_early_release := false) -> void:
	var beat_number := float(cues[index].beat)
	if not is_equal_approx(beat_number,roundf(beat_number)):
		cues[index].status = 3
		return
	super.miss_cue(index)

func show_judgement(label: String,color: Color,seconds: float) -> void:
	guide_label = label
	guide_color = color
	guide_label_time = seconds

func project_to_screen(pos: Vector3) -> Vector2:
	return VIEW_RECT.position+camera.unproject_position(pos)/Vector2(view.size)*VIEW_RECT.size

func beat_ring(clock: float) -> Dictionary:
	var judged: float = clock-h.offset_ms/1000.0
	var since := fposmod(judged,BEAT)
	var flash := since<0.09
	var radius := TARGET_RING
	if not flash:
		radius += 47.0*(BEAT-since)/(BEAT-0.09)
	return {"radius":radius,"flash":flash}

func meshes_below(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is MeshInstance3D and child.visible: found.append(child)
		found.append_array(meshes_below(child))
	return found

func launch_piece(part: MeshInstance3D,force: float) -> void:
	if not is_instance_valid(part) or not part.visible: return
	var transform := part.global_transform
	var bounds := part.get_aabb()
	var scale3 := transform.basis.get_scale().abs()
	var body := RigidBody3D.new()
	body.mass = clampf(bounds.size.x*bounds.size.y*bounds.size.z*scale3.x*scale3.y*scale3.z,0.15,3)
	body.linear_damp = 0.22
	body.angular_damp = 0.45
	body.collision_layer = 2
	body.collision_mask = 1
	var physics := PhysicsMaterial.new()
	physics.bounce = 0.28
	physics.friction = 0.75
	body.physics_material_override = physics
	var model := MeshInstance3D.new()
	model.mesh = part.mesh
	model.material_override = part.material_override
	model.scale = scale3
	body.add_child(model)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = (bounds.size*scale3).max(Vector3.ONE*0.08)
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.global_transform = Transform3D(transform.basis.orthonormalized(),transform.origin)
	var away := (transform.origin-hit3d).normalized()
	body.linear_velocity = away*force+Vector3(randf_range(-1.5,1.5),randf_range(3.0,6.0),randf_range(-1.5,1.5))
	body.angular_velocity = Vector3(randf_range(-5,5),randf_range(-6,6),randf_range(-5,5))
	part.visible = false
	physical.append({"body":body,"age":0.0,"frozen":false,"velocity":Vector3.ZERO,"angular":Vector3.ZERO})
	# Preserve settled meshes while limiting active physics work in the web build.
	if physical.size()>320:
		var old: Dictionary = physical.pop_front()
		if is_instance_valid(old.body): old.body.queue_free()

func apply_smash(id: int,kind: String,on_beat: bool) -> void:
	total_smashes += 1
	if kind=="heavy": heavy_hits += 1
	id = valid_target(id)
	var heavy := kind=="heavy"
	impact_time = 0.27
	impact_strength = 1.35 if heavy else (1.0 if on_beat else 0.56)
	punch = 1
	shake = maxf(shake,13 if heavy and on_beat else (7 if on_beat else 2))
	if id<0:
		hit3d = avatar.position+Vector3(0,0.2,1)
		for entry in physical:
			if is_instance_valid(entry.body) and entry.body.position.distance_to(hit3d)<5:
				entry.body.freeze = false
				entry.body.apply_central_impulse(Vector3(randf_range(-3,3),5,randf_range(-3,3)))
		make_wave(hit3d,heavy)
		demo_sounds.thump.play()
		say("清场！把残骸再震飞",GOLD,0.5)
		return
	var item: Dictionary = objects[id]
	hit3d = item.pos+Vector3(0,item.size.y*0.55,0)
	if item.kind=="dummy":
		hit3d.y = item.pos.y+item.size.y*0.82
		slaps += 1
		item.slap = 1
		slap_flash = 1
		palm.position = hit3d+Vector3(0.45,0,0.4)
		demo_sounds.slap.play()
		say("啪！"+item.title+"，消停点！",GOLD,0.55)
	else:
		demo_sounds[item.material].play()
		if on_beat: demo_sounds.thump.play()
		say("整 片 震 碎！" if heavy else ("砸 中 重 拍！" if on_beat else "尽管砸，跟底鼓更带劲"),GOLD if on_beat else h.MUTED,0.4)
	var damage := (6.2 if heavy else 2.6) if on_beat else (2.8 if heavy else 0.65)
	damage_object(id,damage,heavy or on_beat)
	if heavy or (on_beat and streak%4==0):
		make_wave(hit3d,heavy)
		var neighbors: Array = []
		for item2 in objects:
			if item2.alive and item2.id!=id and item2.kind!="dummy" and item2.pos.distance_to(item.pos)<(3.7 if heavy else 2.8): neighbors.append(item2.id)
		for neighbor in neighbors:
			chain_hits += 1
			damage_object(neighbor,2.4 if heavy and on_beat else 1.0,true)
	target_id = valid_target(target_id)

func damage_object(id: int,damage: float,explosive: bool) -> void:
	var item: Dictionary = objects[id]
	if not item.alive: return
	var effective := minf(item.hp,damage)
	item.hp = maxf(0,item.hp-damage)
	item.flash = 1
	score += int(effective*25)
	if item.kind=="dummy":
		if item.hp<=0:
			item.alive = false
			broken += 1
			item.collider.queue_free()
			spawn_loot(item.pos+Vector3.UP*1.5,item.value)
		return
	var parts := meshes_below(item.visual)
	if item.hp>0:
		if parts.size()>3: launch_piece(parts[parts.size()-1],2.5 if explosive else 1.2)
		# Shelves/safe expose a real new cash box instead of regenerating themselves.
		if item.kind in ["safe","shelf","cabinet"] and item.title!="现金盒" and not item.revealed and item.hp<=item.maxhp*0.5:
			item.revealed = true
			crates_revealed += 1
			var location: Vector3 = item.pos+Vector3(0,0,item.size.z*0.8+0.45)
			add_prop("safe",location,Vector3(0.65,0.65,0.65),4.5,"metal",160,"现金盒")
			spawn_loot(location+Vector3.UP,25)
		return
	item.alive = false
	broken += 1
	if item.kind=="wall": wall_breaks += 1
	score += 150
	item.collider.queue_free()
	for part in parts: launch_piece(part,4.2 if explosive else 2.4)
	spawn_loot(item.pos+Vector3.UP*minf(1.5,item.size.y),item.value)

func spawn_loot(pos: Vector3,value: int) -> void:
	var count := clampi(int(ceil(value/40.0)),2,8)
	for i in range(count):
		var coin := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.13
		shape.bottom_radius = 0.13
		shape.height = 0.06
		shape.radial_segments = 8
		coin.mesh = shape
		coin.material_override = mat(GOLD,true)
		coin.position = pos+Vector3(randf_range(-0.45,0.45),randf_range(0,0.5),randf_range(-0.45,0.45))
		stage.add_child(coin)
		loot.append({"node":coin,"age":0.0,"value":int(value/count)+(1 if i<value%count else 0),"velocity":Vector3(randf_range(-2,2),randf_range(3,5),randf_range(-2,2))})

func make_wave(pos: Vector3,heavy: bool) -> void:
	var ring := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = 0.92
	shape.outer_radius = 1.0
	ring.mesh = shape
	ring.material_override = mat(GOLD,true)
	ring.position = Vector3(pos.x,0.06,pos.z)
	stage.add_child(ring)
	waves3d.append({"node":ring,"age":0.0,"heavy":heavy})

func update(delta: float) -> void:
	if not is_instance_valid(view): return
	var mode := SubViewport.UPDATE_DISABLED
	if h.screen in ["combat_intro","combat_play"]: mode = SubViewport.UPDATE_ALWAYS
	view.render_target_update_mode = mode
	if not h.screen.begins_with("combat") or h.screen=="combat_pause": return
	pulse = maxf(0,pulse-delta*5)
	punch = maxf(0,punch-delta*6)
	shake = maxf(0,shake-delta*30)
	press_flash = maxf(0,press_flash-delta*6)
	slap_flash = maxf(0,slap_flash-delta*5)
	feedback_timer = maxf(0,feedback_timer-delta)
	guide_label_time = maxf(0,guide_label_time-delta)
	impact_time = maxf(0,impact_time-delta)
	for item in objects:
		item.flash = maxf(0,item.flash-delta*5)
		if item.kind=="dummy":
			item.slap = maxf(0,item.slap-delta*2.8)
			item.visual.rotation.z = sin(item.slap*12)*item.slap*0.26
			item.visual.rotation.y = item.slap*TAU if not item.alive else sin(item.slap*10)*item.slap*0.35
			var head: Node3D = item.visual.get_node_or_null("Head")
			if head: head.rotation.z = item.slap*0.45
		else:
			item.visual.rotation.z = sin(h.anim*30)*item.flash*0.045
	for entry in physical:
		if not is_instance_valid(entry.body): continue
		entry.age += delta
		if entry.age>5.0 and entry.body.linear_velocity.length()<0.3: entry.body.sleeping = true
	for coin in loot:
		coin.age += delta
		coin.node.rotate_y(delta*7)
		if coin.age<0.3:
			coin.velocity.y -= delta*12
			coin.node.position += coin.velocity*delta
		else:
			var destination: Vector3 = avatar.position+Vector3.UP
			coin.node.position = coin.node.position.lerp(destination,1-exp(-delta*7))
			if coin.node.position.distance_to(destination)<0.35 or coin.age>2:
				cash += coin.value
				looted += 1
				coin.node.queue_free()
	loot = loot.filter(func(coin): return is_instance_valid(coin.node) and not coin.node.is_queued_for_deletion())
	for ring in waves3d:
		ring.age += delta
		ring.node.scale = Vector3.ONE*(0.5+ring.age*(10 if ring.heavy else 7))
		if ring.age>0.35: ring.node.queue_free()
	waves3d = waves3d.filter(func(ring): return is_instance_valid(ring.node) and not ring.node.is_queued_for_deletion())
	var selected := valid_target(locked_target if charging else target_id)
	indicator.visible = selected>=0
	if selected>=0:
		var item: Dictionary = objects[selected]
		indicator.position = item.pos+Vector3(0,0.06,0)
		var radius: float = maxf(item.size.x,item.size.z)*0.75+0.25
		indicator.scale = Vector3.ONE*radius
		var destination: Vector3 = item.pos+Vector3(0,0,item.size.z*0.5+1.05)
		avatar.position = avatar.position.lerp(destination,1-exp(-delta*16))
		var look: Vector3 = item.pos-avatar.position
		if look.length_squared()>0.01: avatar.rotation.y = atan2(look.x,look.z)
		if hammer:
			hammer.visible = item.kind!="dummy"
			hammer.rotation.x = punch*1.4-(0.55*minf(1,(now()-charge_start)) if charging else 0)
	palm.visible = slap_flash>0
	if palm.visible:
		palm.position = hit3d+Vector3((1-slap_flash)*0.6,0,0.2)
		palm.rotation.y = slap_flash*2
	camera.position = base_camera+Vector3(sin(h.anim*83),cos(h.anim*91),0)*shake*0.018
	if h.screen!="combat_play": return
	elapsed = now()
	var current_beat := int(floor((elapsed-INTRO)/BEAT))
	if current_beat!=beat:
		beat = current_beat
		pulse = 1
	resolve_cues()
	if elapsed>=PLAY_END: finish(true)

func pointer_down(point: Vector2,source: String) -> void:
	for button in h.buttons:
		if button.rect.has_point(point):
			action(button.id)
			return
	if h.screen=="combat_play" and VIEW_RECT.has_point(point) and not charging:
		var pixel := (point-VIEW_RECT.position)/VIEW_RECT.size*Vector2(view.size)
		var origin := camera.project_ray_origin(pixel)
		var direction := camera.project_ray_normal(pixel)
		var best := INF
		for item in objects:
			if not item.alive: continue
			var bounds := AABB(item.pos-Vector3(item.size.x*0.5,0,item.size.z*0.5),item.size)
			var crossing = bounds.intersects_ray(origin,direction)
			if crossing is Vector3 and origin.distance_to(crossing)<best:
				best = origin.distance_to(crossing)
				target_id = item.id
	press(source)

func freeze_bodies(frozen: bool) -> void:
	for entry in physical:
		if not is_instance_valid(entry.body): continue
		if frozen:
			entry.velocity = entry.body.linear_velocity
			entry.angular = entry.body.angular_velocity
			entry.frozen = entry.body.freeze
			entry.body.freeze = true
		else:
			entry.body.freeze = entry.frozen
			entry.body.linear_velocity = entry.velocity
			entry.body.angular_velocity = entry.angular

func pause_game() -> void:
	if h.screen!="combat_play": return
	freeze_bodies(true)
	super.pause_game()
	beat_guide.stream_paused = true

func resume_game() -> void:
	if h.screen!="combat_pause": return
	super.resume_game()
	beat_guide.stream_paused = false
	freeze_bodies(false)

func finish(_success: bool) -> void:
	if h.screen=="combat_result": return
	# Settle outstanding automatic pickup rewards before showing the result.
	for coin in loot:
		cash += coin.value
		looted += 1
		coin.node.queue_free()
	loot.clear()
	won = true
	h.screen = "combat_result"
	stop()
	var key := "wreck3d_"+("easy" if h.easy else "normal")
	if score+cash>int(h.records.get(key,0)): h.records[key] = score+cash
	h.save_data()

func state() -> Dictionary:
	var chart: Array = []
	var props: Array = []
	for cue in cues: chart.append({"time":cue.time,"beat":cue.beat,"type":cue.type,"status":cue.status})
	for item in objects:
		var point := camera.unproject_position(item.pos+Vector3.UP*item.size.y*0.5)
		var screen: Vector2 = VIEW_RECT.position+point/Vector2(view.size)*VIEW_RECT.size
		props.append({"id":item.id,"kind":item.kind,"alive":item.alive,"hp":item.hp,"x":screen.x,"y":screen.y,"title":item.title})
	return {"mode":"wreck3d","elapsed":elapsed,"duration":PLAY_END,"beat":beat,"score":score,"cash":cash,"looted":looted,"slaps":slaps,"resolved":resolved,"missed":missed,"streak":streak,"maxStreak":max_streak,"heavyHits":heavy_hits,"weakHits":weak_hits,"broken":broken,"walls":wall_breaks,"chainHits":chain_hits,"destruction":destruction(),"charging":charging,"target":target_id,"won":won,"debris":physical.size(),"revealed":crates_revealed,"shopIdentity":shop_identity,"cues":chart,"objects":props,"worldMeshes":stage.find_children("*","MeshInstance3D",true,false).size(),"beatGuide":beat_ring(elapsed),"judgement":guide_label if guide_label_time>0 else ""}

func section_name() -> String:
	var names := {"verse_intro":"主歌 · 开砸","funk_groove":"切分贝斯","break":"Break · 留住底鼓","drop":"Drop · 全力拆","melodic_lift":"旋律抬升","final_fill":"终段鼓花","outro":"余音收束"}
	for section in track.sections:
		if elapsed>=float(section.from) and elapsed<float(section.to): return names.get(str(section.id),str(section.id))
	return "准备开拆"

func draw_view() -> void:
	h.draw_texture_rect(view.get_texture(),VIEW_RECT,false)
	h.rounded(VIEW_RECT,Color.TRANSPARENT,18,Color("5b496c"))

func draw_impact() -> void:
	if impact_time<=0: return
	var center := project_to_screen(hit3d)
	var life := impact_time/0.27
	var reach := (25.0+(1.0-life)*71.0)*impact_strength
	var tint := Color(PEACH,life)
	for i in range(9):
		var angle := i*TAU/9+0.17
		var axis := Vector2.from_angle(angle)
		var across := axis.orthogonal()
		var pos := center+axis*reach
		if not VIEW_RECT.grow(-9).has_point(pos): continue
		h.draw_colored_polygon(PackedVector2Array([
			pos+axis*(14.0+life*5.0),
			pos+across*3.0,
			pos-axis*7.0,
			pos-across*3.0
		]),tint if i%2==0 else Color(MINT,life))

func draw_beat_ring(center: Vector2,clock: float,preview := false) -> void:
	var timing := beat_ring(clock)
	var ring_scale := 1.0 if preview else 0.62
	var radius: float = timing.radius*ring_scale
	var inner := TARGET_RING*ring_scale
	var feedback_tint := MINT if timing.flash else PEACH
	h.draw_circle(center,inner,Color(MINT,0.12 if timing.flash else 0.045),true,-1,true)
	h.draw_arc(center,inner,0,TAU,56,Color("100f20"),7,true)
	h.draw_arc(center,inner,0,TAU,56,MINT if timing.flash else Color("fff2e0"),3.2,true)
	if timing.flash:
		h.draw_arc(center,inner+6,0,TAU,56,Color(MINT,0.62),3,true)
	else:
		h.draw_arc(center,radius,0,TAU,72,Color("160f27"),7,true)
		h.draw_arc(center,radius,0,TAU,72,feedback_tint,3.6,true)
	if not preview and elapsed<INTRO:
		var count := clampi(int(floor(elapsed/BEAT))+1,1,4)
		h.center(str(count),center+Vector2(0,8),22,Color("fff2e0"))
	else:
		h.draw_circle(center,4.5,feedback_tint,true,-1,true)
		var beat_position: float = (clock-INTRO-h.offset_ms/1000.0)/BEAT
		var current_beat := int(floor(beat_position))
		if not preview and (current_beat+1)%16==0:
			# A small ornament marks the optional upbeat without changing the main countdown.
			var upbeat := absf(fposmod(beat_position,1.0)-0.5)<0.12
			h.draw_circle(center+Vector2(11,0),4 if upbeat else 2.5,PEACH,true,-1,true)
	if not preview and charging and now()-charge_start>=0.28:
		h.draw_arc(center,inner-6,-PI/2,PI*1.5,48,Color(GOLD,0.75),2.5,true)

func draw_intro() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color("1c162e"))
	h.brand()
	h.button("sound",Rect2(1020,28,174,44),"声音关" if h.muted else "声音开",false,true)
	h.button("combat_menu",Rect2(1212,28,180,44),"其他模式",false,true)
	var preview := Rect2(620,172,738,324)
	h.rounded(preview.grow(8),PANEL_DARK,21,Color("63506e"))
	h.draw_texture_rect(view.get_texture(),preview,false)
	h.text("节拍拆迁王",Vector2(84,250),71,PEACH)
	h.text("午夜百货",Vector2(90,338),60,MINT)
	h.text("跟着鼓点，砸个痛快。",Vector2(92,410),26,h.INK)
	h.rounded(Rect2(83,546,1275,137),PANEL_DARK,24,Color("63506e"))
	draw_beat_ring(Vector2(164,615),h.anim,true)
	h.text("看下方节拍圈，合圈时按空格",Vector2(260,607),30,MINT)
	h.text("也可直接点物件。按住后，在重合时松开能重砸。",Vector2(260,647),21,h.INK)
	h.button("combat_start",Rect2(430,731,365,72),"开砸！ →",true)
	h.button("mode",Rect2(820,731,230,72),"宽松节拍 ⇄" if h.easy else "精准节拍 ⇄")
	h.center("48 秒 · 120 BPM",Vector2(720,861),17,Color("c6aecf"))

func draw_game() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color("1c162e"))
	h.brand()
	h.button("sound",Rect2(1120,28,115,44),"静音" if h.muted else "声音 开",false,true)
	h.button("combat_pause",Rect2(1250,28,142,44),"Ⅱ 暂停",false,true)
	h.rounded(Rect2(48,91,1344,4),h.LINE,2)
	h.rounded(Rect2(48,91,1344*clampf((elapsed-INTRO)/48,0,1),4),GOLD,2)
	h.text("午夜百货",Vector2(52,142),24,PEACH)
	h.center("战利品 ¥%d" % cash,Vector2(741,142),26,GOLD)
	h.text("%02d 秒" % int(ceil(maxf(0,PLAY_END-maxf(INTRO,elapsed)))),Vector2(1270,142),22,h.MUTED)
	draw_view()
	draw_impact()
	var selected := valid_target(locked_target if charging else target_id)
	if selected>=0 and objects[selected].kind=="dummy":
		var item: Dictionary = objects[selected]
		var label := project_to_screen(item.pos+Vector3.UP*item.size.y)+Vector2(81,-17)
		h.rounded(Rect2(label+Vector2(-65,-22),Vector2(130,31)),PANEL_DARK,11)
		h.center(item.title,label,17,PEACH)
	if slap_flash>0.25:
		h.center("啪！",project_to_screen(hit3d+Vector3.UP*0.4)+Vector2(62,60),36,GOLD)
	draw_rhythm_panel()

func draw_rhythm_panel() -> void:
	h.rounded(RHYTHM_PANEL,PANEL_DARK,18,Color("5b496c"))
	draw_beat_ring(Vector2(539,RHYTHM_PANEL.get_center().y),elapsed)
	var instruction := "两圈重合时，按一下空格"
	if charging and now()-charge_start>=0.28:
		instruction = "两圈重合时，松手重砸"
	elif elapsed>=6:
		instruction = "空格 · 合圈时出手"
	h.text(instruction,Vector2(620,816),24,PEACH if charging else h.INK)
	var detail := section_name()
	var color := Color("c6b0d0")
	if guide_label_time>0 and elapsed>=INTRO:
		detail = guide_label
		color = guide_color
	if streak>=4: detail += "  ·  %d 连拍" % streak
	h.text(detail,Vector2(620,850),19,color)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.92))
	h.buttons.clear()
	h.rounded(Rect2(290,175,860,565),h.PANEL,28,GOLD)
	h.center("商场拆了，压力散了。",Vector2(720,258),41,GOLD)
	h.center("¥ %d" % cash,Vector2(720,355),64,GOLD)
	h.center("砸碎 %d 件 · 连锁 %d 次 · 巴掌 %d 下" % [broken,chain_hits,slaps],Vector2(720,426),25,AQUA)
	h.center("重砸 %d 次 · 揭开 %d 个暗格 · 破坏率 %d%%" % [heavy_hits,crates_revealed,int(destruction()*100)],Vector2(720,478),22)
	h.center("接上 %d / %d 拍 · 最长 %d 连拍 · 拆迁得分 %d" % [resolved,cues.size(),max_streak,score],Vector2(720,532),19,h.MUTED)
	h.button("combat_start",Rect2(415,621,300,67),"再砸一遍！",true)
	h.button("combat_menu",Rect2(740,621,280,67),"其他模式")
