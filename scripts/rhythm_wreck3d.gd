extends "res://scripts/rhythm_demolition.gd"

const CHARGE_MIN := 0.24
const BEAT_WINDOW := 0.13
const DOUBLE_WINDOW := 0.095
const STREAK_GRACE := 3.0*BEAT
const LOOP_START := 2.0
const LOOP_END := 50.0
const SECTION_LENGTH := 16.0*BEAT
const SHOW_WINDOW := 0.12
const PINK := Color("ffa9d6")
const VIOLET := Color("bba5ff")
const CHARGE_FULL := 0.75
const TAP_COOLDOWN := 0.09
const VIEW_RECT := Rect2(48,159,1344,686)
const FLOOR_MARKERS := [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]
const PANEL_DARK := Color("302541")
const PEACH := Color("ffd3aa")
const MINT := Color("94fae0")
const CAMERA_ORBIT := Vector3(12.8,19.0,26.6)
const ShopDecor = preload("res://scripts/wreck3d_shop_decor.gd")
enum Show { WARMUP, RELAY, REBOUND, DROP }
const SECTIONS := [Show.WARMUP,Show.RELAY,Show.REBOUND,Show.DROP,Show.RELAY,Show.DROP]
const SHOW_NAMES := ["","换位接力","回弹追拍","低音爆破"]
const SHOW_COLORS := [Color("ffdfa9"),MINT,PINK,VIOLET]
var view: SubViewport
var stage: Node3D
var camera: Camera3D
var avatar: Node3D
var hammer: Node3D
var indicator: Node3D
var marker_material: StandardMaterial3D
var target_light: OmniLight3D
var hammer_light: StandardMaterial3D
var marquee_light: StandardMaterial3D
var show_light: OmniLight3D
var physical: Array = []
var loot: Array = []
var waves3d: Array = []
var cash := 0
var slaps := 0
var looted := 0
var crates_revealed := 0
var base_camera := CAMERA_ORBIT
var hit3d := Vector3.ZERO
var impact_target := -1
var impact_time := 0.0
var impact_strength := 0.0
var slap_flash := 0.0
var slapped_target := -1
var locked_point := Vector3.ZERO
var rhythm_time := 0.0
var music_phase := 0.0
var music_loops := 0
var double_target := -1
var double_at := 0.0
var double_hits := 0
var timed_heavies := 0
var last_pulse := -1
var section := -1
var show_type: Show = Show.WARMUP
var show_target := -1
var show_step := 0
var show_due := 0.0
var show_count := 0
var encore_at := INF
var relay_from := Vector3.ZERO
var bounce_start := 0.0
var specials := 0
var trails: Array[Dictionary] = []
var blast_queue: Array[Dictionary] = []
var impact_label := ""
var impact_label_time := 0.0
var palm: MeshInstance3D
var shop_identity := 0
var combat_backdrop := Color("29223d")
var meshes := preload("res://scripts/wreck3d_art.gd")

func _init(host) -> void:
	super(host)

	var bed: AudioStreamWAV = load("res://assets/audio/wreck3d/rhythm_mix.wav").duplicate()
	bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bed.loop_begin = int(LOOP_START*bed.mix_rate)
	bed.loop_end = int(LOOP_END*bed.mix_rate)
	music.stream = bed
	music.volume_db = -4
	var clap := AudioStreamPlayer.new()
	clap.stream = load("res://assets/audio/demolition/slap.wav")
	clap.volume_db = -5
	clap.max_polyphony = 2
	h.add_child(clap)
	demo_sounds.slap = clap
	for i in range(3):
		melody_players[i].stream = load("res://assets/audio/wreck3d/shot_%d.wav" % [1,4,6][i])
		melody_players[i].volume_db = -10

	view = SubViewport.new()
	view.size = Vector2i(VIEW_RECT.size)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	h.add_child(view)
	build_shop()

func start() -> void:
	stop()
	h.music.stop()
	h.adventure.stop_audio()
	elapsed = 0.0
	rhythm_time = 0.0
	music_phase = 0.0
	music_loops = 0
	double_target = -1
	double_at = 0.0
	double_hits = 0
	timed_heavies = 0
	last_pulse = -1
	section = -1
	show_type = Show.WARMUP
	show_target = -1
	show_step = 0
	show_due = 0.0
	show_count = 0
	encore_at = INF
	specials = 0
	trails.clear()
	blast_queue.clear()
	resolved = 0
	streak = 0
	max_streak = 0
	last_strike = -99.0
	cash = 0
	slaps = 0
	looted = 0
	broken = 0
	heavy_hits = 0
	wall_breaks = 0
	chain_hits = 0
	total_smashes = 0
	crates_revealed = 0
	impact_label = ""
	impact_label_time = 0.0
	impact_time = 0.0
	impact_target = -1
	slap_flash = 0.0
	slapped_target = -1
	punch = 0.0
	shake = 0.0
	won = false
	build_shop()
	shop_identity = stage.get_instance_id()
	h.screen = "combat_play"
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	music.play()

