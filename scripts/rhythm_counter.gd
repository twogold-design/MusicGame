extends RefCounted

const BEAT := 0.5
const INTRO := 2.0
const END := 32.0
const HIT := Vector2(510,474)
const SPEED := 430.0
const GOLD := Color("e4ff7b")
const AQUA := Color("67f1ed")
const RED := Color("ff628e")
var h
var art: Dictionary = {}
var music: AudioStreamPlayer
var response_players: Array[AudioStreamPlayer] = []
var response_until: Array[float] = [-1.0,-1.0]
var melody_players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var cues: Array = []
var elapsed := 0.0
var beat := -4
var hp := 8
var max_hp := 8
var score := 0
var streak := 0
var max_streak := 0
var resolved := 0
var missed := 0
var wrong := 0
var perfect := 0
var heavy_hits := 0
var holding := -1
var active_input := ""
var recovery_hold := false
var won := false
var boss_hp := 18
var boss_defeated := false
var pulse := 0.0
var punch := 0.0
var press_flash := 0.0
var hurt_flash := 0.0
var shake := 0.0
var feedback := ""
var feedback_color := GOLD
var feedback_timer := 0.0
var sparks: Array = []
var flying: Array = []
var last_reject := -99.0
var timing_ms := 0

func _init(host) -> void:
	h = host
	for id in ["hero","grunt","heavy","boss"]:
		var path := "res://assets/counter/%s.svg" % id
		if ResourceLoader.exists(path): art[id] = load(path)
	if not art.has("hero"): art.hero = load("res://assets/combat/player.svg")
	if not art.has("grunt"): art.grunt = load("res://assets/combat/enemy.svg")
	if not art.has("heavy"): art.heavy = load("res://assets/combat/boss.svg")
	if not art.has("boss"): art.boss = load("res://assets/combat/boss.svg")
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/groove/bed.wav")
	music.volume_db = -3
	h.add_child(music)
	for i in range(2):
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/groove/response_%s.wav" % ("even" if i==0 else "odd"))
		audio.volume_db = -80
		h.add_child(audio)
		response_players.append(audio)
	for i in range(8):
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/groove/shot_%d.wav" % i)
		audio.volume_db = -1
		h.add_child(audio)
		melody_players.append(audio)
	for id in ["dash","miss"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://assets/audio/groove/%s.wav" % id)
		audio.volume_db = -1 if id=="dash" else -10
		h.add_child(audio)
		sounds[id] = audio

func make_chart() -> Array:
	var chart: Array = []
	for b in range(60):
		var type := "hold" if b in [13,29,45,57] else ("release" if b in [14,30,46,58] else "tap")
		chart.append({"beat":float(b),"time":INTRO+b*BEAT,"type":type,"status":0,"offset":0.0,"sound":false,"sample":((b/4)%4)*2+b%2,"voice":"dash" if b>=8 and b%4==2 else "shot"})
		if b in [43,47,51,55]:
			chart.append({"beat":b+0.5,"time":INTRO+(b+0.5)*BEAT,"type":"tap","status":0,"offset":0.0,"sound":false,"sample":((b/4)%4)*2,"voice":"shot"})
	return chart

func start() -> void:
	stop()
	h.music.stop()
	h.adventure.stop_audio()
	cues = make_chart()
	elapsed = 0
	beat = -4
	max_hp = 8 if h.easy else 5
	hp = max_hp
	score = 0
	streak = 0
	max_streak = 0
	resolved = 0
	missed = 0
	wrong = 0
	perfect = 0
	heavy_hits = 0
	boss_hp = 18
	boss_defeated = false
	won = false
	pulse = 0
	punch = 0
	shake = 0
	press_flash = 0
	hurt_flash = 0
	last_reject = -99
	timing_ms = 0
	flying.clear()
	sparks.clear()
	response_until = [-1.0,-1.0]
	music.play()
	for audio in response_players:
		audio.volume_db = -80
		audio.play()
	h.screen = "combat_play"
	say("看这个圈，到圈时点一下。",AQUA,5)

func stop() -> void:
	music.stop()
	music.stream_paused = false
	for audio in response_players+melody_players+sounds.values():
		audio.stop()
		audio.stream_paused = false
	for audio in response_players: audio.volume_db = -80
	response_until = [-1.0,-1.0]
	active_input = ""
	holding = -1
	recovery_hold = false

func show_intro() -> void:
	stop()
	h.music.stop()
	h.adventure.stop_audio()
	h.screen = "combat_intro"

func now() -> float:
	return maxf(elapsed,maxf(0,music.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()))

func window_early() -> float:
	return 0.15 if h.easy else 0.11

func window_late() -> float:
	return 0.15 if h.easy else 0.11

func say(message: String,color: Color,seconds: float) -> void:
	feedback = message
	feedback_color = color
	feedback_timer = seconds

func closest_cue() -> int:
	var time: float = now()-h.offset_ms/1000.0
	var closest := INF
	var found := -1
	for i in range(cues.size()):
		var delta := time-float(cues[i].time)
		if delta < -window_early() or delta > window_late(): continue
		if absf(delta)<closest:
			closest = absf(delta)
			found = i
	return found

func press(source := "test") -> void:
	if h.screen!="combat_play" or not active_input.is_empty(): return
	active_input = source
	press_flash = 1
	if recovery_hold:
		recovery_hold = false
		return
	var index := closest_cue()
	if index<0:
		if now()>=INTRO-window_early(): reject_input()
		return
	var cue: Dictionary = cues[index]
	if cue.status!=0: return
	if cue.type=="release":
		say("金色长敌：先按住，再松开",GOLD,0.6)
		return
	if cue.type=="hold": holding = index
	accept(index)

func release(source := "test") -> void:
	if h.screen!="combat_play" or source!=active_input: return
	active_input = ""
	if holding<0: return
	var tail := holding+1
	holding = -1
	var index := closest_cue()
	if index==tail and cues[tail].status==0:
		accept(tail)
	else:
		# One long enemy is one failure, even when released before its tail.
		if cues[tail].status==0: miss_cue(tail,true)

func accept(index: int) -> void:
	var cue: Dictionary = cues[index]
	cue.status = 1
	cue.offset = now()-h.offset_ms/1000.0-float(cue.time)
	schedule_cue_audio()
	if now()>=float(cue.time): execute_cue(index)

func reject_input() -> void:
	if now()-last_reject<0.16: return
	last_reject = now()
	wrong += 1
	streak = 0
	say("等它到圈，再出手",h.MUTED,0.45)
	# No extra musical voice or HP penalty obscures the next drum beat.

func schedule_cue_audio() -> void:
	var time := now()
	for i in range(2):
		if time>response_until[i]: response_players[i].volume_db = -80
	for i in range(cues.size()):
		var cue: Dictionary = cues[i]
		if cue.status!=1 or cue.sound: continue
		if time<float(cue.time):
			response_players[i%2].volume_db = -1
			response_until[i%2] = float(cue.time)+0.25
			cue.sound = true
		else: play_cue_sound(cue)

func play_cue_sound(cue: Dictionary) -> void:
	if cue.sound: return
	cue.sound = true
	if cue.voice=="dash": sounds.dash.play()
	else: melody_players[int(cue.sample)].play()

func execute_cue(index: int) -> void:
	var cue: Dictionary = cues[index]
	if cue.status!=1: return
	cue.status = 2
	play_cue_sound(cue)
	resolved += 1
	streak += 1
	max_streak = maxi(max_streak,streak)
	var precise := absf(float(cue.offset))<=0.07
	if precise: perfect += 1
	score += 100 if precise else 70
	timing_ms = int(float(cue.offset)*1000)
	punch = 1
	shake = 11 if cue.type=="release" else 4
	if cue.type=="release": heavy_hits += 1
	if cue.type!="hold":
		flying.append({"pos":HIT,"vel":Vector2(950,-480 if cue.type=="release" else -380),"life":0.65,"heavy":cue.type=="release","spin":0.0})
	for i in range(16 if cue.type=="release" else 8):
		sparks.append({"pos":HIT,"vel":Vector2.from_angle(randf()*TAU)*randf_range(90,320),"life":0.35,"color":GOLD if cue.type=="release" else AQUA})
	if float(cue.beat)>=40 and cue.type!="hold":
		boss_hp = maxi(0,boss_hp-(3 if cue.type=="release" else 1))
		if boss_hp==0 and not boss_defeated:
			boss_defeated = true
			score += 1000
			shake = 15
	if cue.type=="hold": say("按住…",GOLD,0.5)
	elif cue.type=="release": say("重 拳！",GOLD,0.5)
	elif streak%8==0: say("%d 连拍 · 打飞！" % streak,GOLD,0.5)
	else: say("啪！" if precise else "接住！",AQUA,0.2)

func miss_cue(index: int,early_release := false) -> void:
	var cue: Dictionary = cues[index]
	if cue.status>=2: return
	cue.status = 3
	missed += 1
	streak = 0
	# A missed head also consumes its tail: no double penalty for one long foe.
	if cue.type=="hold" and index+1<cues.size(): cues[index+1].status = 3
	if cue.type=="release": holding = -1
	if float(cue.beat)>=8:
		hp -= 1
		hurt_flash = 0.3
		say("松早了 · 下一只接回来" if early_release else "下一只，接回来",h.MUTED,0.6)
	if hp<=0: finish(false)

func resolve_cues() -> void:
	schedule_cue_audio()
	var judge: float = now()-h.offset_ms/1000.0
	for i in range(cues.size()):
		if h.screen!="combat_play": return
		var cue: Dictionary = cues[i]
		if cue.status==1 and now()>=float(cue.time): execute_cue(i)
		elif cue.status==0 and judge>float(cue.time)+window_late(): miss_cue(i)

func update(delta: float) -> void:
	if not h.screen.begins_with("combat") or h.screen=="combat_pause": return
	pulse = maxf(0,pulse-delta*5)
	punch = maxf(0,punch-delta*6)
	press_flash = maxf(0,press_flash-delta*7)
	shake = maxf(0,shake-delta*35)
	hurt_flash = maxf(0,hurt_flash-delta)
	feedback_timer = maxf(0,feedback_timer-delta)
	for item in flying:
		item.pos += item.vel*delta
		item.vel.y += 280*delta
		item.spin += delta*5
		item.life -= delta
	flying = flying.filter(func(item): return item.life>0)
	for item in sparks:
		item.pos += item.vel*delta
		item.life -= delta
	sparks = sparks.filter(func(item): return item.life>0)
	if h.screen!="combat_play": return
	elapsed = now()
	var new_beat := int(floor((elapsed-INTRO)/BEAT))
	if new_beat!=beat:
		beat = new_beat
		pulse = 1
		if beat==10: say("金色长敌：按住头部，尾巴到圈松开",GOLD,2.4)
		if beat==40: say("最后一段，跟住它！",GOLD,1)
		if beat==41: say("两只挨在一起：哒哒，点两下",AQUA,1)
	resolve_cues()
	if h.screen=="combat_play" and elapsed>=END: finish(true)

func finish(success: bool) -> void:
	if h.screen=="combat_result": return
	won = success
	h.screen = "combat_result"
	stop()
	if success: score += hp*100
	var key := "counter_"+("easy" if h.easy else "normal")
	if score>int(h.records.get(key,0)): h.records[key] = score
	h.save_data()

func pause_game() -> void:
	if h.screen!="combat_play": return
	music.stream_paused = true
	for audio in response_players+melody_players+sounds.values(): audio.stream_paused = true
	h.screen = "combat_pause"
	active_input = ""
	recovery_hold = holding>=0

func resume_game() -> void:
	if h.screen!="combat_pause": return
	music.stream_paused = false
	for audio in response_players+melody_players+sounds.values(): audio.stream_paused = false
	h.screen = "combat_play"
	if recovery_hold: say("先按住，尾巴到圈松开",GOLD,1)

func action(id: String) -> void:
	if id=="combat_start": start()
	elif id=="combat_resume": resume_game()
	elif id=="combat_pause": pause_game()
	elif id=="combat_menu":
		stop()
		h.screen = "menu"
	elif id in ["sound","mode"]: h.action(id)

func pointer_down(point: Vector2,source: String) -> void:
	for button in h.buttons:
		if button.rect.has_point(point):
			action(button.id)
			return
	press(source)

func input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.pressed and event.keycode==KEY_ESCAPE:
			if h.screen=="combat_play": pause_game()
			elif h.screen=="combat_pause": resume_game()
			else: action("combat_menu")
		elif event.pressed and event.keycode==KEY_ENTER:
			if h.screen=="combat_pause": resume_game()
			elif h.screen in ["combat_intro","combat_result"]: start()
		elif event.physical_keycode in [KEY_SPACE,KEY_J]:
			if event.pressed: press("key_%d" % event.physical_keycode)
			else: release("key_%d" % event.physical_keycode)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: pointer_down(h.get_global_mouse_position(),"mouse")
		else: release("mouse")
	elif event is InputEventScreenTouch:
		if event.pressed: pointer_down(h.get_canvas_transform().affine_inverse()*event.position,"touch_%d" % event.index)
		else: release("touch_%d" % event.index)

func state() -> Dictionary:
	var chart: Array = []
	for cue in cues: chart.append({"time":cue.time,"type":cue.type,"status":cue.status,"beat":cue.beat})
	return {"mode":"counter","elapsed":elapsed,"beat":beat,"hp":hp,"score":score,"streak":streak,"maxStreak":max_streak,"resolved":resolved,"missed":missed,"wrong":wrong,"perfect":perfect,"heavyHits":heavy_hits,"holding":holding,"pressed":not active_input.is_empty(),"bossHp":boss_hp,"bossDefeated":boss_defeated,"won":won,"cues":chart,"timingMs":timing_ms}

func icon(id: String,rect: Rect2,tint := Color.WHITE) -> void:
	if art.has(id): h.draw_texture_rect(art[id],rect,false,tint)

func render() -> void:
	if h.screen=="combat_intro": draw_intro()
	else:
		draw_game()
		if h.screen=="combat_pause": draw_pause()
		elif h.screen=="combat_result": draw_result()

func draw_intro() -> void:
	h.brand()
	h.button("sound",Rect2(1020,28,174,44),"声音 关" if h.muted else "声音 开",false,true)
	h.button("combat_menu",Rect2(1212,28,180,44),"其他模式",false,true)
	h.text("这一拳，",Vector2(90,225),74)
	h.text("刚好踩中拍。",Vector2(90,322),74,GOLD)
	h.text("只看一个圈，只用一个键。",Vector2(95,385),26,AQUA)
	h.text("怪物到圈时点一下，把它打回音箱王！",Vector2(95,435),21,h.MUTED)
	icon("hero",Rect2(780,150,290,290))
	icon("grunt",Rect2(1140,290,110,110))
	h.draw_line(Vector2(770,471),Vector2(1310,471),Color(AQUA,0.35),3,true)
	h.draw_arc(Vector2(1040,370),86,0,TAU,64,GOLD,4,true)
	h.rounded(Rect2(90,525,600,160),h.PANEL,22,h.LINE)
	h.text("普通怪 → 点一下",Vector2(120,576),27,AQUA)
	h.text("空格 / J / 点击屏幕，选一种就好",Vector2(120,624),20,h.MUTED)
	h.rounded(Rect2(720,525,630,160),h.PANEL,22,h.LINE)
	h.text("金色长敌 → 按住，再松开",Vector2(750,576),27,GOLD)
	h.text("头部到圈按住，尾巴到圈松开",Vector2(750,624),20,h.MUTED)
	h.button("combat_start",Rect2(430,749,360,70),"听四拍，开始！ →",true)
	h.button("mode",Rect2(814,749,230,70),"轻松 · 8心 ⇄" if h.easy else "挑战 · 5心 ⇄")
	h.center("30秒 · 前八拍放心练 · 最后跟着哒哒连点两下",Vector2(720,865),18,h.MUTED)

func draw_game() -> void:
	h.brand()
	h.button("sound",Rect2(1120,28,115,44),"静音" if h.muted else "声音 开",false,true)
	h.button("combat_pause",Rect2(1250,28,142,44),"Ⅱ 暂停",false,true)
	h.rounded(Rect2(48,91,1344,4),h.LINE,2)
	h.rounded(Rect2(48,91,1344*clampf((elapsed-INTRO)/30,0,1),4),GOLD,2)
	for i in range(max_hp): h.center("♥",Vector2(61+i*25,139),18,RED if i<hp else h.LINE)
	h.center("%d 连拍" % streak,Vector2(720,140),20,GOLD)
	h.text("%02d 秒" % int(ceil(maxf(0,END-maxf(INTRO,elapsed)))),Vector2(1300,140),19,h.MUTED)
	var offset := Vector2(sin(h.anim*93),cos(h.anim*71))*shake*0.4
	h.draw_set_transform(offset)
	h.rounded(Rect2(80,245,1280,370),Color("121c2b"),32,Color(AQUA,0.09+pulse*0.1))
	for i in range(8):
		h.draw_line(Vector2(440+i*120,515),Vector2(390+i*140,610),Color(AQUA,0.035),1,true)
	h.draw_line(Vector2(450,474),Vector2(1340,474),Color(AQUA,0.2+pulse*0.15),3,true)
	if elapsed>=22:
		icon("boss",Rect2(1160,200+sin(h.anim*3)*4,170,170),Color(1,1,1,0.35 if boss_defeated else 0.85))
		h.rounded(Rect2(1175,192,140,5),h.LINE,2)
		h.rounded(Rect2(1175,192,140*boss_hp/18.0,5),RED,2)
	# The enemies ARE the timing display. There is no separate note lane.
	for i in range(cues.size()):
		var cue: Dictionary = cues[i]
		if cue.status>=2 or cue.type=="release": continue
		var x: float = HIT.x+(float(cue.time)-elapsed)*SPEED
		if x>1400 or x<390: continue
		if cue.type=="hold":
			var tail_x: float = HIT.x+(float(cues[i+1].time)-elapsed)*SPEED
			h.rounded(Rect2(x,449,maxf(1,tail_x-x),50),Color(GOLD,0.22),20,Color(GOLD,0.65))
			h.draw_circle(Vector2(tail_x,474),22,Color(GOLD,0.15))
			h.draw_arc(Vector2(tail_x,474),20,0,TAU,32,GOLD,3,true)
			icon("heavy",Rect2(x-45,425,90,90))
		else: icon("grunt",Rect2(x-35,439,70,70))
	# A held long enemy stays visibly connected to its approaching tail.
	if holding>=0:
		var tail_x: float = maxf(HIT.x,HIT.x+(float(cues[holding+1].time)-elapsed)*SPEED)
		h.rounded(Rect2(HIT.x,449,maxf(1,tail_x-HIT.x),50),Color(GOLD,0.3),20,GOLD)
		h.draw_arc(Vector2(tail_x,474),22,0,TAU,32,GOLD,3,true)
		icon("heavy",Rect2(HIT-Vector2(47,49),Vector2(94,94)))
	for item in flying:
		h.draw_set_transform(item.pos+offset,item.spin,Vector2.ONE)
		icon("heavy" if item.heavy else "grunt",Rect2(-36,-36,72,72),Color(1,1,1,minf(1,item.life*3)))
	h.draw_set_transform(offset)
	var radius := 52+pulse*5+press_flash*4
	h.draw_circle(HIT,radius,Color(GOLD if holding>=0 else AQUA,0.07+press_flash*0.2))
	h.draw_arc(HIT,radius,0,TAU,64,GOLD if holding>=0 else AQUA,4,true)
	h.draw_arc(HIT,68+(1-fposmod(elapsed,BEAT)/BEAT)*28,0,TAU,64,Color(AQUA,0.12),2,true)
	icon("hero",Rect2(274+punch*35,365-pulse*4,185,185))
	if punch>0:
		h.draw_line(Vector2(425,471),HIT,Color(GOLD,punch),16,true)
		h.draw_arc(HIT,35+(1-punch)*80,-1.4,1.4,32,Color(GOLD,punch),5,true)
	for item in sparks: h.draw_circle(item.pos,4,Color(item.color,minf(1,item.life*3)))
	if hurt_flash>0: h.rounded(Rect2(80,245,1280,370),Color(RED,hurt_flash),32)
	if feedback_timer>0: h.center(feedback,Vector2(590,315),23,feedback_color)
	h.draw_set_transform(Vector2.ZERO)
	if elapsed<INTRO:
		h.center("听四拍… %d" % mini(4,4+beat),Vector2(510,660),31,GOLD)
	elif holding>=0: h.center("按住… 尾巴到圈时松开",Vector2(510,660),25,GOLD)
	else: h.center("到圈时，点一下",Vector2(510,660),24,AQUA)
	h.rounded(Rect2(402,702,216,68),Color(GOLD if not active_input.is_empty() else AQUA,0.1+press_flash*0.15),22,Color(AQUA,0.3))
	h.center("松 开" if holding>=0 else "空格 / J / 点按",Vector2(510,746),22,GOLD if holding>=0 else h.INK)
	h.text("← 只看这个圈",Vector2(646,745),17,h.MUTED)

func draw_pause() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.9))
	h.buttons.clear()
	h.rounded(Rect2(450,255,540,390),h.PANEL,25,h.LINE)
	h.center("暂停一下。",Vector2(720,338),38)
	h.center("音乐和来敌同步暂停",Vector2(720,387),20,h.MUTED)
	h.button("combat_resume",Rect2(510,421,420,62),"继续 ▶",true)
	h.button("combat_start",Rect2(510,505,200,56),"重新开始")
	h.button("combat_menu",Rect2(730,505,200,56),"其他模式")
	h.center("ESC / Enter 继续",Vector2(720,608),17,h.MUTED)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.93))
	h.buttons.clear()
	h.rounded(Rect2(300,180,840,560),h.PANEL,28,GOLD if won else h.LINE)
	h.center("音箱王，打回去了！" if boss_defeated else ("接住了这段音乐！" if won else "下一拳，再接回来。"),Vector2(720,267),37,GOLD)
	icon("hero",Rect2(369,342,210,210))
	h.text(str(score),Vector2(651,408),58,GOLD)
	h.text("接上 %d / 64 · 最长 %d 连拍" % [resolved,max_streak],Vector2(653,460),22)
	h.text("重拳 %d / 4 · 完美 %d" % [heavy_hits,perfect],Vector2(653,505),21,AQUA)
	h.text("漏拍 %d · 拍外 %d" % [missed,wrong],Vector2(653,547),18,h.MUTED)
	h.button("combat_start",Rect2(420,615,300,65),"再来一段！",true)
	h.button("combat_menu",Rect2(744,615,270,65),"其他模式")
