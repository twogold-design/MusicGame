extends RefCounted

const ARENA := Rect2(237,174,966,568)
const BEAT := 0.5
const INTRO := 2.0
const END := 32.0
const RED := Color("ff628e")
const GOLD := Color("e4ff7b")
const AQUA := Color("67f1ed")
var h
var art: Dictionary = {}
var music: AudioStreamPlayer
var sounds: Dictionary = {}
var elapsed := 0.0
var beat := -5
var player := Vector2(720,500)
var aim := Vector2(1100,450)
var move_keys: Dictionary = {}
var move_dir := Vector2.ZERO
var enemies: Array = []
var shots: Array = []
var bullets: Array = []
var sparks: Array = []
var rings: Array = []
var next_id := 0
var hp := 5
var max_hp := 5
var immune_until := -1.0
var dash_until := -1.0
var dash_ready := 0.0
var dash_dir := Vector2.RIGHT
var dash_total := 0
var dash_cancelled := 0
var last_shot := -99.0
var last_perfect_beat := -99
var streak := 0
var max_streak := 0
var perfect_shots := 0
var normal_shots := 0
var kills := 0
var score := 0
var overdrive_until := -1.0
var overdrives := 0
var boss_defeated := false
var pulse := 0.0
var recoil := 0.0
var shake := 0.0
var hurt_flash := 0.0
var feedback := ""
var feedback_color := AQUA
var feedback_timer := 0.0
var won := false
var touch_id := -1
var touch_dir := Vector2.ZERO
var cursor_visible := false
var restore_cursor := Input.MOUSE_MODE_VISIBLE
var cues: Array = []
var melody_players: Array[AudioStreamPlayer] = []
var traces: Array = []
var next_cue := 0
var missed_cues := 0
var wrong_inputs := 0
var on_time := 0
var good_actions := 0
var last_resolved := -1
var prepared_flash := 0.0
var last_reject := -99.0
var timing_ms := 0
var phrase_bounce := 0.0
var response_players: Array[AudioStreamPlayer] = []
var response_until: Array[float] = [-1.0,-1.0]