func stop() -> void:
	super.stop()
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
	marquee_light = ShopDecor.build(stage)
	marquee_light.emission_energy_multiplier = 0.55
	show_light = OmniLight3D.new()
	show_light.omni_range = 3.7
	show_light.omni_attenuation = 1.25
	show_light.visible = false
	stage.add_child(show_light)
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
	add_prop("dummy",Vector3(5.2,0,3.5),Vector3(1.25,2.1,1.15),0,"slap",0,"催加班经理",0)
	add_prop("dummy",Vector3(8.6,0,4.7),Vector3(1.25,2.1,1.15),0,"slap",0,"插队大叔",1)
	add_prop("dummy",Vector3(-2.1,0,-5),Vector3(1.25,2.1,1.15),0,"slap",0,"开会达人",2)
	# Breakable architectural pieces expose a permanent hole in the facade.
	for x in [-8.0,0.0,8.0]: add_prop("wall",Vector3(x,0,-6.65),Vector3(2.6,2.8,0.3),18,"wood",40)
	avatar = meshes.create_hero()
	avatar.scale = Vector3.ONE*1.25
	stage.add_child(avatar)
	avatar.position = Vector3(-8,0,5)
	hammer = avatar.get_node_or_null("Hammer")
	var stripe: MeshInstance3D = hammer.get_node("HammerStripe")
	hammer_light = stripe.material_override.duplicate()
	hammer_light.emission_enabled = true
	stripe.material_override = hammer_light
	build_floor_markers()
	palm = box(stage,Vector3.ZERO,Vector3(0.48,0.1,0.64),Color("f4d7aa"))
	palm.visible = false
	for i in range(4): box(palm,Vector3(-0.18+i*0.12,0,0.36),Vector3(0.085,0.09,0.25),Color("f4d7aa"))
	target_id = pick_target()

func build_floor_markers() -> void:
	indicator = Node3D.new()
	indicator.name = "TargetCorners"
	stage.add_child(indicator)
	indicator.visible = false
	marker_material = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var stripe := PlaneMesh.new()
	stripe.size = Vector2(0.32,0.085)
	for direction: Vector2 in FLOOR_MARKERS:
		var corner := Node3D.new()
		indicator.add_child(corner)
		for axis in [0,1]:
			var line := MeshInstance3D.new()
			line.mesh = stripe
			line.material_override = marker_material
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if axis == 0:
				line.position.x = -direction.x*0.12
			else:
				line.rotation.y = PI*0.5
				line.position.z = -direction.y*0.12
			corner.add_child(line)
	target_light = OmniLight3D.new()
	target_light.visible = false
	target_light.shadow_enabled = false
	target_light.omni_attenuation = 1.75
	stage.add_child(target_light)

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
	objects.append({"id":objects.size(),"kind":kind,"pos":pos,"size":size,"hp":health,"maxhp":health,"material":material,"alive":true,"value":value,"visual":visual,"collider":solid,"flash":0.0,"title":title,"revealed":false,"slap":0.0,"slap_side":1.0,"slap_power":0.0,"variant":variant})
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

func press(source := "test") -> void:
	var id := valid_target(target_id)
	var point: Vector3 = objects[id].pos if id>=0 else avatar.position
	begin_hit(source,id,point)

func begin_hit(source: String,id: int,point: Vector3) -> void:
	if h.screen!="combat_play" or not active_input.is_empty() or elapsed-last_strike<TAP_COOLDOWN:
		return
	sync_rhythm()
	if id!=double_target: double_target = -1
	active_input = source
	charging = attack_style(id)=="hold"
	charge_start = elapsed
	last_strike = elapsed
	locked_target = id
	locked_point = point
	var approach := action_position(id,point)
	if avatar.position.distance_to(approach)>2.0:
		avatar.position = approach+Vector3(0,0,0.35)
	face_target(point)
	if not charging: rhythmic_hit(id,point,0.0)

func release(source := "test") -> void:
	if h.screen!="combat_play" or active_input!=source: return
	var power := charge_level()
	active_input = ""
	if charging:
		sync_rhythm()
		charging = false
		rhythmic_hit(locked_target,locked_point,power)
	locked_target = -1

func charge_level() -> float:
	if not charging or elapsed-charge_start<CHARGE_MIN: return 0.0
	return lerpf(0.45,1.0,clampf(inverse_lerp(CHARGE_MIN,CHARGE_FULL,elapsed-charge_start),0,1))

func attack_style(id: int) -> String:
	if id<0: return "hold"
	var item: Dictionary = objects[id]
	if item.kind in ["arcade","vending","dummy"]: return "double"
	if item.kind in ["wall","shelf","sofa","charge_crate"] or (item.kind=="safe" and item.title.is_empty()):
		return "hold"
	return "tap"

func selected_target() -> int:
	if charging: return locked_target
	return valid_target(target_id)

func sync_rhythm() -> void:
	if not music.playing:
		rhythm_time = elapsed
	else:
		var position := music.get_playback_position()
		if music_phase-position>(LOOP_END-LOOP_START)*0.5: music_loops += 1
		music_phase = position
		var audible_time := position+music_loops*(LOOP_END-LOOP_START)
		audible_time += AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
		rhythm_time = maxf(rhythm_time,audible_time-h.offset_ms/1000.0)
	if double_target>=0 and rhythm_time>double_at+DOUBLE_WINDOW: double_target = -1
	if streak>0 and rhythm_time-float(last_pulse)*BEAT*0.5>STREAK_GRACE: streak = 0
	update_show()

func cue_time(id: int) -> float:
	if id>=0 and id==show_target and show_step==1: return show_due
	if id>=0 and id==double_target: return double_at
	if id>=0 and id==show_target and show_type==Show.DROP:
		var shift := drop_beat_shift()
		return (floorf((rhythm_time-0.09-shift)/(2.0*BEAT))+1.0)*2.0*BEAT+shift
	return (floorf((rhythm_time-0.09)/BEAT)+1.0)*BEAT

