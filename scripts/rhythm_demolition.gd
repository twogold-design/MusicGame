extends "res://scripts/rhythm_counter.gd"

const ROOM_NAMES := ["下班后的客厅","不想加班办公室","最后一间街机厅"]
const ROOM_COLORS := [Color("343454"),Color("203e4b"),Color("3c2850")]
var objects: Array = []
var debris: Array = []
var shockwaves: Array = []
var demo_sounds: Dictionary = {}
var room := 0
var target_id := -1
var charging := false
var charge_start := 0.0
var locked_target := -1
var hero_pos := Vector2(350,570)
var impact_pos := Vector2(560,450)
var transition := 0.0
var broken := 0
var wall_breaks := 0
var chain_hits := 0
var weak_hits := 0
var total_smashes := 0
var last_strike := -99.0
var break_flash := 0.0

func _init(host) -> void:
	super(host)
	for id in ["hero","sofa","television","cabinet","desk","monitor","arcade","vending","plant"]:
		var path := "res://assets/demolition/%s.svg" % id
		if ResourceLoader.exists(path): art[id] = load(path)
	for id in ["wood","glass","metal","thump"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/demolition/%s.wav" % id)
		audio.volume_db = -5 if id!="thump" else -7
		audio.max_polyphony = 3
		h.add_child(audio)
		demo_sounds[id] = audio

func make_chart() -> Array:
	var chart := super.make_chart()
	for cue in chart:
		cue.type = "tap"
		cue.kind = "tap"
		cue.target = -1
	return chart

func start() -> void:
	super.start()
	objects.clear()
	debris.clear()
	shockwaves.clear()
	room = 0
	broken = 0
	wall_breaks = 0
	chain_hits = 0
	weak_hits = 0
	total_smashes = 0
	last_strike = -99
	transition = 0
	break_flash = 0
	hero_pos = Vector2(290,560)
	for r in range(3): build_room(r)
	target_id = pick_target()
	say("空格砸亮的家具，按住再松开砸更狠！",GOLD,5)

func stop() -> void:
	super.stop()
	charging = false
	locked_target = -1
	for audio in demo_sounds.values():
		audio.stop()
		audio.stream_paused = false

func add_object(r: int,kind: String,rect: Rect2,health: float,material: String) -> void:
	objects.append({"id":objects.size(),"room":r,"kind":kind,"rect":rect,"hp":health,"maxhp":health,"material":material,"alive":true,"flash":0.0})

func build_room(r: int) -> void:
	# Furniture has a fixed place in the room; it never travels toward a hit line.
	if r==0:
		add_object(r,"television",Rect2(279,306,150,150),2.4,"glass")
		add_object(r,"cabinet",Rect2(250,453,210,130),4.5,"wood")
		add_object(r,"sofa",Rect2(503,417,252,190),5.5,"wood")
		add_object(r,"plant",Rect2(812,365,132,170),1.8,"glass")
		add_object(r,"desk",Rect2(815,497,165,140),3.4,"wood")
		add_object(r,"cabinet",Rect2(1030,298,165,225),4.5,"wood")
		add_object(r,"plant",Rect2(1100,506,125,145),1.8,"glass")
	elif r==1:
		for x in [255,580,905]:
			add_object(r,"monitor",Rect2(x+25,324,128,136),2.4,"glass")
			add_object(r,"desk",Rect2(x,443,220,160),4.2,"wood")
		add_object(r,"cabinet",Rect2(1120,338,130,210),4.5,"metal")
		add_object(r,"plant",Rect2(740,525,115,140),1.8,"glass")
	else:
		for x in [260,465,670,875]: add_object(r,"arcade",Rect2(x,320,165,250),5.5,"metal")
		add_object(r,"vending",Rect2(1080,310,168,265),4.5,"glass")
		add_object(r,"desk",Rect2(535,552,190,120),3.4,"wood")
		add_object(r,"plant",Rect2(880,546,120,135),1.8,"glass")
	for x in [234,576,918]: add_object(r,"wall",Rect2(x,244,292,235),8.0,"wood")

func pick_target() -> int:
	for item in objects:
		if item.room==room and item.alive and item.kind!="wall": return item.id
	for item in objects:
		if item.room==room and item.alive: return item.id
	return -1

func valid_target(id: int) -> int:
	if id>=0 and id<objects.size() and objects[id].room==room and objects[id].alive: return id
	return pick_target()

func press(source := "test") -> void:
	if h.screen!="combat_play" or not active_input.is_empty(): return
	active_input = source
	charging = true
	charge_start = now()
	locked_target = valid_target(target_id)
	press_flash = 1
	strike("tap",locked_target)

func release(source := "test") -> void:
	if h.screen!="combat_play" or active_input!=source: return
	active_input = ""
	var duration := now()-charge_start
	if charging and duration>=0.28: strike("heavy",locked_target)
	charging = false
	locked_target = -1

func strike(kind: String,id: int) -> void:
	if now()-last_strike<0.14: return
	last_strike = now()
	var index := closest_cue()
	if index>=0 and cues[index].status==0:
		cues[index].kind = kind
		cues[index].target = id
		accept(index)
	else:
		weak_hits += 1
		apply_smash(id,kind,false)

func execute_cue(index: int) -> void:
	var cue: Dictionary = cues[index]
	if cue.status!=1: return
	cue.status = 2
	play_cue_sound(cue)
	resolved += 1
	streak += 1
	max_streak = maxi(max_streak,streak)
	perfect += 1
	timing_ms = int(float(cue.offset)*1000)
	apply_smash(int(cue.target),str(cue.kind),true)

func miss_cue(index: int,_early_release := false) -> void:
	if cues[index].status>=2: return
	cues[index].status = 3
	missed += 1
	streak = 0

func apply_smash(id: int,kind: String,on_beat: bool) -> void:
	total_smashes += 1
	if kind=="heavy": heavy_hits += 1
	id = valid_target(id)
	if id<0:
		# After clearing a room, keep smashing the rubble until the next music section.
		impact_pos = Vector2(720,580)
		for piece in debris:
			if piece.room==room and piece.pos.distance_to(impact_pos)<390:
				piece.rest = false
				piece.vel += Vector2(randf_range(-140,140),-randf_range(100,320))
		punch = 1
		shake = maxf(shake,9 if kind=="heavy" else 4)
		demo_sounds.thump.play()
		shockwaves.append({"pos":impact_pos,"radius":10.0,"life":0.35,"heavy":kind=="heavy"})
		say("清场！把残骸再震飞",GOLD,0.5)
		return
	var item: Dictionary = objects[id]
	impact_pos = item.rect.get_center()
	var heavy := kind=="heavy"
	var damage := (5.8 if heavy else 2.4) if on_beat else (2.4 if heavy else 0.55)
	punch = 1
	shake = maxf(shake,14 if heavy and on_beat else (7 if on_beat else 2))
	press_flash = 1
	demo_sounds[item.material].play()
	if on_beat: demo_sounds.thump.play()
	damage_object(id,damage,heavy or on_beat)
	var chain := heavy or (on_beat and streak%4==0)
	if chain:
		shockwaves.append({"pos":impact_pos,"radius":10.0,"life":0.45,"heavy":heavy})
		for neighbor in objects:
			if neighbor.id!=id and neighbor.alive and neighbor.room==room and neighbor.rect.get_center().distance_to(impact_pos)<(350 if heavy else 295):
				chain_hits += 1
				damage_object(neighbor.id,3.2 if heavy and on_beat else 1.4,true)
		say("整 片 震 碎！" if heavy else "连 锁 拆 除！",GOLD,0.6)
	elif on_beat: say("砸 中 重 拍！",GOLD,0.35)
	else: say("跟着底鼓砸，更带劲",h.MUTED,0.3)
	for n in range(20 if on_beat else 5):
		sparks.append({"pos":impact_pos,"vel":Vector2.from_angle(randf()*TAU)*randf_range(80,340),"life":0.32,"color":GOLD if on_beat else AQUA})
	target_id = valid_target(target_id)

func damage_object(id: int,damage: float,explosive: bool) -> void:
	var item: Dictionary = objects[id]
	if not item.alive: return
	var effective := minf(float(item.hp),damage)
	item.hp = maxf(0,item.hp-damage)
	item.flash = 1
	score += int(effective*30)
	if item.hp>0:
		spawn_chips(item,3)
		return
	item.alive = false
	broken += 1
	if item.kind=="wall": wall_breaks += 1
	score += 150
	break_flash = maxf(break_flash,0.15 if explosive else 0.05)
	var grid := 4 if explosive else 3
	var rect: Rect2 = item.rect
	for y in range(grid):
		for x in range(grid):
			var tile := rect.size/float(grid)
			var pos := rect.position+Vector2(x+0.5,y+0.5)*tile
			var away := (pos-impact_pos).normalized()
			debris.append({"pos":pos,"vel":away*randf_range(100,240)+Vector2(randf_range(-80,80),-randf_range(160,400)),"angle":0.0,"spin":randf_range(-7,7),"size":tile,"uv":Rect2(Vector2(x,y)/grid,Vector2.ONE/grid),"kind":item.kind,"room":room,"color":ROOM_COLORS[room].lightened(0.3) if item.kind=="wall" else Color.WHITE,"ground":randf_range(615,678),"rest":false})
	if debris.size()>650: debris = debris.slice(debris.size()-650)

func spawn_chips(item: Dictionary,count: int) -> void:
	for i in range(count):
		debris.append({"pos":item.rect.get_center()+Vector2(randf_range(-30,30),randf_range(-30,30)),"vel":Vector2(randf_range(-150,150),-randf_range(100,300)),"angle":randf()*TAU,"spin":randf_range(-8,8),"size":Vector2(randf_range(8,20),randf_range(8,20)),"uv":Rect2(0.2,0.2,0.15,0.15),"kind":item.kind,"room":room,"color":GOLD if item.material=="wood" else AQUA,"ground":randf_range(620,680),"rest":false})
	if debris.size()>650: debris = debris.slice(debris.size()-650)

func update(delta: float) -> void:
	if not h.screen.begins_with("combat") or h.screen=="combat_pause": return
	pulse = maxf(0,pulse-delta*5)
	punch = maxf(0,punch-delta*5)
	press_flash = maxf(0,press_flash-delta*6)
	shake = maxf(0,shake-delta*28)
	break_flash = maxf(0,break_flash-delta)
	feedback_timer = maxf(0,feedback_timer-delta)
	transition = maxf(0,transition-delta*1.5)
	for item in objects: item.flash = maxf(0,item.flash-delta*6)
	for piece in debris:
		if piece.room!=room or piece.rest: continue
		piece.vel.y += 820*delta
		piece.pos += piece.vel*delta
		piece.angle += piece.spin*delta
		if piece.pos.y>piece.ground:
			piece.pos.y = piece.ground
			piece.vel.y *= -0.34
			piece.vel.x *= 0.63
			piece.spin *= 0.6
			if absf(piece.vel.y)<25 and absf(piece.vel.x)<20: piece.rest = true
		if piece.pos.x<155 or piece.pos.x>1280:
			piece.pos.x = clampf(piece.pos.x,155,1280)
			piece.vel.x *= -0.5
	for ring in shockwaves:
		ring.radius += delta*(850 if ring.heavy else 600)
		ring.life -= delta
	shockwaves = shockwaves.filter(func(ring): return ring.life>0)
	for p in sparks:
		p.pos += p.vel*delta
		p.life -= delta
	sparks = sparks.filter(func(p): return p.life>0)
	var current := valid_target(locked_target if charging else target_id)
	if current>=0:
		var destination: Vector2 = objects[current].rect.get_center()+Vector2(-78,60)
		hero_pos = hero_pos.lerp(destination,1-exp(-delta*15))
	else: hero_pos = hero_pos.lerp(Vector2(625,620),1-exp(-delta*10))
	if h.screen!="combat_play": return
	elapsed = now()
	var next_room := clampi(int(floor((elapsed-INTRO)/10)),0,2)
	if next_room!=room:
		room = next_room
		target_id = pick_target()
		locked_target = target_id
		transition = 1
		shockwaves.clear()
		say(ROOM_NAMES[room]+" · 接着拆！",GOLD,2)
	var new_beat := int(floor((elapsed-INTRO)/BEAT))
	if new_beat!=beat:
		beat = new_beat
		pulse = 1
	resolve_cues()
	if elapsed>=END: finish(true)

func pause_game() -> void:
	if h.screen!="combat_play": return
	super.pause_game()
	charging = false
	locked_target = -1
	for audio in demo_sounds.values(): audio.stream_paused = true

func resume_game() -> void:
	super.resume_game()
	for audio in demo_sounds.values(): audio.stream_paused = false

func pointer_down(point: Vector2,source: String) -> void:
	for button in h.buttons:
		if button.rect.has_point(point):
			action(button.id)
			return
	if h.screen=="combat_play" and not charging:
		# Optional direct choice is part of the same click, never an extra required task.
		for item in objects:
			if item.room==room and item.alive and item.kind!="wall" and item.rect.has_point(point):
				target_id = item.id
				break
	press(source)

func finish(success: bool) -> void:
	if h.screen=="combat_result": return
	won = true
	h.screen = "combat_result"
	stop()
	var key := "demolition_"+("easy" if h.easy else "normal")
	if score>int(h.records.get(key,0)): h.records[key] = score
	h.save_data()

func destruction() -> float:
	var damage := 0.0
	var health := 0.0
	for item in objects:
		health += float(item.maxhp)
		damage += float(item.maxhp)-float(item.hp)
	return damage/maxf(1,health)

func state() -> Dictionary:
	var result := super.state()
	var props: Array = []
	for item in objects: props.append({"id":item.id,"room":item.room,"kind":item.kind,"hp":item.hp,"alive":item.alive,"x":item.rect.get_center().x,"y":item.rect.get_center().y})
	result.merge({"mode":"demolition","room":room,"target":target_id,"charging":charging,"broken":broken,"walls":wall_breaks,"debris":debris.size(),"chainHits":chain_hits,"weakHits":weak_hits,"smashes":total_smashes,"destruction":destruction(),"objects":props},true)
	return result

func draw_intro() -> void:
	h.brand()
	h.button("sound",Rect2(1020,28,174,44),"声音 关" if h.muted else "声音 开",false,true)
	h.button("combat_menu",Rect2(1212,28,180,44),"其他模式",false,true)
	h.rounded(Rect2(90,132,240,34),Color("343b2b"),16)
	h.text("BEAT WRECKER / 节拍拆迁王",Vector2(104,155),14,GOLD)
	h.text("今天，",Vector2(90,255),80)
	h.text("把压力砸个稀碎。",Vector2(90,359),70,GOLD)
	h.text("家具会裂，玻璃会爆，墙也能拆。",Vector2(96,420),25,AQUA)
	h.text("踩准鼓点，一锤震碎一大片。",Vector2(96,462),21,h.MUTED)
	icon("sofa",Rect2(1020,340,250,200))
	icon("television",Rect2(1120,175,135,135))
	icon("hero",Rect2(820,155,260,320))
	for i in range(12):
		var p := Vector2(1090+cos(i*4.3)*150,325+sin(i*2.7)*130)
		h.draw_colored_polygon(PackedVector2Array([p,p+Vector2(12,-9),p+Vector2(19,10)]),GOLD if i%2==0 else AQUA)
	h.rounded(Rect2(90,548,1260,135),h.PANEL,24,h.LINE)
	h.center("空格砸亮的家具 · 按住再松开，砸得更狠",Vector2(720,602),29,GOLD)
	h.center("也可 J / 点击屏幕。角色自动接近目标，尽管跟着底鼓砸！",Vector2(720,648),20,h.MUTED)
	h.button("combat_start",Rect2(435,744,360,70),"开拆！ →",true)
	h.button("mode",Rect2(820,744,230,70),"宽松节拍 ⇄" if h.easy else "精准节拍 ⇄")
	h.center("30秒 · 三间房 · 没有掉血失败，拍外也能砸",Vector2(720,864),18,h.MUTED)

func draw_room_shell() -> void:
	h.rounded(Rect2(150,207,1140,497),Color("121622"),24)
	h.rounded(Rect2(175,230,1090,325),ROOM_COLORS[room].darkened(0.5),12)
	h.draw_polygon(PackedVector2Array([Vector2(175,555),Vector2(1265,555),Vector2(1290,700),Vector2(150,700)]),PackedColorArray([ROOM_COLORS[room].darkened(0.28)]))
	for y in range(5): h.draw_line(Vector2(160,562+y*32),Vector2(1280,562+y*32),Color(1,1,1,0.06),2,true)
	for x in range(9): h.draw_line(Vector2(180+x*130,555),Vector2(150+x*145,700),Color(1,1,1,0.04),1,true)
	h.rounded(Rect2(198,251,40,215),Color(AQUA,0.1+pulse*0.12),10)
	h.rounded(Rect2(1210,251,30,215),Color(GOLD,0.06+pulse*0.1),10)
	var sign: String = ["HOME SWEET BOOM","NO MORE OVERTIME","INSERT COIN? NO. HAMMER."][room]
	h.center(sign,Vector2(720,224),14,Color(AQUA,0.6))

func draw_object(item: Dictionary) -> void:
	var rect: Rect2 = item.rect
	if not item.alive:
		if item.kind=="wall":
			h.rounded(rect.grow(-12),Color("080b13"),8)
			for i in range(5): h.draw_line(rect.position+Vector2(22+i*50,20),rect.position+Vector2(38+i*43,rect.size.y-15),Color(AQUA,0.1),3,true)
		return
	var jiggle := Vector2(sin(h.anim*85)*item.flash*5,0)
	if item.kind=="wall":
		h.rounded(Rect2(rect.position+jiggle,rect.size),ROOM_COLORS[room],8,Color(1,1,1,0.04))
		for x in range(4): h.draw_line(rect.position+Vector2(x*76,0),rect.position+Vector2(x*76,rect.size.y),Color(0,0,0,0.1),2,true)
	else:
		h.rounded(Rect2(rect.position+Vector2(8,rect.size.y-17),Vector2(rect.size.x-16,24)),Color(0,0,0,0.25),12)
		icon(item.kind,Rect2(rect.position+jiggle,rect.size),Color.WHITE.lerp(GOLD,item.flash*0.4))
	var cracks := int(ceil((1-float(item.hp)/float(item.maxhp))*5))
	for n in range(cracks):
		var center := rect.position+rect.size*Vector2(0.3+fposmod(item.id*0.17+n*0.29,0.45),0.2+fposmod(n*0.31,0.65))
		var points := PackedVector2Array([center+Vector2(-16,-23),center,center+Vector2(15,9),center+Vector2(3,28)])
		h.draw_polyline(points,Color("0a101b"),5,true)
		h.draw_polyline(points,Color(GOLD,0.5),1,true)

func draw_game() -> void:
	h.brand()
	h.button("sound",Rect2(1120,28,115,44),"静音" if h.muted else "声音 开",false,true)
	h.button("combat_pause",Rect2(1250,28,142,44),"Ⅱ 暂停",false,true)
	h.rounded(Rect2(48,91,1344,4),h.LINE,2)
	h.rounded(Rect2(48,91,1344*clampf((elapsed-INTRO)/30,0,1),4),GOLD,2)
	h.text(ROOM_NAMES[room]+"  /  %d·3" % (room+1),Vector2(159,159),24)
	h.center("破坏率 %d%%" % int(destruction()*100),Vector2(855,157),25,GOLD)
	h.text("%02d 秒" % int(ceil(maxf(0,END-maxf(INTRO,elapsed)))),Vector2(1168,157),22,h.MUTED)
	var offset := Vector2(sin(h.anim*97),cos(h.anim*81))*shake*0.4
	h.draw_set_transform(offset)
	draw_room_shell()
	for item in objects:
		if item.room==room and item.kind=="wall": draw_object(item)
	for item in objects:
		if item.room==room and item.kind!="wall": draw_object(item)
	var selected := valid_target(locked_target if charging else target_id)
	if selected>=0:
		var rect: Rect2 = objects[selected].rect
		var phase := fposmod(maxf(0,elapsed-INTRO),BEAT)/BEAT
		h.rounded(rect.grow(5+pulse*4),Color(GOLD,0.02),14,Color(GOLD,0.5+pulse*0.5))
		h.draw_arc(rect.get_center(),40+(1-phase)*50,0,TAU,60,Color(GOLD,0.55),3,true)
		if charging:
			h.draw_arc(rect.get_center(),65,-PI/2,-PI/2+TAU*minf(1,(now()-charge_start)/0.5),64,GOLD,7,true)
	for piece in debris:
		if piece.room!=room: continue
		h.draw_set_transform(piece.pos+offset,piece.angle)
		var rect := Rect2(-piece.size/2,piece.size)
		if art.has(piece.kind) and piece.size.x>13:
			var tex: Texture2D = art[piece.kind]
			var region := Rect2(piece.uv.position*tex.get_size(),piece.uv.size*tex.get_size())
			h.draw_texture_rect_region(tex,rect,region,Color.WHITE)
		else: h.draw_rect(rect,piece.color)
	h.draw_set_transform(offset)
	for ring in shockwaves: h.draw_arc(ring.pos,ring.radius,0,TAU,80,Color(GOLD,minf(0.9,ring.life*2)),5,true)
	for p in sparks: h.draw_circle(p.pos,4,Color(p.color,minf(1,p.life*4)))
	icon("hero",Rect2(hero_pos-Vector2(70,112)+Vector2(punch*12,-punch*10),Vector2(140,155)))
	if punch>0:
		h.draw_arc(impact_pos,35+(1-punch)*100,-2.6,0.6,48,Color(GOLD,punch),8,true)
		h.draw_line(hero_pos-Vector2(0,55),impact_pos,Color(GOLD,punch*0.6),11,true)
	if break_flash>0: h.rounded(Rect2(150,207,1140,497),Color(GOLD,break_flash),24)
	h.draw_set_transform(Vector2.ZERO)
	if transition>0:
		h.draw_rect(Rect2(150,207,1140,497),Color(ROOM_COLORS[room],transition*0.7))
	if feedback_timer>0: h.center(feedback,Vector2(720,747),26,feedback_color)
	if elapsed<INTRO:
		h.center("听四拍… %d" % clampi(5+beat,1,4),Vector2(720,808),27,GOLD)
	else:
		h.center("松开，重砸！" if charging and now()-charge_start>=0.28 else "空格 / J / 点击：砸！   按住再松开：重砸",Vector2(720,808),23,GOLD if charging else h.INK)
	h.center("亮起的家具自动选好 · 跟着底鼓，尽管砸",Vector2(720,864),16,h.MUTED)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.93))
	h.buttons.clear()
	h.rounded(Rect2(300,170,840,570),h.PANEL,28,GOLD)
	h.center("压力，砸碎了！",Vector2(720,260),44,GOLD)
	icon("hero",Rect2(365,330,220,250))
	h.text("破坏率 %d%%" % int(destruction()*100),Vector2(640,372),39,GOLD)
	h.text("砸碎 %d 件 · 拆墙 %d 面" % [broken,wall_breaks],Vector2(646,429),23)
	h.text("连锁波及 %d 次 · 重砸 %d 次" % [chain_hits,heavy_hits],Vector2(646,475),21,AQUA)
	h.text("接上 %d 拍 · 最长 %d 连拍" % [resolved,max_streak],Vector2(646,518),20,h.MUTED)
	h.text("拆迁得分 %d" % score,Vector2(646,559),23,GOLD)
	h.button("combat_start",Rect2(420,635,300,65),"再拆一遍！",true)
	h.button("combat_menu",Rect2(744,635,270,65),"其他模式")

func draw_pause() -> void:
	super.draw_pause()
	h.draw_rect(Rect2(490,362,460,36),h.PANEL)
	h.center("破坏现场和音乐已暂停",Vector2(720,387),20,h.MUTED)