func _init(host) -> void:
	h = host
	for id in ["player","enemy","boss","hero"]:
		var path: String = "res://assets/combat/"+id+".svg"
		if ResourceLoader.exists(path): art[id] = load(path)
	music = AudioStreamPlayer.new()
	music.volume_db = -3
	h.add_child(music)
	for id in ["shot","perfect","dash","hurt","kill"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/combat/"+id+".wav")
		audio.volume_db = -3 if id=="perfect" else 0
		audio.max_polyphony = 4
		h.add_child(audio)
		sounds[id] = audio
	for i in range(8):
		var note := AudioStreamPlayer.new()
		note.stream = load("res://assets/audio/groove/shot_%d.wav" % i)
		note.volume_db = -1
		note.max_polyphony = 2
		h.add_child(note)
		melody_players.append(note)
	sounds.dash.stream = load("res://assets/audio/groove/dash.wav")
	var miss := AudioStreamPlayer.new()
	miss.stream = load("res://assets/audio/groove/miss.wav")
	miss.volume_db = -6
	h.add_child(miss)
	sounds.miss = miss
	for i in range(2):
		var response := AudioStreamPlayer.new()
		response.stream = load("res://assets/audio/groove/response_%s.wav" % ("even" if i==0 else "odd"))
		response.volume_db = -80
		h.add_child(response)
		response_players.append(response)

func show_intro() -> void:
	stop()
	h.music.stop()
	h.adventure.stop_audio()
	h.screen = "combat_intro"

func start() -> void:
	stop()
	h.music.stop()
	h.adventure.stop_audio()
	elapsed = 0
	beat = -5
	player = Vector2(720,500)
	aim = Vector2(1100,450)
	move_keys.clear()
	move_dir = Vector2.ZERO
	touch_dir = Vector2.ZERO
	touch_id = -1
	enemies.clear()
	shots.clear()
	bullets.clear()
	sparks.clear()
	rings.clear()
	next_id = 0
	max_hp = 5 if h.easy else 4
	hp = max_hp
	immune_until = -1
	dash_until = -1
	dash_ready = 0
	dash_total = 0
	dash_cancelled = 0
	last_shot = -99
	last_perfect_beat = -99
	streak = 0
	max_streak = 0
	perfect_shots = 0
	normal_shots = 0
	kills = 0
	score = 0
	overdrive_until = -1
	overdrives = 0
	boss_defeated = false
	won = false
	pulse = 0
	shake = 0
	hurt_flash = 0
	cues = make_chart()
	traces.clear()
	next_cue = 0
	missed_cues = 0
	wrong_inputs = 0
	on_time = 0
	good_actions = 0
	last_resolved = -1
	prepared_flash = 0
	last_reject = -99
	timing_ms = 0
	say("前八拍：射、射、射、射。跟上底鼓。",GOLD,5)
	music.stream = load("res://assets/audio/groove/bed.wav")
	music.stream_paused = false
	music.play()
	for i in range(2):
		response_players[i].volume_db = -80
		response_players[i].stream_paused = false
		response_players[i].play()
		response_until[i] = -1
	h.screen = "combat_play"

func stop() -> void:
	music.stop()
	music.stream_paused = false
	for audio in melody_players:
		audio.stop()
		audio.stream_paused = false
	for audio in response_players:
		audio.stop()
		audio.stream_paused = false
	for audio in sounds.values():
		audio.stop()
		audio.stream_paused = false
	move_keys.clear()
	move_dir = Vector2.ZERO
	touch_dir = Vector2.ZERO
	touch_id = -1

func audio_time() -> float:
	return maxf(0,music.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency())

func now() -> float:
	return maxf(elapsed,audio_time())

func make_chart() -> Array:
	var chart: Array = []
	for b in range(60):
		chart.append({"beat":float(b),"time":INTRO+b*BEAT,"type":"dash" if b>=8 and b%4==2 else "shot","status":0,"offset":0.0,"dir":Vector2.ZERO,"aim":Vector2.ZERO,"sample":((b/4)%4)*2+b%2,"sound":false})
		if b in [43,47,51,55]:
			chart.append({"beat":b+0.5,"time":INTRO+(b+0.5)*BEAT,"type":"shot","status":0,"offset":0.0,"dir":Vector2.ZERO,"aim":Vector2.ZERO,"sample":((b/4)%4)*2,"sound":false})
	return chart

func window_early() -> float:
	return 0.15 if h.easy else 0.11

func window_late() -> float:
	return 0.14 if h.easy else 0.10

func request_action(kind: String) -> void:
	if h.screen!="combat_play": return
	var raw := now()
	var time: float = raw-h.offset_ms/1000.0
	if time<INTRO-window_early() or time>=END: return
	var index := -1
	var nearest := INF
	# Lock to the nearest cue, including consumed cues: spamming cannot consume
	# a later overlapping cue while the player is still on the current beat.
	for i in range(cues.size()):
		var difference := time-float(cues[i].time)
		if difference < -window_early() or difference > window_late(): continue
		if absf(difference)<nearest:
			nearest = absf(difference)
			index = i
	if index<0:
		reject_input("早了 / 晚了 · 等光圈合拢",raw)
		return
	var cue: Dictionary = cues[index]
	if cue.type!=kind:
		reject_input("这一拍要闪！按空格" if cue.type=="dash" else "这一拍要射！点左键",raw)
		return
	if cue.status!=0: return
	cue.offset = time-float(cue.time)
	cue.aim = aim
	cue.dir = current_direction()
	cue.status = 1
	prepared_flash = 1
	schedule_cue_audio()
	if raw<float(cue.time):
		say("已准备 · 鼓点落下就出手",AQUA,0.2)
	else: execute_cue(index)

func reject_input(message: String,time: float) -> void:
	if time-last_reject<0.12: return
	last_reject = time
	wrong_inputs += 1
	normal_shots += 1
	streak = 0
	sounds.miss.play()
	say(message,h.MUTED,0.45)

func current_direction() -> Vector2:
	var x := int(move_keys.has(KEY_D) or move_keys.has(KEY_RIGHT))-int(move_keys.has(KEY_A) or move_keys.has(KEY_LEFT))
	var y := int(move_keys.has(KEY_S) or move_keys.has(KEY_DOWN))-int(move_keys.has(KEY_W) or move_keys.has(KEY_UP))
	var direction := Vector2(x,y).normalized()
	if touch_dir.length()>0.1: direction = touch_dir
	if direction.length()<0.1: direction = (aim-player).normalized()
	return direction if direction.length()>0.1 else Vector2.RIGHT

func resolve_cues() -> void:
	schedule_cue_audio()
	var time: float = elapsed-h.offset_ms/1000.0
	for i in range(cues.size()):
		var cue: Dictionary = cues[i]
		if cue.status==1 and elapsed>=float(cue.time): execute_cue(i)
		elif cue.status==0 and time>float(cue.time)+window_late():
			cue.status = 3
			missed_cues += 1
			streak = 0
			if cue.type=="dash": hurt()
			say("漏了一拍 · 看下一个动作接回来",h.MUTED,0.4)
	next_cue = 0
	while next_cue<cues.size() and cues[next_cue].status>=2: next_cue += 1

func schedule_cue_audio() -> void:
	# The two response stems started on the same mix frame as the backing track.
	# Opening a silent gap before a queued note preserves its sample-accurate
	# onset; AudioStreamPlayer.play() itself is not a sample scheduler.
	var time := now()
	for channel in range(2):
		if time>response_until[channel]: response_players[channel].volume_db = -80
	for i in range(cues.size()):
		var cue: Dictionary = cues[i]
		if cue.status!=1 or cue.sound: continue
		if time<float(cue.time):
			var channel := i%2
			response_players[channel].volume_db = -1
			response_until[channel] = float(cue.time)+0.25
			cue.sound = true
		else: play_cue_sound(cue)

func play_cue_sound(cue: Dictionary) -> void:
	if cue.sound: return
	cue.sound = true
	if cue.type=="shot": melody_players[int(cue.sample)].play()
	else: sounds.dash.play()

func execute_cue(index: int) -> void:
	var cue: Dictionary = cues[index]
	if cue.status!=1: return
	cue.status = 2
	streak = streak+1 if last_resolved==index-1 else 1
	last_resolved = index
	max_streak = maxi(max_streak,streak)
	timing_ms = int(cue.offset*1000)
	on_time += 1
	var precise := absf(float(cue.offset))<=0.065
	play_cue_sound(cue)
	if not precise: good_actions += 1
	score += 100 if precise else 70
	if streak%8==0:
		overdrive_until = now()+4*BEAT
		overdrives += 1
		say("合上节拍！四拍狂热",GOLD,1)
	else: say("PERFECT  ·  " + ("砰！" if cue.type=="shot" else "闪！") if precise else "接上了！",GOLD if precise else AQUA,0.3)
	if cue.type=="dash": perform_dash(cue)
	else: perform_shot(cue)
	phrase_bounce = 1

func perform_shot(cue: Dictionary) -> void:
	last_shot = now()
	last_perfect_beat = int(round(cue.beat))
	perfect_shots += 1
	var point: Vector2 = aim if now()-float(cue.time)<0.07 else cue.aim
	var direction := (point-player).normalized()
	if direction.length()<0.1: direction = Vector2.RIGHT
	var count := 3 if now()<overdrive_until else 1
	recoil = 1
	shake = maxf(shake,4)
	rings.append({"pos":player,"radius":20.0,"speed":220.0,"life":0.24,"color":GOLD})
	for i in range(count):
		var dir := direction.rotated((i-(count-1)/2.0)*0.17)
		var endpoint := player+dir*1100
		traces.append({"from":player+dir*25,"to":endpoint,"life":0.17,"color":GOLD})
		for enemy in enemies:
			if enemy.hp<=0: continue
			var closest := Geometry2D.get_closest_point_to_segment(enemy.pos,player,endpoint)
			if closest.distance_to(enemy.pos)<enemy.radius+17:
				enemy.hp -= 6
				enemy.flash = 1
				score += 30
				burst(enemy.pos,GOLD,13,190)
	reap_enemies()
	burst(player+direction*35,GOLD,10,100)

func perform_dash(cue: Dictionary) -> void:
	var time := now()
	dash_dir = current_direction() if current_direction().length()>0.1 else cue.dir
	dash_until = time+0.17
	dash_ready = time+0.6
	immune_until = maxf(immune_until,time+0.3)
	dash_total += 1
	var survivors: Array = []
	for bullet in bullets:
		if player.distance_to(bullet.pos)<180:
			burst(bullet.pos,AQUA,5,100)
			dash_cancelled += 1
			score += 30
		else: survivors.append(bullet)
	bullets = survivors
	rings.append({"pos":player,"radius":25.0,"speed":600.0,"life":0.3,"color":AQUA})

func update(delta: float) -> void:
	if not h.screen.begins_with("combat"): return
	if h.screen=="combat_pause": return
	pulse = maxf(0,pulse-delta*5)
	recoil = maxf(0,recoil-delta*7)
	shake = maxf(0,shake-delta*30)
	hurt_flash = maxf(0,hurt_flash-delta*3)
	feedback_timer = maxf(0,feedback_timer-delta)
	prepared_flash = maxf(0,prepared_flash-delta*4)
	phrase_bounce = maxf(0,phrase_bounce-delta*6)
	for line in traces: line.life -= delta
	traces = traces.filter(func(line): return line.life>0)
	for p in sparks:
		p.pos += p.vel*delta
		p.vel *= pow(0.12,delta)
		p.life -= delta
	sparks = sparks.filter(func(p): return p.life>0)
	for r in rings:
		r.radius += r.speed*delta
		r.life -= delta
	rings = rings.filter(func(r): return r.life>0)
	if h.screen!="combat_play": return
	elapsed = now()
	var target := int(floor((elapsed-INTRO)/BEAT))
	while beat<target and h.screen=="combat_play":
		on_beat(beat+1)
	if h.screen!="combat_play": return
	resolve_cues()
	var x := int(move_keys.has(KEY_D) or move_keys.has(KEY_RIGHT))-int(move_keys.has(KEY_A) or move_keys.has(KEY_LEFT))
	var y := int(move_keys.has(KEY_S) or move_keys.has(KEY_DOWN))-int(move_keys.has(KEY_W) or move_keys.has(KEY_UP))
	move_dir = Vector2(x,y).normalized()
	if touch_dir.length()>0.1: move_dir = touch_dir
	var velocity := dash_dir*1050 if elapsed<dash_until else move_dir*315
	player += velocity*delta
	player = player.clamp(ARENA.position+Vector2(28,28),ARENA.end-Vector2(28,28))
	if elapsed<dash_until:
		sparks.append({"pos":player,"vel":Vector2.ZERO,"life":0.2,"color":AQUA,"size":14.0})
	for enemy in enemies:
		enemy.flash = maxf(0,enemy.flash-delta*6)
		if not enemy.boss:
			var difference: Vector2 = player-enemy.pos
			if difference.length()>240: enemy.pos += difference.normalized()*24*delta
		if player.distance_to(enemy.pos)<enemy.radius+16: hurt()
	step_projectiles(delta)
	if hp<=0: finish(false)

func on_beat(index: int) -> void:
	beat = index
	pulse = 1
	if beat<0: return
	if beat>=60:
		resolve_cues()
		finish(true)
		return
	# Keep a target on each beat; sparse waves left most of the music empty.
	if beat<40 and enemies.size()<8:
		spawn_enemy(false)
		if beat==0: spawn_enemy(false)
	if beat==40:
		spawn_enemy(true)
		shake = 9
		say("最后10秒！击倒音箱王。",GOLD,3)
	if beat==6: say("下一小节：射、射、闪、射。闪用空格！",AQUA,2)
	if beat==42: say("听最后一拍的哒哒！准备半拍双击。",GOLD,2)
	if beat>=8 and beat%4==2:
		rings.append({"pos":ARENA.get_center(),"radius":20.0,"speed":1800.0,"life":0.4,"color":RED})
	if beat>=44 and beat%8==4 and enemies.size()<4: spawn_enemy(false)
	if beat%4==3:
		for enemy in enemies:
			enemy.lock = (player-enemy.pos).normalized()
			enemy.armed = true
	if beat>=4 and beat%4==0:
		for enemy in enemies:
			if not enemy.armed: continue
			var count := 5 if enemy.boss else (3 if beat>=32 else 1)
			for i in range(count):
				var angle := (i-(count-1)/2.0)*(0.19 if enemy.boss else 0.15)
				var direction: Vector2 = enemy.lock.rotated(angle)
				bullets.append({"pos":enemy.pos+direction*enemy.radius,"vel":direction*(180 if h.easy else 220),"life":7.0,"radius":8.0 if enemy.boss else 7.0})
			enemy.armed = false
			rings.append({"pos":enemy.pos,"radius":enemy.radius,"speed":90.0,"life":0.25,"color":RED})

func spawn_enemy(boss: bool) -> void:
	var positions: Array[Vector2] = [Vector2(1110,430),Vector2(330,400),Vector2(720,245),Vector2(960,640),Vector2(450,630),Vector2(1040,265),Vector2(425,270),Vector2(720,650)]
	var pos: Vector2 = Vector2(720,270) if boss else positions[(next_id)%positions.size()]
	if not boss and pos.distance_to(player)<170:
		for candidate in positions:
			if candidate.distance_to(player)>pos.distance_to(player): pos = candidate
	var health := 60 if boss else 6
	enemies.append({"id":next_id,"pos":pos,"hp":health,"maxhp":health,"boss":boss,"radius":52.0 if boss else 26.0,"flash":1.0,"armed":false,"lock":Vector2.DOWN})
	next_id += 1
	rings.append({"pos":pos,"radius":75.0 if boss else 45.0,"speed":-60.0,"life":0.5,"color":RED})

func shoot() -> void:
	request_action("shot")

func dash() -> void:
	request_action("dash")

func step_projectiles(delta: float) -> void:
	reap_enemies()
	for bullet in bullets:
		var previous: Vector2 = bullet.pos
		bullet.pos += bullet.vel*delta
		bullet.life -= delta
		var closest := Geometry2D.get_closest_point_to_segment(player,previous,bullet.pos)
		if closest.distance_to(player)<16+bullet.radius:
			if elapsed<dash_until:
				burst(bullet.pos,AQUA,4,70)
				dash_cancelled += 1
			else: hurt()
			bullet.life = -1
	bullets = bullets.filter(func(b): return b.life>0 and ARENA.grow(30).has_point(b.pos))

func reap_enemies() -> void:
	for enemy in enemies:
		if enemy.hp<=0:
			kills += 1
			score += 1500 if enemy.boss else 200
			if enemy.boss:
				boss_defeated = true
				bullets.clear()
				say("音箱王击破！继续跟住最后几拍。",GOLD,2)
			# The player's melodic shot supplies the kill sound on the beat.
			burst(enemy.pos,GOLD if enemy.boss else AQUA,40 if enemy.boss else 20,260)
			rings.append({"pos":enemy.pos,"radius":10.0,"speed":250.0,"life":0.5,"color":GOLD})
			shake = maxf(shake,8 if enemy.boss else 4)
	enemies = enemies.filter(func(e): return e.hp>0)

func hurt() -> void:
	if elapsed<6.0 or elapsed<immune_until or h.screen!="combat_play": return
	hp -= 1
	immune_until = elapsed+1
	hurt_flash = 0.6
	shake = 10
	streak = 0
	sounds.hurt.play()
	say("闪开！空格冲刺有短暂无敌",RED,1)

func burst(pos: Vector2,color: Color,count: int,speed: float) -> void:
	for i in range(count):
		var angle := randf()*TAU
		sparks.append({"pos":pos,"vel":Vector2.from_angle(angle)*randf_range(speed*0.3,speed),"life":randf_range(0.18,0.45),"color":color,"size":randf_range(2,6)})
	if sparks.size()>350: sparks = sparks.slice(sparks.size()-350)

func say(value: String,color: Color,seconds: float) -> void:
	feedback = value
	feedback_color = color
	feedback_timer = seconds

func finish(success: bool) -> void:
	if h.screen=="combat_result": return
	won = success
	h.screen = "combat_result"
	move_keys.clear()
	touch_dir = Vector2.ZERO
	if success: score += hp*150
	else: stop()
	var key: String = "groove_"+("easy" if h.easy else "normal")
	if score>int(h.records.get(key,0)): h.records[key] = score
	h.save_data()

func pause_game() -> void:
	if h.screen!="combat_play": return
	music.stream_paused = true
	for audio in melody_players: audio.stream_paused = true
	for audio in response_players: audio.stream_paused = true
	sounds.dash.stream_paused = true
	h.screen = "combat_pause"
	move_keys.clear()
	move_dir = Vector2.ZERO
	touch_dir = Vector2.ZERO
	touch_id = -1

func resume_game() -> void:
	move_keys.clear()
	move_dir = Vector2.ZERO
	touch_dir = Vector2.ZERO
	touch_id = -1
	music.stream_paused = false
	for audio in melody_players: audio.stream_paused = false
	for audio in response_players: audio.stream_paused = false
	sounds.dash.stream_paused = false
	h.screen = "combat_play"

func input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		h.hover = h.get_global_mouse_position()
		aim = h.hover
	if event is InputEventKey and not event.echo:
		if event.physical_keycode in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
			if event.pressed and h.screen=="combat_play": move_keys[event.physical_keycode] = true
			elif not event.pressed: move_keys.erase(event.physical_keycode)
		if event.pressed:
			if event.keycode==KEY_ESCAPE:
				if h.screen=="combat_play": pause_game()
				elif h.screen=="combat_pause": resume_game()
				else: action("combat_menu")
			elif event.keycode==KEY_ENTER:
				if h.screen in ["combat_intro","combat_result"]: start()
				elif h.screen=="combat_pause": resume_game()
			elif event.keycode==KEY_SPACE: dash()
			elif event.physical_keycode==KEY_J:
				auto_aim()
				shoot()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		pointer(h.get_global_mouse_position(),false)
	if event is InputEventScreenTouch:
		var point: Vector2 = h.get_canvas_transform().affine_inverse()*event.position
		if event.pressed:
			if h.screen=="combat_play" and point.distance_to(Vector2(126,650))<110:
				touch_id = event.index
				touch_dir = ((point-Vector2(126,650))/65).limit_length(1)
			else: pointer(point,true)
		elif event.index==touch_id:
			touch_dir = Vector2.ZERO
			touch_id = -1
	if event is InputEventScreenDrag and event.index==touch_id:
		var point: Vector2 = h.get_canvas_transform().affine_inverse()*event.position
		touch_dir = ((point-Vector2(126,650))/65).limit_length(1)

func pointer(point: Vector2,touch: bool) -> void:
	for b in h.buttons:
		if b.rect.has_point(point):
			action(b.id)
			return
	if h.screen!="combat_play": return
	if touch: auto_aim()
	else: aim = point
	shoot()

func auto_aim() -> void:
	var closest := INF
	for enemy in enemies:
		var distance := player.distance_to(enemy.pos)
		if distance<closest:
			closest = distance
			aim = enemy.pos

func action(id: String) -> void:
	if id=="combat_start": start()
	elif id=="combat_menu":
		stop()
		h.screen = "menu"
	elif id=="combat_pause": pause_game()
	elif id=="combat_resume": resume_game()
	elif id=="combat_fire":
		auto_aim()
		shoot()
	elif id=="combat_dash": dash()
	elif id=="mode": h.action("mode")
	elif id=="sound": h.action("sound")

func state() -> Dictionary:
	var targets: Array = []
	var actions: Array = []
	for enemy in enemies: targets.append({"id":enemy.id,"x":enemy.pos.x,"y":enemy.pos.y,"hp":enemy.hp,"boss":enemy.boss})
	for cue in cues: actions.append({"time":cue.time,"type":cue.type,"status":cue.status,"beat":cue.beat})
	return {"elapsed":elapsed,"beat":beat,"player":[player.x,player.y],"hp":hp,"score":score,"streak":streak,"maxStreak":max_streak,"perfect":perfect_shots,"normal":normal_shots,"kills":kills,"overdrives":overdrives,"dashes":dash_total,"dashCancelled":dash_cancelled,"dashReady":dash_ready,"bossDefeated":boss_defeated,"won":won,"enemies":targets,"bullets":bullets.size(),"cues":actions,"missed":missed_cues,"wrong":wrong_inputs,"resolved":on_time,"good":good_actions,"timingMs":timing_ms}

func icon(id: String,rect: Rect2,tint := Color.WHITE) -> void:
	if art.has(id): h.draw_texture_rect(art[id],rect,false,tint)

func render() -> void:
	if h.screen=="combat_intro":
		draw_intro()
		return
	draw_game()
	if h.screen=="combat_pause": draw_pause()
	elif h.screen=="combat_result": draw_result()

func draw_intro() -> void:
	h.brand()
	h.button("sound",Rect2(1020,28,174,44),"声音 关" if h.muted else "声音 开",false,true)
	h.button("combat_menu",Rect2(1212,28,180,44),"其他模式",false,true)
	h.rounded(Rect2(65,128,266,32),Color("29372c"),16)
	h.text("射 · 射 · 闪 · 射  /  120 BPM",Vector2(78,150),14,GOLD)
	h.text("让每一枪，",Vector2(64,245),68)
	h.text("打在鼓点上。",Vector2(64,332),68,GOLD)
	h.text("砰、砰、闪、砰！打出你的旋律。",Vector2(68,391),23,AQUA)
	h.text("前八拍练射击，随后跟着乐句射击和闪避。",Vector2(68,432),19,h.MUTED)
	h.text("提前一点按也可以，出手会对齐下一拍。",Vector2(68,466),19,h.MUTED)
	icon("hero",Rect2(664,128,728,437))
	var titles := ["01  射击就是演奏","02  第三拍闪避","03  看清后面的乐句"]
	var lines := ["左键 / J 跟拍，WASD自由走位","闪字到线时按空格，穿过全场音波","提示提前出现，最后加入哒哒双击"]
	for i in range(3):
		var x := 65+i*446
		h.rounded(Rect2(x,594,418,133),h.PANEL,18,h.LINE)
		h.text(titles[i],Vector2(x+22,637),26,h.COLORS[i])
		h.text(lines[i],Vector2(x+22,680),17,h.MUTED)
	h.button("combat_start",Rect2(487,769,345,65),"戴好耳机，开战  →",true)
	h.button("mode",Rect2(850,769,238,65),"轻松 · 5心 ⇄" if h.easy else "挑战 · 4心 ⇄")
	h.center("拍外点击没有子弹 · 连续接上八个动作进入狂热 · 触屏：左侧移动，右侧射 / 闪",Vector2(720,879),15,h.MUTED)

func draw_game() -> void:
	h.brand()
	h.center("GROOVE BLASTER",Vector2(720,54),26,GOLD)
	h.button("sound",Rect2(1123,28,110,44),"静音" if h.muted else "声音 开",false,true)
	h.button("combat_pause",Rect2(1245,28,147,44),"Ⅱ  暂停",false,true)
	var progress := clampf((elapsed-INTRO)/30.0,0,1)
	h.rounded(Rect2(48,91,1344,4),h.LINE,2)
	h.rounded(Rect2(48,91,1344*progress,4),GOLD,2)
	h.text("120 BPM / %s" % ("轻松" if h.easy else "挑战"),Vector2(52,135),17,h.MUTED)
	h.center("前八拍：射 / 射 / 射 / 射" if beat<8 else ("射 / 射 / 闪 / 射射！" if beat>=40 and beat<56 else "射 / 射 / 闪 / 射"),Vector2(720,138),25,GOLD)
	h.text("剩余 %02d 秒" % int(ceil(maxf(0,END-maxf(INTRO,elapsed)))),Vector2(1252,135),19,GOLD)
	var offset := Vector2(sin(h.anim*97),cos(h.anim*83))*shake*0.45
	h.draw_set_transform(offset)
	h.rounded(ARENA,Color("111b2b"),26,Color(AQUA,0.2+pulse*0.4))
	var centre := ARENA.get_center()
	var phase := fposmod(elapsed,BEAT)/BEAT
	for radius in [100,180,260]:
		h.draw_arc(centre,radius,0,TAU,90,Color(AQUA,0.025+pulse*0.025),1,true)
	for i in range(12):
		var angle := i*TAU/12
		var a := centre+Vector2.from_angle(angle)*80
		var b := centre+Vector2.from_angle(angle)*270
		h.draw_line(a,b,Color(AQUA,0.035),1,true)
	# Enemy attacks are aimed and locked one beat before firing.
	for enemy in enemies:
		if enemy.armed:
			var end: Vector2 = enemy.pos+enemy.lock*450
			h.draw_dashed_line(enemy.pos,end,Color(RED,0.22+phase*0.35),2,12)
			h.draw_arc(enemy.pos,enemy.radius+10+(1-phase)*20,0,TAU,48,Color(RED,0.65),2,true)
	for r in rings:
		h.draw_arc(r.pos,maxf(1,r.radius),0,TAU,48,Color(r.color,minf(0.8,r.life*2)),3,true)
	for shot in shots:
		var direction: Vector2 = shot.vel.normalized()
		var col: Color = GOLD if shot.strong else AQUA
		h.draw_line(shot.pos-direction*(46 if shot.strong else 17),shot.pos,col,shot.radius*1.2,true)
		if shot.strong: h.draw_circle(shot.pos,7,Color.WHITE)
	for line in traces:
		var alpha := minf(1,line.life*7)
		# Clip visible beams to the arena instead of drawing through the HUD.
		var direction: Vector2 = (line.to-line.from).normalized()
		var endpoint: Vector2 = line.from
		for step in range(90):
			var candidate: Vector2 = endpoint+direction*15
			if not ARENA.has_point(candidate): break
			endpoint = candidate
		h.draw_line(line.from,endpoint,Color(GOLD,alpha*0.14),24,true)
		h.draw_line(line.from,endpoint,Color(GOLD,alpha),8,true)
		h.draw_line(line.from,endpoint,Color(1,1,1,alpha),2,true)
	for bullet in bullets:
		h.draw_circle(bullet.pos,bullet.radius+4,Color(RED,0.16))
		h.draw_circle(bullet.pos,bullet.radius,RED)
		h.draw_circle(bullet.pos,bullet.radius*0.35,Color("ffe2ea"))
	for enemy in enemies:
		var size := 118.0 if enemy.boss else 66.0
		var pos: Vector2 = enemy.pos
		h.draw_circle(pos+Vector2(0,22),size*0.4,Color(0,0,0,0.3))
		icon("boss" if enemy.boss else "enemy",Rect2(pos-Vector2.ONE*(size/2+pulse*2),Vector2.ONE*(size+pulse*4)),Color.WHITE.lerp(GOLD,enemy.flash*0.65))
		var width := 105.0 if enemy.boss else 48.0
		h.rounded(Rect2(pos.x-width/2,pos.y-size/2-13,width,5),h.LINE,2)
		h.rounded(Rect2(pos.x-width/2,pos.y-size/2-13,width*maxf(0,float(enemy.hp)/enemy.maxhp),5),RED if enemy.boss else AQUA,2)
		if enemy.boss: h.center("音 箱 王",pos-Vector2(0,77),17,RED)
	for p in sparks:
		h.draw_circle(p.pos,p.size,Color(p.color,minf(1,p.life*4)))
	var direction := (aim-player).normalized()
	h.draw_circle(player+Vector2(0,23),26,Color(0,0,0,0.35))
	if elapsed<immune_until:
		h.draw_arc(player,34,0,TAU,48,Color(AQUA,0.6),3,true)
	var opacity := 0.45 if elapsed<immune_until and int(h.anim*16)%2==0 else 1.0
	# Keep the character upright; the external cannon and muzzle follow the aim.
	h.draw_set_transform(player+offset,0,Vector2(-1,1) if direction.x<0 else Vector2.ONE)
	icon("player",Rect2(-34,-36-pulse*5,68,68),Color(1,1,1,opacity))
	h.draw_set_transform(offset)
	h.draw_line(player+direction*19,player+direction*(39-recoil*8),AQUA,9,true)
	h.draw_circle(player+direction*(40-recoil*8),7+recoil*4,GOLD if recoil>0.5 else AQUA)
	if prepared_flash>0:
		h.draw_arc(player,37,0,TAU,48,Color(AQUA,prepared_flash),4,true)
	if ARENA.has_point(aim):
		h.draw_arc(aim,12+(1-phase)*12,0,TAU,36,Color(AQUA,0.5),1.5,true)
		h.draw_arc(aim,11,-0.6,0.6,12,GOLD,2,true)
		h.draw_line(aim-Vector2(5,0),aim+Vector2(5,0),AQUA,1)
		h.draw_line(aim-Vector2(0,5),aim+Vector2(0,5),AQUA,1)
	if hurt_flash>0: h.rounded(ARENA,Color(RED,hurt_flash*0.2),26,Color(RED,hurt_flash))
	h.draw_set_transform(Vector2.ZERO)
	h.text("SCORE",Vector2(51,213),17,h.MUTED)
	h.text("%06d" % score,Vector2(48,258),35)
	for i in range(max_hp): h.center("♥",Vector2(65+i*32,307),26,RED if i<hp else h.LINE)
	h.text("准拍连击",Vector2(53,368),20,h.MUTED)
	h.text(str(streak),Vector2(51,419),43,GOLD)
	h.text("连续8个动作 → 狂热",Vector2(53,456),15,h.MUTED)
	h.text("接上 %d   漏拍 %d" % [on_time,missed_cues],Vector2(53,495),15,AQUA)
	h.text("%+d ms" % timing_ms,Vector2(53,528),20,h.MUTED)
	h.text("WASD 自由移动",Vector2(53,560),16,h.MUTED)
	h.draw_circle(Vector2(126,650),68,Color(AQUA,0.04))
	h.draw_arc(Vector2(126,650),66,0,TAU,64,Color(AQUA,0.23),2,true)
	h.draw_circle(Vector2(126,650)+touch_dir*43,25,Color(AQUA,0.22))
	h.center("移动",Vector2(126,656)+touch_dir*43,15,h.MUTED)
	h.center("鼠标瞄准",Vector2(1308,226),19,h.MUTED)
	h.center("左键点射",Vector2(1308,261),22,AQUA)
	h.center("看下方动作到线",Vector2(1308,297),16,h.MUTED)
	if elapsed<overdrive_until:
		h.rounded(Rect2(1220,337,178,101),Color("34402a"),16,GOLD)
		h.center("狂 热",Vector2(1309,378),29,GOLD)
		h.center("剩余 %d 拍" % int(ceil((overdrive_until-elapsed)/BEAT)),Vector2(1309,413),18)
	else:
		var upcoming := ""
		for cue in cues:
			if cue.status<2:
				upcoming = "闪！空格" if cue.type=="dash" else "射！左键"
				break
		h.center(upcoming,Vector2(1308,376),25,AQUA if upcoming.begins_with("闪") else GOLD)
		h.center("提前按会蓄力",Vector2(1308,412),16,h.MUTED)
	h.button("combat_fire",Rect2(1222,502,176,102),"点 按 开 火",true)
	h.button("combat_dash",Rect2(1222,626,176,74),"空格  闪",false,true)
	h.center("每小节第三拍闪避",Vector2(1309,736),15,AQUA)
	draw_action_lane()
	if feedback_timer>0: h.center(feedback,Vector2(720,865),23,feedback_color)
	if beat<0:
		h.rounded(Rect2(542,359,356,167),Color("142232"),22,AQUA)
		h.center(str(maxi(1,-beat)),Vector2(720,441),68,GOLD)
		h.center("前八拍跟鼓射击，先找到节奏",Vector2(720,487),19)

func draw_pause() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.88))
	h.buttons.clear()
	h.rounded(Rect2(465,253,510,390),h.PANEL,24,h.LINE)
	h.center("暂停一下，找回节奏。",Vector2(720,329),31)
	h.center("音乐、弹幕和倒计时已同步暂停",Vector2(720,371),18,h.MUTED)
	h.button("combat_resume",Rect2(520,413,400,61),"继续战斗  ▶",true)
	h.button("combat_start",Rect2(520,492,191,55),"重新开始")
	h.button("combat_menu",Rect2(729,492,191,55),"返回菜单")
	h.center("ESC / Enter 继续",Vector2(720,600),17,h.MUTED)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.91))
	h.buttons.clear()
	h.rounded(Rect2(295,173,850,557),h.PANEL,25,GOLD if won else RED)
	var title := "终曲击破！这就是你的节奏。" if boss_defeated else ("守住舞池！下次试着击倒音箱王。" if won else "再来一次，跟住下一拍。")
	h.center(title,Vector2(720,252),33,GOLD if won else h.INK)
	h.center("30秒结束 · 砰、砰、闪、砰！" if won else "看清闪字，第三拍用空格接上。",Vector2(720,298),18,h.MUTED)
	icon("player",Rect2(356,349,200,200))
	h.text("得分",Vector2(614,368),19,h.MUTED)
	h.text(str(score),Vector2(610,434),55,GOLD)
	h.text("接上 %d / 64    最高连拍 %d" % [on_time,max_streak],Vector2(614,478),21)
	h.text("击破 %d    狂热 %d    冲刺 %d" % [kills,overdrives,dash_total],Vector2(614,520),21,AQUA)
	h.text("音箱王：" + ("已击倒" if boss_defeated else "还差一点"),Vector2(614,560),19,h.MUTED)
	h.button("combat_start",Rect2(430,618,300,64),"再打30秒！",true)
	h.button("combat_menu",Rect2(750,618,250,64),"返回菜单")
	h.center("漏拍 %d  ·  拍外 / 错动作 %d  ·  完美 %d" % [missed_cues,wrong_inputs,on_time-good_actions],Vector2(720,792),19,h.MUTED)