func update_show() -> void:
	var current := maxi(0,int(floor((rhythm_time-LOOP_START)/SECTION_LENGTH)))
	if current!=section:
		section = current
		show_type = SECTIONS[section%SECTIONS.size()]
		show_count = 0
		encore_at = INF
		arm_show()
		marquee_light.emission = SHOW_COLORS[show_type]
		show_light.light_color = SHOW_COLORS[show_type]
	elif encore_at<=rhythm_time and active_input.is_empty() and double_target<0:
		encore_at = INF
		arm_show()
	if show_step==1 and rhythm_time>show_due+SHOW_WINDOW:
		show_step = 0
	if show_target>=0 and not objects[show_target].alive:
		show_target = -1
		encore_at = rhythm_time+BEAT*2.0
	var accent := 1.0-clampf(absf(rhythm_time-roundf(rhythm_time/BEAT)*BEAT)/0.13,0,1)
	marquee_light.emission_energy_multiplier = 0.42+0.8*accent
	show_light.visible = show_target>=0
	if show_light.visible:
		var item: Dictionary = objects[show_target]
		show_light.position = item.pos+Vector3(0,2.4,0.62)
		var flash := 1.0-clampf(absf(cue_time(show_target)-rhythm_time)/0.11,0,1)
		show_light.light_energy = 0.48+flash*1.05

func arm_show() -> void:
	show_target = -1
	show_step = 0
	show_due = 0.0
	match show_type:
		Show.RELAY:
			show_target = relay_neighbor(avatar.position,-1)
		Show.REBOUND:
			var variant := (int(section/SECTIONS.size())+show_count)%3
			for item in objects:
				if item.kind=="dummy" and item.variant==variant:
					show_target = item.id
					break
		Show.DROP:
			show_target = delivery("charge_crate",0)
	if show_target>=0 and active_input.is_empty() and double_target<0:
		target_id = show_target

func delivery(kind: String,slot: int) -> int:
	var blast := kind=="charge_crate"
	for item in objects:
		if item.kind!=kind or item.variant!=slot: continue
		if not item.alive:
			item.hp = item.maxhp
			item.alive = true
			item.visual.rotation = Vector3.ZERO
			for piece in item.visual.find_children("*","MeshInstance3D",true,false): piece.show()
			var center: Vector3 = item.pos+Vector3.UP*item.size.y*0.5
			item.collider = collider(stage,center,item.size*Vector3(0.9,1,0.9))
			make_wave(item.pos,blast)
		return item.id
	var pos := Vector3(2.9,0,6.1) if blast else Vector3(-5.4+3.5*slot,0,5.85)
	var size := Vector3(1.24,1.12,1.03) if blast else Vector3(0.96,0.88,0.86)
	var label := "低音箱" if blast else "补货箱"
	var id := add_prop(kind,pos,size,13.0 if blast else 7.0,"metal" if blast else "wood",80,label,slot)
	var visual: Node3D = objects[id].visual
	var stripe := box(visual,Vector3(0,0.72,0.52),Vector3(0.78,0.11,0.051),VIOLET if blast else MINT,true)
	stripe.name = "DeliveryLight"
	make_wave(pos,blast)
	return id

func relay_neighbor(point: Vector3,exclude: int) -> int:
	var next := -1
	var closest := INF
	for item in objects:
		if item.id==exclude or not item.alive or attack_style(item.id)!="tap": continue
		var distance: float = item.pos.distance_to(point)
		if distance<closest:
			closest = distance
			next = item.id
	if next>=0: return next
	var slot := 1 if exclude>=0 and objects[exclude].kind=="relay_crate" and objects[exclude].variant==0 else 0
	return delivery("relay_crate",slot)

func drop_beat_shift() -> float:
	return BEAT if section%SECTIONS.size()==5 else 0.0

func rhythmic_hit(id: int,point: Vector3,power: float) -> void:
	var pulse_index := int(roundf(rhythm_time/BEAT))*2
	var grade := "loose"
	if id>=0:
		if id==show_target and show_step==1 and absf(rhythm_time-show_due)<=SHOW_WINDOW:
			pulse_index = int(roundf(show_due/BEAT*2.0))
			grade = "relay" if show_type==Show.RELAY else "rebound"
		elif id==double_target and absf(rhythm_time-double_at)<=DOUBLE_WINDOW:
			pulse_index = int(roundf(double_at/BEAT*2.0))
			grade = "double"
			double_target = -1
			double_hits += 1
		elif pulse_index!=last_pulse and absf(rhythm_time-float(pulse_index)*BEAT*0.5)<=BEAT_WINDOW:
			grade = "beat"
			if id==show_target and show_type==Show.DROP and power>0.0 and pulse_index%4==int(drop_beat_shift()/BEAT)*2:
				grade = "blast"
			if attack_style(id)=="double" and (id!=show_target or show_step==0):
				double_target = id
				double_at = (float(pulse_index)+1.0)*BEAT*0.5
		if grade=="loose":
			if pulse_index!=last_pulse: streak = 0
		else:
			last_pulse = pulse_index
			resolved += 1
			streak += 1
			max_streak = maxi(max_streak,streak)
			if power>0.0: timed_heavies += 1
	hit_target(id,point,power,grade)
	if id==double_target and id>=0 and not objects[id].alive: double_target = -1
	if id>=0 and id==show_target:
		advance_show(id,grade,float(pulse_index)*BEAT*0.5)

func advance_show(id: int,grade: String,beat_at: float) -> void:
	var point: Vector3 = objects[id].pos
	match grade:
		"relay":
			add_trail(relay_from,point,MINT)
			make_wave(point,true,MINT)
			spawn_loot(point+Vector3.UP,100)
			announce("换位接上！")
		"rebound":
			add_trail(point+Vector3(1.6,1.4,0),point,PINK)
			make_wave(point,false,PINK)
			spawn_loot(point+Vector3.UP,110)
		"blast":
			queue_blast(id,beat_at)
			announce("低音引爆！")
		_:
			if show_type==Show.RELAY and grade=="beat" and show_step==0:
				show_target = relay_neighbor(point,id)
				target_id = show_target
				relay_from = point
				show_step = 1
				show_due = beat_at+(BEAT*1.5 if section%SECTIONS.size()==4 else BEAT)
				add_trail(point,objects[show_target].pos,MINT,show_due-rhythm_time)
			elif show_type==Show.REBOUND and grade=="double" and show_step==0:
				show_step = 1
				bounce_start = rhythm_time
				show_due = beat_at+float([0.75,1.0,0.50][objects[id].variant])
				add_trail(point,point+Vector3(1.5,0.8,-0.2),PINK)
			return
	specials += 1
	melody_players[show_type-1].play()
	show_count += 1
	if show_count<2: encore_at = beat_at+4.0*BEAT
	show_target = -1
	show_step = 0

func queue_blast(id: int,beat_at: float) -> void:
	var origin: Vector3 = objects[id].pos
	make_wave(origin,true,VIOLET)
	spawn_loot(origin+Vector3.UP*1.5,150)
	var candidates: Array[Dictionary] = []
	for item in objects:
		if item.id!=id and item.alive and item.kind!="dummy" and item.pos.distance_to(origin)<8.0:
			candidates.append(item)
	if candidates.size()<2:
		for slot in range(2):
			var crate: Dictionary = objects[delivery("relay_crate",slot)]
			if not candidates.has(crate): candidates.append(crate)
	candidates.sort_custom(func(a,b): return a.pos.distance_squared_to(origin)<b.pos.distance_squared_to(origin))
	for i in range(mini(3,candidates.size())):
		blast_queue.append({"id":candidates[i].id,"due":beat_at+BEAT*0.5*(i+1),"from":origin})

func update_blast() -> void:
	while not blast_queue.is_empty() and blast_queue[0].due<=rhythm_time:
		var blast: Dictionary = blast_queue.pop_front()
		var item: Dictionary = objects[blast.id]
		if not item.alive: continue
		var point: Vector3 = item.pos
		add_trail(blast.from,point,VIOLET)
		make_wave(point,true,VIOLET)
		kick_debris(point,4.5,11.0)
		chain_hits += 1
		damage_prop(item.id,8.0,true,point)
		demo_sounds[item.material].play()

func add_trail(from: Vector3,to: Vector3,tint: Color,duration := 0.42) -> void:
	trails.append({"from":from,"to":to,"tint":tint,"at":elapsed,"duration":duration})


func action_position(id: int,point: Vector3) -> Vector3:
	var distance := 0.9
	if id>=0: distance = objects[id].size.z*0.5+1.05
	return Vector3(point.x,0,minf(7.2,point.z+distance))

func face_target(point: Vector3) -> void:
	var look := point-avatar.position
	if look.length_squared()>0.01: avatar.rotation.y = atan2(look.x,look.z)

func project_to_screen(pos: Vector3) -> Vector2:
	return VIEW_RECT.position+camera.unproject_position(pos)/Vector2(view.size)*VIEW_RECT.size

func update_floor_markers(selected: int) -> void:
	var active: bool = h.screen=="combat_play"
	indicator.visible = active and selected>=0
	target_light.visible = indicator.visible
	if not active: return
	var fill := clampf((elapsed-charge_start)/CHARGE_FULL,0,1) if charging else 0.0
	var tint := MINT.lerp(GOLD,fill)
	hammer_light.emission = tint
	hammer_light.emission_energy_multiplier = 0.35+fill*1.3
	hammer.rotation.x = punch*1.5-fill*0.85
	if not indicator.visible: return
	var item: Dictionary = objects[selected]
	var center: Vector3 = item.pos
	center.y = 0.083
	var half_size := Vector2(item.size.x,item.size.z)*0.5+Vector2.ONE*0.30
	var until := cue_time(selected)-rhythm_time
	var ready_color := tint
	match attack_style(selected):
		"hold": ready_color = GOLD
		"double": ready_color = PINK
	if selected==show_target: ready_color = SHOW_COLORS[show_type]
	var flash := 1.0-clampf(absf(until)/0.09,0,1)
	var spacing := clampf(until/0.37,0,1)*0.82
	marker_material.albedo_color = ready_color.lerp(Color("fff8d4"),flash)
	for index in range(FLOOR_MARKERS.size()):
		var axis: Vector2 = FLOOR_MARKERS[index]
		var corner := center+Vector3(axis.x*(half_size.x+spacing),0,axis.y*(half_size.y+spacing))
		indicator.get_child(index).position = corner.clamp(Vector3(-12.04,0.083,-6.96),Vector3(12.26,0.083,7.31))
	target_light.position = center+Vector3(0,item.size.y*0.55+0.8,half_size.y+0.36)
	target_light.light_color = ready_color.lerp(Color.WHITE,flash*0.8)
	target_light.omni_range = 2.5+item.size.y*0.45
	target_light.light_energy = 0.26+fill*0.38+flash*1.45
	hammer_light.emission_energy_multiplier += flash*0.85