func draw_action_lane() -> void:
	h.rounded(Rect2(237,755,966,76),h.PANEL,16,h.LINE)
	var target_x := 438.0
	h.text("到线出手",Vector2(255,786),17,h.MUTED)
	h.text("射 = 左键/J",Vector2(255,813),13,GOLD)
	h.draw_line(Vector2(target_x,760),Vector2(target_x,826),Color.WHITE,3,true)
	h.draw_arc(Vector2(target_x,792),26+pulse*4,0,TAU,40,Color(GOLD,0.3+pulse*0.4),2,true)
	for cue in cues:
		var x := target_x+(float(cue.time)-elapsed)*260
		if x<374 or x>1140: continue
		var color: Color = AQUA if cue.type=="dash" else GOLD
		var alpha := 1.0 if cue.status<2 else (0.35 if cue.status==2 else 0.12)
		h.rounded(Rect2(x-26,767,52,49),Color(color,0.18 if cue.status==0 else 0.48),11,Color(color,alpha))
		h.center("闪" if cue.type=="dash" else "射",Vector2(x,799),25,Color(color,alpha))
		if cue.status==1: h.draw_circle(Vector2(x,761),4,AQUA)
		if fmod(float(cue.beat),4.0)==0:
			h.draw_line(Vector2(x,750),Vector2(x,755),color,2)
	if elapsed<INTRO:
		h.text("听四拍准备，再接第一枪 →",Vector2(670,745),16,h.MUTED)