func meshes_below(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is MeshInstance3D and child.visible: found.append(child)
		found.append_array(meshes_below(child))
	return found

func launch_piece(part: MeshInstance3D,force: float,origin: Vector3) -> void:
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
	var away := (transform.origin-origin).normalized()
	body.linear_velocity = away*force+Vector3(randf_range(-1.5,1.5),randf_range(3.0,6.0),randf_range(-1.5,1.5))
	body.angular_velocity = Vector3(randf_range(-5,5),randf_range(-6,6),randf_range(-5,5))
	part.visible = false
	physical.append({"body":body,"age":0.0,"frozen":false,"velocity":Vector3.ZERO,"angular":Vector3.ZERO})
	# Preserve settled meshes while limiting active physics work in the web build.
	if physical.size()>320:
		var old: Dictionary = physical.pop_front()
		if is_instance_valid(old.body): old.body.queue_free()

func hit_target(id: int,point: Vector3,power: float,grade: String) -> void:
	var heavy := power>0.0
	var timed := grade!="loose"
	var two := grade=="double"
	var extra := grade in ["relay","rebound","blast"]
	var reaction := maxf(power,1.0 if extra else (0.65 if two else 0.0))
	total_smashes += 1
	if heavy: heavy_hits += 1
	impact_target = id
	impact_time = 0.27
	impact_strength = (1.0 if timed else 0.65)+reaction*0.80
	punch = 1.0
	shake = maxf(shake,(5.0 if timed else 2.0)+reaction*9.0)
	hit3d = point
	impact_label_time = 0.0
	slap_flash = 0.0
	if id<0 or not objects[id].alive:
		if heavy:
			kick_debris(point,2.0+reaction*2.2,4.0+reaction*5.0)
			make_wave(point,true)
			demo_sounds.thump.play()
		return
	var item: Dictionary = objects[id]
	hit3d = item.pos+Vector3.UP*item.size.y*0.55
	if item.kind=="dummy":
		slap_character(item,reaction)
		impact_label = "双拍！" if two else ("准拍啪！" if timed else "啪！")
		if grade=="rebound": impact_label = "回弹全中！"
		return
	demo_sounds[item.material].play()
	if heavy or two:
		demo_sounds.thump.play()
		kick_debris(point,2.0+reaction*2.2,4.0+reaction*5.0)
		make_wave(point,true)
	var damage := 9.5 if two else (4.6 if timed else 2.0)
	if grade=="relay": damage = 10.5
	if heavy: damage = lerpf(8.0,20.0,power)*(1.0 if timed else 0.47)
	var keep_crate := id==show_target and show_type==Show.DROP and grade!="blast"
	if keep_crate: damage = minf(damage,maxf(0,item.hp-1.0))
	var shattered := damage>0.0 and damage_prop(id,damage,heavy or two or extra)
	if shattered:
		match item.kind:
			"arcade":
				if bump_arcade(id): announce("街机连锁！")
			"vending":
				kick_debris(point,3.3,5.0)
				make_wave(point,true)
				announce("汽水喷泉！")
			"safe":
				if item.title.is_empty():
					kick_debris(point,4.5,8.0)
					announce("保险柜开了！")
	if impact_label_time==0.0:
		if keep_crate: announce("等紫光再松手")
		elif two: announce("双拍连击！")
		elif timed: announce("准拍重砸！" if heavy else "准拍！")
		elif heavy: announce("松手跟着亮光")
	target_id = valid_target(target_id)

func announce(label: String) -> void:
	impact_label = label
	impact_label_time = 0.66

func slap_character(item: Dictionary,power: float) -> void:
	hit3d = item.visual.position+Vector3.UP*item.size.y*0.79
	slaps += 1
	item.slap = 1.0
	item.slap_side = -item.slap_side
	item.slap_power = power
	slapped_target = item.id
	slap_flash = 1.0
	demo_sounds.slap.play()

func kick_debris(center: Vector3,radius: float,force: float) -> void:
	for entry in physical:
		var body: RigidBody3D = entry.body
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var away := body.position-center
		away.y = 0.0
		var distance := away.length()
		if distance>=radius: continue
		body.sleeping = false
		entry.age = 0.0
		body.apply_central_impulse((away.normalized()*0.8+Vector3.UP)*body.mass*force*(1.0-distance/radius))

func bump_arcade(id: int) -> bool:
	var source: Dictionary = objects[id]
	var next := -1
	var closest := 2.3
	for item in objects:
		if item.kind!="arcade" or not item.alive: continue
		var distance: float = source.pos.distance_to(item.pos)
		if distance<closest:
			closest = distance
			next = item.id
	if next<0: return false
	chain_hits += 1
	make_wave(objects[next].pos,false)
	damage_prop(next,4.5,true)
	return true

func damage_prop(id: int,damage: float,explosive: bool,origin := Vector3.INF) -> bool:
	var item: Dictionary = objects[id]
	if not item.alive or item.kind=="dummy": return false
	item.hp = maxf(0,item.hp-damage)
	item.flash = 1.0
	var parts := meshes_below(item.visual)
	if origin==Vector3.INF: origin = hit3d
	if item.hp>0:
		if parts.size()>3: launch_piece(parts.back(),2.5 if explosive else 1.2,origin)
		if item.kind in ["safe","shelf","cabinet"] and item.title!="现金盒" and not item.revealed and item.hp<=item.maxhp*0.5:
			item.revealed = true
			crates_revealed += 1
			var location: Vector3 = item.pos+Vector3(0,0,item.size.z*0.8+0.45)
			add_prop("safe",location,Vector3(0.65,0.65,0.65),4.5,"metal",160,"现金盒")
			spawn_loot(location+Vector3.UP,25)
		return false
	item.alive = false
	broken += 1
	if item.kind=="wall": wall_breaks += 1
	item.collider.queue_free()
	for part: MeshInstance3D in parts:
		var force := 4.2 if explosive else 2.4
		if item.kind=="vending" and str(part.name).ends_with("Can"): force = 7.5
		launch_piece(part,force,origin)
	spawn_loot(item.pos+Vector3.UP*minf(1.5,item.size.y),item.value)
	return true

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

func make_wave(pos: Vector3,heavy: bool,tint := Color.TRANSPARENT) -> void:
	var ring := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = 0.92
	shape.outer_radius = 1.0
	ring.mesh = shape
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.albedo_color = tint if tint.a>0.0 else (GOLD if heavy else MINT)
	ring.material_override = surface
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(pos.x,0.10,pos.z)
	stage.add_child(ring)
	waves3d.append({"node":ring,"age":0.0,"heavy":heavy})

func update(delta: float) -> void:
	if not is_instance_valid(view): return
	var mode := SubViewport.UPDATE_DISABLED
	if h.screen in ["combat_intro","combat_play"]: mode = SubViewport.UPDATE_ALWAYS
	view.render_target_update_mode = mode
	if h.screen!="combat_play": return
	elapsed += delta
	sync_rhythm()
	update_blast()
	trails = trails.filter(func(trail): return elapsed-trail.at<trail.duration+0.08)
	punch = maxf(0,punch-delta*6)
	shake = maxf(0,shake-delta*30)
	slap_flash = maxf(0,slap_flash-delta*5)
	impact_label_time = maxf(0,impact_label_time-delta)
	impact_time = maxf(0,impact_time-delta)
	for item in objects:
		item.flash = maxf(0,item.flash-delta*5)
		if item.kind=="dummy":
			update_character(item,delta)
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
		ring.node.scale = Vector3(1,0.18,1)*(0.42+ring.age*(10 if ring.heavy else 5))
		ring.node.material_override.albedo_color.a = clampf(1.0-ring.age/0.35,0,1)
		if ring.age>0.35: ring.node.queue_free()
	waves3d = waves3d.filter(func(ring): return is_instance_valid(ring.node) and not ring.node.is_queued_for_deletion())
	var selected := selected_target()
	var actor_target := impact_target if impact_time>0.15 else selected
	if actor_target>=0:
		var point: Vector3 = objects[actor_target].pos
		var destination := action_position(actor_target,point)
		avatar.position = avatar.position.lerp(destination,1-exp(-delta*19))
		face_target(point)
	elif charging or impact_time>0.0:
		var destination := action_position(-1,locked_point)
		avatar.position = avatar.position.lerp(destination,1-exp(-delta*19))
		face_target(locked_point)
	hammer.visible = actor_target<0 or objects[actor_target].kind!="dummy"
	update_floor_markers(selected)
	palm.visible = slap_flash>0
	if palm.visible:
		var side: float = objects[slapped_target].slap_side
		palm.position = hit3d+Vector3((1-slap_flash)*0.65*side,0,0.24)
		palm.rotation.y = slap_flash*2*side
	camera.position = base_camera+Vector3(sin(h.anim*83),cos(h.anim*91),0)*shake*0.018

func update_character(item: Dictionary,delta: float) -> void:
	var position: Vector3 = item.pos
	if show_type==Show.REBOUND and item.id==show_target and show_step==1:
		var moment := clampf(inverse_lerp(bounce_start,show_due,rhythm_time),0,1)
		var lift := sin(moment*PI)
		position += Vector3(lift*1.35,1.05*lift,-0.28*lift)
	item.visual.position = position
	if item.slap<=0: return
	item.slap = maxf(0,item.slap-delta*lerpf(2.9,1.55,item.slap_power))
	var life: float = item.slap
	var side: float = item.slap_side
	var strength: float = 1.0+item.slap_power*0.65
	var recoil := cos((1.0-life)*13.0)*life*side*strength
	var head: Node3D = item.visual.get_node("Head")
	head.rotation.z = recoil*0.46
	item.visual.rotation.z = recoil*0.19
	match item.variant:
		0:
			var turn := TAU*smoothstep(0.0,1.0,1.0-life)*side
			item.visual.rotation.y = turn if item.slap_power>0.25 and life>0 else recoil*0.44
		1:
			item.visual.position.y += sin(life*PI)*0.52*strength
		2:
			head.rotation.y = sin((1.0-life)*29.0)*life*0.62*strength
			item.visual.get_node("LeftArm").rotation.z = recoil*1.1
			item.visual.get_node("RightArm").rotation.z = -recoil*1.1

func input(event: InputEvent) -> void:
	if h.screen=="combat_play" and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_TAB:
		if active_input.is_empty():
			for step in range(1,objects.size()+1):
				var id := (target_id+step)%objects.size()
				if objects[id].alive:
					target_id = id
					double_target = -1
					break
		return
	super.input(event)

func pointer_down(point: Vector2,source: String) -> void:
	for button in h.buttons:
		if button.rect.has_point(point):
			action(button.id)
			return
	if h.screen!="combat_play" or not VIEW_RECT.has_point(point) or not active_input.is_empty(): return
	var hint_target := selected_target()
	if hint_target>=0 and action_hint_rect(hint_target).has_point(point):
		begin_hit(source,hint_target,objects[hint_target].pos)
		return
	var pixel := (point-VIEW_RECT.position)/VIEW_RECT.size*Vector2(view.size)
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var best := INF
	var id := -1
	for item in objects:
		if not item.alive: continue
		var location: Vector3 = item.visual.position
		var bounds := AABB(location-Vector3(item.size.x*0.5,0,item.size.z*0.5),item.size)
		var crossing = bounds.intersects_ray(origin,direction)
		if crossing is Vector3 and origin.distance_to(crossing)<best:
			best = origin.distance_to(crossing)
			id = item.id
	if id>=0:
		target_id = id
		begin_hit(source,id,objects[id].pos)
		return
	var ground = Plane(Vector3.UP,0.0).intersects_ray(origin,direction)
	if ground is Vector3 and absf(ground.x)<12.4 and absf(ground.z)<7.4:
		begin_hit(source,-1,ground)

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
	double_target = -1
	freeze_bodies(true)
	super.pause_game()

func resume_game() -> void:
	if h.screen!="combat_pause": return
	super.resume_game()
	freeze_bodies(false)

func action(id: String) -> void:
	if id=="combat_menu":
		if h.screen!="combat_intro":
			show_intro()
			build_shop()
	elif id=="combat_finish" and h.screen=="combat_play":
		finish(true)
	elif id!="mode":
		super.action(id)

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
	var key := "wreck3d_rhythm"
	var result := resolved+double_hits+timed_heavies+specials*3
	if result>int(h.records.get(key,0)): h.records[key] = result
	h.save_data()

func named_target() -> int:
	if slapped_target>=0 and objects[slapped_target].slap>0.0: return slapped_target
	if show_type==Show.REBOUND and show_step==1: return show_target
	var selected := selected_target()
	if selected>=0 and objects[selected].kind=="dummy": return selected
	return -1

func state() -> Dictionary:
	var props: Array = []
	for item in objects:
		var screen := project_to_screen(item.visual.position+Vector3.UP*item.size.y*0.5)
		props.append({"id":item.id,"kind":item.kind,"alive":item.alive,"hp":item.hp,"style":attack_style(item.id),"x":screen.x,"y":screen.y,"title":item.title})
	var named := named_target()
	return {"mode":"wreck3d","elapsed":elapsed,"cash":cash,"looted":looted,"slaps":slaps,"heavyHits":heavy_hits,
		"hits":total_smashes,"onBeat":resolved,"doubleHits":double_hits,"timedHeavies":timed_heavies,
		"rhythmTime":rhythm_time,"cueTime":cue_time(selected_target()),"doubleTarget":double_target,
		"section":section,"showType":show_type,"showTarget":show_target,"showStep":show_step,
		"showDue":show_due,"specials":specials,"blastPending":blast_queue.size(),
		"streak":streak,"bestStreak":max_streak,"broken":broken,"walls":wall_breaks,"chainHits":chain_hits,"destruction":destruction(),
		"charging":charging,"charge":charge_level(),"target":target_id,"won":won,"debris":physical.size(),"revealed":crates_revealed,
		"shopIdentity":shop_identity,"objects":props,"worldMeshes":stage.find_children("*","MeshInstance3D",true,false).size(),
		"nameTag":objects[named].title if named>=0 else ""}

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

func draw_trails() -> void:
	for trail in trails:
		var progress := clampf((elapsed-trail.at)/trail.duration,0,1)
		var from: Vector3 = trail.from+Vector3.UP*0.32
		var to: Vector3 = trail.to+Vector3.UP*0.32
		var previous := Vector2.ZERO
		for tick in range(8):
			var t := maxf(0,progress-0.27*(1.0-tick/7.0))
			var point := from.lerp(to,t)+Vector3.UP*sin(t*PI)*0.9
			var pixel := project_to_screen(point)
			var strength := (1.0-progress)*tick/7.0
			if tick>0 and VIEW_RECT.has_point(pixel) and VIEW_RECT.has_point(previous):
				h.draw_line(previous,pixel,Color(trail.tint,strength),1.0+5.0*strength,true)
			previous = pixel
		if VIEW_RECT.has_point(previous):
			h.draw_circle(previous,3.2+3.0*(1.0-progress),Color(trail.tint,1.0-progress))

func draw_intro() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color("1c162e"))
	h.center("商场拆迁王",Vector2(720,135),72,PEACH)
	var preview := Rect2(209,183,1022,521)
	h.draw_texture_rect(view.get_texture(),preview,false)
	h.rounded(preview,Color.TRANSPARENT,21,Color("63506e"))
	h.button("combat_start",Rect2(540,730,360,76),"开始打砸",true)

func draw_game() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color("1c162e"))
	h.text("午夜百货",Vector2(48,65),34,PEACH)
	h.button("sound",Rect2(1016,28,104,44),"静音" if h.muted else "声音 开",false,true)
	h.button("combat_pause",Rect2(1134,28,108,44),"Ⅱ 暂停",false,true)
	h.button("combat_finish",Rect2(1256,28,136,44),"收工",true,true)
	h.rounded(Rect2(48,91,1344,3),h.LINE,2)
	h.text("砸碎 %d 件" % broken,Vector2(52,134),22,PEACH)
	h.text("战利品 ¥%d" % cash,Vector2(224,134),22,GOLD)
	h.text("巴掌 %d 下" % slaps,Vector2(434,134),22,PEACH)
	h.text("准拍 %d" % resolved,Vector2(644,134),22,MINT)
	if streak>1: h.text("%d 连拍" % streak,Vector2(783,134),22,GOLD)
	if show_target>=0:
		h.text(SHOW_NAMES[show_type],Vector2(1136,134),22,SHOW_COLORS[show_type])
	draw_view()
	draw_trails()
	draw_impact()
	var named := named_target()
	if named>=0:
		var item: Dictionary = objects[named]
		var label := project_to_screen(item.visual.position+Vector3.UP*(item.size.y+0.18))
		label = label.clamp(VIEW_RECT.position+Vector2(70,28),VIEW_RECT.end-Vector2(70,12))
		h.rounded(Rect2(label+Vector2(-65,-22),Vector2(130,30)),PANEL_DARK,10)
		h.center(item.title,label,17,PEACH)
	if slap_flash>0.18:
		var offset := Vector2(75*objects[slapped_target].slap_side,34)
		var label := project_to_screen(hit3d)+offset
		label = label.clamp(VIEW_RECT.position+Vector2(70,46),VIEW_RECT.end-Vector2(70,16))
		h.center(impact_label,label,32,GOLD)
	if impact_label_time>0.0:
		var label := project_to_screen(hit3d)+Vector2(55,-60-(0.66-impact_label_time)*25)
		label = label.clamp(VIEW_RECT.position+Vector2(96,40),VIEW_RECT.end-Vector2(96,16))
		h.rounded(Rect2(label-Vector2(88,28),Vector2(176,36)),PANEL_DARK,10)
		h.center(impact_label,label,23,GOLD)
	draw_action_hint()
	h.center("点物件或按空格 · 脚边亮起时出手 · Tab 换目标",Vector2(720,881),18,h.MUTED)

func draw_action_hint() -> void:
	var id := selected_target()
	if id<0 and not charging: return
	var style := attack_style(id)
	var label := "亮时点"
	var tint := MINT
	if style=="hold":
		label = "按住蓄力"
		tint = GOLD
		if charging: label = "亮时松手" if charge_level()>0.0 else "蓄力中"
	elif style=="double":
		label = "再点一下  2/2" if id==double_target else "亮时点  1/2"
		tint = PINK
	if id==show_target:
		tint = SHOW_COLORS[show_type]
		match show_type:
			Show.RELAY: label = "换位接拍" if show_step==1 else "接力起拍"
			Show.REBOUND:
				if show_step==1: label = "落回时追拍"
			Show.DROP: label = "紫光时松手" if charging and charge_level()>0.0 else ("蓄力中" if charging else "按住低音箱")
	var plate := action_hint_rect(id)
	h.rounded(plate,PANEL_DARK,10)
	h.center(label,plate.position+Vector2(73,24),18,tint)
	if charging:
		var fill := clampf((elapsed-charge_start)/CHARGE_FULL,0,1)
		if fill>0.0:
			h.rounded(Rect2(plate.position+Vector2(12,30),Vector2(122*fill,3)),tint,1)

func action_hint_rect(id: int) -> Rect2:
	var point := locked_point if id<0 else action_position(id,objects[id].pos)
	var anchor := project_to_screen(point)+Vector2(17,31)
	anchor = anchor.clamp(VIEW_RECT.position+Vector2(84,34),VIEW_RECT.end-Vector2(84,13))
	return Rect2(anchor-Vector2(73,24),Vector2(146,32))

func draw_pause() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.9))
	h.buttons.clear()
	h.rounded(Rect2(450,255,540,390),h.PANEL,25,h.LINE)
	h.center("暂停",Vector2(720,350),38)
	h.button("combat_resume",Rect2(510,421,420,62),"继续打砸",true)
	h.button("combat_start",Rect2(510,505,200,56),"重新开始")
	h.button("combat_menu",Rect2(730,505,200,56),"返回首页")
	h.center("ESC / Enter 继续",Vector2(720,608),17,h.MUTED)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.92))
	h.buttons.clear()
	h.rounded(Rect2(290,175,860,565),h.PANEL,28,GOLD)
	h.center("打砸收工",Vector2(720,258),41,GOLD)
	h.center("¥ %d" % cash,Vector2(720,355),64,GOLD)
	h.center("砸碎 %d 件 · 连锁 %d 次 · 巴掌 %d 下" % [broken,chain_hits,slaps],Vector2(720,426),25,AQUA)
	h.center("准拍 %d 下 · 最长 %d 连拍" % [resolved,max_streak],Vector2(720,478),22)
	h.center("准拍重砸 %d 次 · 双拍 %d 次 · 段落特技 %d 次" % [timed_heavies,double_hits,specials],Vector2(720,532),19,h.MUTED)
	h.button("combat_start",Rect2(415,621,300,67),"再砸一遍！",true)
	h.button("combat_menu",Rect2(740,621,280,67),"返回首页")
