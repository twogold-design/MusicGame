extends Node2D

const BG = Color("0c0f19")
const PANEL = Color("151b29")
const LINE = Color("2a3143")
const INK = Color("f4f4ef")
const MUTED = Color("919bb3")
const LIME = Color("dbff79")
const PINK = Color("ff83b5")
const CYAN = Color("77e4e0")
const COLORS = [Color("ff83b5"), Color("c4a0ff"), Color("77e4e0"), Color("dbff79")]
const IDS: Array[String] = ["sunset", "neon", "cosmic"]
const TITLES: Array[String] = ["落日汽水", "霓虹夜行", "星际派对"]
const SUBS: Array[String] = ["SUNSET SODA", "NEON AFTERHOURS", "COSMIC DISCO"]
const BPMS: Array[int] = [100, 120, 140]
const KEYS = [KEY_D, KEY_F, KEY_J, KEY_K]
const KEY_NAMES = ["D", "F", "J", "K"]

var font: Font
var bold_font: Font
var textures: Dictionary = {}
var screen := "combat_intro"
var selected := 0
var easy := true
var muted := false
var offset_ms := 0
var anim := 0.0
var buttons: Array = []
var hover := Vector2(-1,-1)
var music: AudioStreamPlayer
var hit_players: Array = []
var notes: Array = []
var duration := 65.0
var clock_time := 0.0
var paused_time := 0.0
var score := 0
var combo := 0
var best_combo := 0
var perfect := 0
var great := 0
var good := 0
var missed := 0
var resolved := 0
var total_units := 0
var accuracy_sum := 0.0
var energy := 0.0
var fever_until := -1.0
var fever_count := 0
var feedback := "READY?"
var feedback_color := LIME
var feedback_timer := 0.0
var held := [false,false,false,false]
var flashes := [0.0,0.0,0.0,0.0]
var particles: Array = []
var records: Dictionary = {}
var new_record := false
var tutorial_hits := [false,false,false,false]
var pointer_lanes: Dictionary = {}
var report_timer := 0.0
var music_cache: Dictionary = {}
var resume_grace := -1.0
var adventure
var combat

func _ready() -> void:
	var base_font: Font = load("res://assets/fonts/NotoSansSC.ttf")
	var regular := FontVariation.new()
	regular.base_font = base_font
	regular.variation_opentype = {2003265652:500.0}
	font = regular
	var bold := FontVariation.new()
	bold.base_font = base_font
	bold.variation_opentype = {2003265652:800.0}
	bold_font = bold
	for asset in ["stage", "cat-dj", "cover-sunset", "cover-neon", "cover-cosmic"]:
		var path: String = "res://assets/" + asset + ".svg"
		if ResourceLoader.exists(path): textures[asset] = load(path)
	music = AudioStreamPlayer.new()
	add_child(music)
	music.volume_db = -3
	for lane in range(4):
		var player := AudioStreamPlayer.new()
		var sound := AudioStreamWAV.new()
		sound.format = AudioStreamWAV.FORMAT_16_BITS
		sound.mix_rate = 22050
		var data := PackedByteArray()
		data.resize(3308)
		for i in range(1654):
			var t := float(i) / 22050.0
			var value := sin(TAU * (660.0 + lane * 110) * t) * exp(-t * 65.0) * 0.18
			data.encode_s16(i * 2, int(value * 32767))
		sound.data = data
		player.stream = sound
		add_child(player)
		hit_players.append(player)
	load_save()
	set_audio()
	adventure = preload("res://scripts/adventure.gd").new(self)
	combat = preload("res://scripts/rhythm_wreck3d.gd").new(self)
	get_tree().auto_accept_quit = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.meowReady=true;")
	queue_redraw()

func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://meow-beat.cfg") == OK:
		records = cfg.get_value("game", "records", {})
		easy = cfg.get_value("settings", "easy", true)
		muted = cfg.get_value("settings", "muted", false)
		offset_ms = int(cfg.get_value("settings", "offset", 0))

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "records", records)
	cfg.set_value("settings", "easy", easy)
	cfg.set_value("settings", "muted", muted)
	cfg.set_value("settings", "offset", offset_ms)
	cfg.save("user://meow-beat.cfg")

func set_audio() -> void:
	AudioServer.set_bus_mute(0, muted)

func song_time() -> float:
	return maxf(0.0, music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())

func _process(delta: float) -> void:
	anim += delta
	if adventure: adventure.update(delta)
	if combat: combat.update(delta)
	feedback_timer = maxf(0, feedback_timer - delta)
	for i in range(4): flashes[i] = maxf(0, flashes[i] - delta * 3.2)
	for p in particles:
		p.pos += p.vel * delta
		p.vel.y += 150 * delta
		p.life -= delta
	particles = particles.filter(func(p): return p.life > 0)
	if screen == "play":
		clock_time = maxf(clock_time, song_time())
		var judge_time := clock_time - offset_ms / 1000.0
		for n in notes:
			if n.state == 0 and judge_time - float(n.time) > hit_window():
				n.state = 3
				judge("MISS", int(n.lane))
				if float(n.duration) > 0: judge("MISS", int(n.lane))
			elif n.state == 1:
				if not held[int(n.lane)] and clock_time > resume_grace:
					n.state = 2
					judge("MISS", int(n.lane))
				elif judge_time >= float(n.time) + float(n.duration):
					n.state = 2
					judge("PERFECT", int(n.lane))
		if clock_time >= duration - 0.1 or (not music.playing and clock_time > 4):
			finish_song()
	report_timer += delta
	if report_timer > 0.1 and OS.has_feature("web"):
		report_timer = 0
		var state := {"screen":screen,"time":clock_time,"score":score,"combo":combo,"resolved":resolved,"total":total_units,"missed":missed,"selected":selected,"easy":easy,"duration":duration,"fever":is_fever(),"offset":offset_ms,"muted":muted}
		if adventure and screen.begins_with("adv"): state.adventure = adventure.state()
		if combat and screen.begins_with("combat"): state.combat = combat.state()
		JavaScriptBridge.eval("window.meowState=" + JSON.stringify(state) + ";window.meowState.stamp=performance.now();")
	queue_redraw()

func hit_window() -> float:
	return 0.19 if easy else 0.16

func is_fever() -> bool:
	return screen == "play" and clock_time < fever_until

func start_song() -> void:
	music.stop()
	var chart_path := "res://assets/charts/%s_%s.json" % [IDS[selected], "easy" if easy else "normal"]
	if not FileAccess.file_exists(chart_path):
		feedback = "曲目正在准备中"
		return
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chart_path))
	notes = chart.notes.duplicate(true)
	duration = float(chart.duration)
	total_units = 0
	for n in notes:
		n.state = 0
		total_units += 2 if float(n.duration) > 0 else 1
	var music_path := "res://assets/audio/%s.wav" % IDS[selected]
	if not music_cache.has(music_path): music_cache[music_path] = load(music_path)
	music.stream = music_cache[music_path]
	score = 0
	combo = 0
	best_combo = 0
	perfect = 0
	great = 0
	good = 0
	missed = 0
	resolved = 0
	accuracy_sum = 0
	energy = 0
	fever_until = -1
	fever_count = 0
	clock_time = 0
	resume_grace = -1
	feedback_timer = 0
	held = [false,false,false,false]
	particles.clear()
	pointer_lanes.clear()
	screen = "play"
	music.stream_paused = false
	music.play()

func judge(quality: String, lane: int) -> void:
	resolved += 1
	feedback = quality
	feedback_timer = 0.65
	if quality == "MISS":
		missed += 1
		combo = 0
		energy = maxf(0, energy - 8)
		feedback_color = Color("8991a6")
		return
	combo += 1
	best_combo = maxi(combo, best_combo)
	var base := 1000
	var acc := 1.0
	if quality == "PERFECT":
		perfect += 1
		feedback_color = LIME
	elif quality == "GREAT":
		great += 1
		base = 750
		acc = 0.75
		feedback_color = CYAN
	else:
		good += 1
		base = 450
		acc = 0.45
		feedback_color = PINK
	accuracy_sum += acc
	score += int(base * (1.0 + minf(floor(combo / 10.0), 5) * 0.1) * (2.0 if is_fever() else 1.0))
	if not is_fever():
		energy += 7 if quality == "PERFECT" else 4
		if energy >= 100:
			energy = 0
			fever_until = clock_time + 8.0 * 60.0 / BPMS[selected]
			fever_count += 1
	flashes[lane] = 1
	for j in range(12):
		particles.append({"pos":Vector2(525 + lane * 130, 702),"vel":Vector2(randf_range(-150,150),randf_range(-260,-60)),"life":randf_range(0.25,0.65),"color":COLORS[lane]})
	if not muted: hit_players[lane].play()

func press_lane(lane: int) -> void:
	if held[lane]: return
	held[lane] = true
	flashes[lane] = 0.7
	if screen == "tutorial":
		tutorial_hits[lane] = true
		hit_players[lane].play()
		return
	if screen != "play": return
	var closest = null
	var distance := hit_window() + 0.001
	var time := maxf(clock_time,song_time()) - offset_ms / 1000.0
	for n in notes:
		if n.state != 0 or int(n.lane) != lane: continue
		var diff := absf(time - float(n.time))
		if diff <= distance:
			closest = n
			distance = diff
	if closest == null: return
	closest.state = 1 if float(closest.duration) > 0 else 2
	judge("PERFECT" if distance <= (0.08 if easy else 0.065) else ("GREAT" if distance <= (0.13 if easy else 0.11) else "GOOD"), lane)

func release_lane(lane: int) -> void:
	held[lane] = false
	if screen != "play": return
	var time := maxf(clock_time,song_time()) - offset_ms / 1000.0
	for n in notes:
		if int(n.lane) == lane and n.state == 1:
			n.state = 2
			judge("PERFECT" if time >= float(n.time) + float(n.duration) - 0.11 else "MISS", lane)

func pause_game() -> void:
	if screen != "play": return
	paused_time = clock_time
	music.stream_paused = true
	screen = "pause"
	held = [false,false,false,false]
	pointer_lanes.clear()

func resume_game() -> void:
	# Give players a short window to re-hold active long notes after resuming.
	resume_grace = clock_time + 0.45
	screen = "play"
	music.stream_paused = false

func finish_song() -> void:
	for n in notes:
		if n.state == 0:
			judge("MISS", int(n.lane))
			if float(n.duration) > 0: judge("MISS",int(n.lane))
		elif n.state == 1: judge("MISS",int(n.lane))
		n.state = 2
	music.stop()
	screen = "result"
	var key := IDS[selected] + ("_easy" if easy else "_normal")
	new_record = score > int(records.get(key,0))
	if new_record: records[key] = score
	save_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if combat and screen=="combat_play": combat.pause_game()
		elif adventure and screen=="adv_play": adventure.pause_game()
		else: pause_game()

func _input(event: InputEvent) -> void:
	if screen.begins_with("combat"):
		combat.input(event)
		return
	if screen.begins_with("adv"):
		adventure.input(event)
		return
	if event is InputEventKey and not event.echo:
		var lane := KEYS.find(event.physical_keycode)
		if lane >= 0:
			if event.pressed: press_lane(lane)
			else: release_lane(lane)
		if event.pressed:
			if event.keycode == KEY_ESCAPE:
				if screen == "play": pause_game()
				elif screen == "pause": resume_game()
				elif screen in ["tutorial","settings"]: screen = "menu"
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				if screen=="menu": combat.show_intro()
				elif screen in ["tutorial","result"]: start_song()
				elif screen == "pause": resume_game()
	if event is InputEventMouseMotion: hover = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		if event.pressed: pointer_down(-1, point)
		else: pointer_up(-1)
	if event is InputEventScreenTouch:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		if event.pressed: pointer_down(event.index, point)
		else: pointer_up(event.index)

func pointer_down(id: int, point: Vector2) -> void:
	for b in buttons:
		if b.rect.has_point(point):
			action(b.id)
			return
	if screen == "play" and Rect2(460,180,520,650).has_point(point):
		var lane := clampi(int((point.x - 460) / 130),0,3)
		pointer_lanes[id] = lane
		press_lane(lane)
	elif screen == "tutorial" and Rect2(460,570,520,110).has_point(point):
		var lane := clampi(int((point.x - 460) / 130),0,3)
		pointer_lanes[id] = lane
		press_lane(lane)

func pointer_up(id: int) -> void:
	if pointer_lanes.has(id):
		var lane := int(pointer_lanes[id])
		pointer_lanes.erase(id)
		if not pointer_lanes.values().has(lane): release_lane(lane)

func action(id: String) -> void:
	if id=="combat": combat.show_intro()
	elif id=="adventure": adventure.show_intro()
	elif id.begins_with("song_"): selected = int(id.trim_prefix("song_"))
	elif id == "start": start_song()
	elif id == "mode":
		easy = not easy
		save_data()
	elif id == "help":
		tutorial_hits = [false,false,false,false]
		screen = "tutorial"
	elif id == "settings": screen = "settings"
	elif id == "sound":
		muted = not muted
		set_audio()
		save_data()
	elif id == "pause": pause_game()
	elif id == "resume": resume_game()
	elif id == "menu":
		music.stop()
		screen = "menu"
		held = [false,false,false,false]
	elif id == "next":
		selected = (selected + 1) % 3
		start_song()
	elif id == "offset_minus":
		offset_ms = maxi(-200,offset_ms-10)
		save_data()
	elif id == "offset_plus":
		offset_ms = mini(200,offset_ms+10)
		save_data()

func rounded(rect: Rect2, color: Color, radius := 16.0, border := Color.TRANSPARENT) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = int(radius)
	box.corner_radius_top_right = int(radius)
	box.corner_radius_bottom_left = int(radius)
	box.corner_radius_bottom_right = int(radius)
	if border.a > 0:
		box.set_border_width_all(1)
		box.border_color = border
	draw_style_box(box,rect)

func text(value: String, pos: Vector2, size := 22, color := INK) -> void:
	draw_string(bold_font if size>=26 else font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func center(value: String, pos: Vector2, size := 22, color := INK) -> void:
	var face: Font = bold_font if size>=26 else font
	text(value, pos - Vector2(face.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x / 2,0),size,color)

func button(id: String, rect: Rect2, label: String, primary := false, small := false) -> void:
	var over := rect.has_point(hover)
	rounded(rect, LIME.lightened(0.1) if primary and over else (LIME if primary else (Color("283246") if over else PANEL)),12,Color.TRANSPARENT if primary else LINE)
	center(label,rect.position + Vector2(rect.size.x/2,rect.size.y/2 + (7 if small else 8)),18 if small else 22,BG if primary else INK)
	buttons.append({"id":id,"rect":rect})

func art(name: String, rect: Rect2, tint := Color.WHITE) -> void:
	if textures.has(name): draw_texture_rect(textures[name],rect,false,tint)

func _draw() -> void:
	buttons.clear()
	draw_rect(Rect2(0,0,1440,900),BG)
	for i in range(35):
		var pos := Vector2(fmod(i * 191.2,1440),fmod(i * 117.7,900))
		draw_circle(pos,1.2,Color(0.4,0.5,0.7,0.12 + sin(anim+i)*0.05))
	if screen.begins_with("combat"): combat.render()
	elif screen.begins_with("adv"): adventure.render()
	elif screen == "menu": draw_menu()
	elif screen in ["play","pause"]:
		draw_game()
		if screen == "pause": draw_pause()
	elif screen == "result": draw_result()
	elif screen == "tutorial": draw_tutorial()
	elif screen == "settings": draw_settings()

func brand() -> void:
	rounded(Rect2(48,30,38,38),LIME,11)
	center("m",Vector2(67,58),28,BG)
	text("MEOW BEAT",Vector2(100,58),24)
	text("喵喵打碟俱乐部",Vector2(288,57),17,MUTED)

func draw_menu() -> void:
	brand()
	button("combat",Rect2(1045,29,135,42),"3D拆迁王",false,true)
	button("settings",Rect2(1192,29,92,42),"设置",false,true)
	button("sound",Rect2(1296,29,96,42),"静音" if muted else "声音 开",false,true)
	draw_line(Vector2(48,90),Vector2(1392,90),LINE)
	rounded(Rect2(48,125,173,30),Color("26332a"),15)
	text("●  3D · 午夜商场",Vector2(61,147),15,LIME)
	text("今天，",Vector2(48,238),65)
	text("把压力砸碎。",Vector2(48,326),63,LIME)
	text("踩准鼓点，一锤震碎一大片。",Vector2(51,378),23,INK)
	text("空格砸亮的家具，按住再松开砸得更狠。",Vector2(51,416),18,MUTED)
	button("combat",Rect2(48,456,270,66),"开始3D打砸  ↗",true)
	button("mode",Rect2(334,456,232,66),"轻松模式  ⇄" if easy else "挑战模式  ⇄")
	button("start",Rect2(48,538,162,39),"经典四轨打碟",false,true)
	button("adventure",Rect2(230,538,162,39),"节拍冒险旧版",false,true)
	rounded(Rect2(632,119,760,450),Color("181e32"),26,LINE)
	draw_texture_rect(combat.view.get_texture(),Rect2(632,168,760,353),false)
	rounded(Rect2(656,139,123,31),Color("121b2c"),15)
	text("3D WRECKER",Vector2(668,161),14,CYAN)
	rounded(Rect2(1198,505,169,40),Color("111724"),15)
	text("♫  ORIGINAL MIX",Vector2(1216,531),14,LIME)
	text("旧模式歌单",Vector2(48,619),28)
	text("经典打碟 / 节拍冒险使用下方曲目",Vector2(270,617),17,MUTED)
	text("3D拆迁 120 BPM / 48秒",Vector2(1120,618),16,MUTED)
	for i in range(3):
		var x := 48 + i * 454
		var rect := Rect2(x,646,436,174)
		rounded(rect,Color("242d2b") if selected == i else PANEL,20,LIME if selected == i else LINE)
		art("cover-"+IDS[i],Rect2(x+16,663,140,140))
		text("0%d  /  %s" % [i+1,"CHILL" if i==0 else ("GROOVE" if i==1 else "ENERGY")],Vector2(x+176,681),13,COLORS[i])
		text(TITLES[i],Vector2(x+176,720),28)
		text(SUBS[i],Vector2(x+177,746),11,MUTED)
		text("%d BPM    %s" % [BPMS[i],"● ○ ○" if i==0 else ("● ● ○" if i==1 else "● ● ●")],Vector2(x+177,785),16,LIME if selected==i else MUTED)
		buttons.append({"id":"song_%d" % i,"rect":rect})
	text("独立节奏实验室  /  GODOT 2D",Vector2(48,865),13,MUTED)
	var record_key := "adventure_"+IDS[selected] + ("_easy" if easy else "_normal")
	text("冒险最佳  %06d" % int(records.get(record_key,0)),Vector2(1171,865),16,MUTED)

func draw_game() -> void:
	brand()
	center(TITLES[selected],Vector2(720,53),25)
	button("pause",Rect2(1245,28,147,44),"Ⅱ  暂停",false,true)
	var progress := clampf(clock_time / duration,0,1)
	rounded(Rect2(48,93,1344,4),LINE,2)
	rounded(Rect2(48,93,1344*progress,4),LIME,2)
	text("%s  /  %d BPM" % ["轻松" if easy else "挑战",BPMS[selected]],Vector2(48,132),16,MUTED)
	text("%02d:%02d / %02d:%02d" % [int(clock_time)/60,int(clock_time)%60,int(duration)/60,int(duration)%60],Vector2(1254,132),16,MUTED)
	text("SCORE / 得分",Vector2(66,221),16,MUTED)
	text("%07d" % score,Vector2(62,285),51)
	text("ACCURACY / 准确率",Vector2(66,342),16,MUTED)
	text("%.1f%%" % (accuracy_sum/maxi(resolved,1)*100),Vector2(64,390),37,CYAN)
	rounded(Rect2(62,432,312,120),PANEL,18,LINE)
	text("派对能量",Vector2(84,464),18,LIME)
	text("×2 得分中！" if is_fever() else "跟上节奏，自动开启派对",Vector2(84,496),15,MUTED)
	rounded(Rect2(84,515,267,8),LINE,4)
	rounded(Rect2(84,515,267*(1.0 if is_fever() else energy/100),8),LIME,4)
	var bounce := sin(clock_time * BPMS[selected]/60.0 * TAU) * (12 if is_fever() else 5)
	for bar in range(19):
		var h := 8 + (sin(clock_time*5+bar*1.7)*0.5+0.5) * (48 if is_fever() else 24)
		rounded(Rect2(75+bar*15,802-h,6,h),Color(COLORS[bar%4],0.25),3)
	art("cat-dj",Rect2(87,570+bounce,260,260))
	center("喵！就这个节奏。" if combo>5 else "慢慢来，音乐一直都在。",Vector2(218,840),17,MUTED)
	rounded(Rect2(451,155,538,677),Color("242b42") if is_fever() else LINE,20)
	rounded(Rect2(458,162,524,663),Color("101622"),15)
	for lane in range(4):
		var x := 460 + lane * 130
		if lane%2==0: draw_rect(Rect2(x,175,130,538),Color(1,1,1,0.018))
		if held[lane] or flashes[lane]>0:
			draw_rect(Rect2(x+3,180,124,536),Color(COLORS[lane],0.05+flashes[lane]*0.12))
		if lane>0: draw_line(Vector2(x,177),Vector2(x,810),LINE)
		var target := Rect2(x+11,726,108,74)
		rounded(target,COLORS[lane] if held[lane] else PANEL,14,COLORS[lane])
		center(KEY_NAMES[lane],Vector2(x+65,775),30,BG if held[lane] else COLORS[lane])
	var speed := 280.0 if easy else 350.0
	var time := clock_time-offset_ms/1000.0
	var beat := 60.0/BPMS[selected]
	for j in range(10):
		var bt := floorf(time/beat)*beat + j*beat
		var y := 702-(bt-time)*speed
		if y>180 and y<705: draw_line(Vector2(465,y),Vector2(975,y),Color(1,1,1,0.055))
	for n in notes:
		if n.state >= 2: continue
		var y := 702-(float(n.time)-time)*speed
		var tail := y-float(n.duration)*speed
		if y < 180 or tail>721: continue
		var x := 475+int(n.lane)*130
		var c: Color = COLORS[int(n.lane)]
		if float(n.duration)>0:
			var top := maxf(180,tail)
			var bottom := minf(704,y)
			if bottom>top:
				rounded(Rect2(x+22,top,56,bottom-top),Color(c,0.26 if n.state==0 else 0.7),8)
				draw_line(Vector2(x+50,top),Vector2(x+50,bottom),Color(c,0.8),3)
		if n.state==0 and y<723:
			rounded(Rect2(x,y-12,100,24),c,8)
			rounded(Rect2(x+12,y-8,76,4),Color(1,1,1,0.55),2)
		elif n.state==1:
			draw_circle(Vector2(x+50,702),20+sin(anim*30)*4,Color(c,0.6))
	draw_line(Vector2(460,702),Vector2(980,702),Color("edf3ff"),3)
	for p in particles: draw_circle(p.pos,3.5,Color(p.color,minf(1,p.life*2)))
	center("判定线 · 音符到这里时敲击",Vector2(720,864),15,MUTED)
	center("COMBO",Vector2(1190,246),18,MUTED)
	center(str(combo),Vector2(1190,343),88,LIME if combo>=10 else INK)
	if feedback_timer>0:
		center(feedback,Vector2(1190,400),29,feedback_color)
		if feedback in ["GREAT","GOOD"]: center("贴近白线，更准一点",Vector2(1190,433),15,MUTED)
	if is_fever():
		rounded(Rect2(1044,478,291,112),Color("2d3628"),20,LIME)
		center("PARTY TIME",Vector2(1190,521),27,LIME)
		center("舞池全开 · 双倍得分",Vector2(1190,560),18)
	else:
		center("放轻松，别追着音符跑",Vector2(1190,532),18,MUTED)
		center("听见节拍，让手指跟上",Vector2(1190,564),18,MUTED)
	draw_circle(Vector2(1190,647),43,Color("202738"))
	for radius in [24,31,38]: draw_arc(Vector2(1190,647),radius,0,TAU,48,LINE,1.2,true)
	draw_circle(Vector2(1190,647),14,COLORS[selected])
	draw_circle(Vector2(1190,647),4,BG)
	var arm := Vector2(cos(anim*2),sin(anim*2))*33
	draw_line(Vector2(1190,647)+arm*0.6,Vector2(1190,647)+arm,COLORS[selected],3,true)
	center("长条音符需要按住",Vector2(1190,711),17,MUTED)
	center("ESC 暂停  /  点击轨道也能玩",Vector2(1190,748),15,MUTED)
	if clock_time<3:
		rounded(Rect2(586,325,268,160),Color("202a36"),22,LIME)
		center(str(maxi(1,3-int(clock_time))),Vector2(720,418),74,LIME)
		center("听好节拍，准备开始",Vector2(720,458),17)

func draw_pause() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.86))
	buttons.clear()
	rounded(Rect2(465,243,510,414),PANEL,24,LINE)
	center("歇一小拍",Vector2(720,318),38)
	center("音乐和谱面已一起暂停",Vector2(720,361),19,MUTED)
	button("resume",Rect2(525,400,390,62),"继续派对  ▶",true)
	button("start",Rect2(525,479,186,54),"重新挑战")
	button("menu",Rect2(729,479,186,54),"返回歌单")
	center("按 ESC 或空格也可继续",Vector2(720,600),16,MUTED)

func draw_result() -> void:
	brand()
	var acc := accuracy_sum/maxi(total_units,1)*100
	var rank := "S" if acc>=95 else ("A" if acc>=85 else ("B" if acc>=70 else "C"))
	center("这一首，属于你。",Vector2(720,157),43)
	center(TITLES[selected]+"  /  "+("轻松模式" if easy else "挑战模式"),Vector2(720,202),21,MUTED)
	rounded(Rect2(219,248,1002,390),PANEL,26,LINE)
	art("cover-"+IDS[selected],Rect2(249,279,285,285))
	rounded(Rect2(437,474,116,116),LIME,58)
	center(rank,Vector2(495,563),80,BG)
	text("NEW BEST  /  新纪录" if new_record else "FINAL SCORE  /  最终得分",Vector2(591,302),17,LIME)
	text("%07d" % score,Vector2(588,374),61)
	text("准确率",Vector2(592,421),17,MUTED)
	text("%.1f%%" % acc,Vector2(592,467),33,CYAN)
	text("最高连击",Vector2(814,421),17,MUTED)
	text(str(best_combo),Vector2(814,467),33,PINK)
	text("派对次数",Vector2(1037,421),17,MUTED)
	text(str(fever_count),Vector2(1037,467),33,LIME)
	draw_line(Vector2(592,492),Vector2(1180,492),LINE)
	text("PERFECT  %d       GREAT  %d" % [perfect,great],Vector2(592,531),18,INK)
	text("GOOD       %d       MISS      %d" % [good,missed],Vector2(592,568),18,MUTED)
	center("FULL COMBO！一拍都没落下。" if missed==0 else "再来一次？下一次的你，一定更有节奏。",Vector2(720,687),22,LIME if missed==0 else MUTED)
	button("menu",Rect2(325,735,240,64),"返回歌单")
	button("start",Rect2(585,735,270,64),"再来一首！",true)
	button("next",Rect2(875,735,240,64),"挑战下一曲  →")
	center("最佳成绩会自动保存在当前浏览器",Vector2(720,855),15,MUTED)

func draw_tutorial() -> void:
	brand()
	button("menu",Rect2(1245,28,147,44),"返回歌单",false,true)
	center("四个按键，就能加入派对。",Vector2(720,172),42)
	center("音符落到白线时敲击，别急着提前按。",Vector2(720,218),23,MUTED)
	var labels := ["01  跟着拍子", "02  长音按住", "03  点燃舞池"]
	var bodies := ["D / F / J / K 对应四条轨道", "遇到长条，按到尾巴走完", "连续命中积攒能量，自动双倍"]
	for i in range(3):
		var x := 153+i*390
		rounded(Rect2(x,275,354,210),PANEL,20,LINE)
		text(labels[i],Vector2(x+24,317),25,COLORS[i])
		text(bodies[i],Vector2(x+24,359),17,MUTED)
		if i==0:
			for j in range(4): rounded(Rect2(x+28+j*76,393,60,28),COLORS[j],7)
		elif i==1:
			rounded(Rect2(x+30,397,281,18),Color(PINK,0.25),8)
			rounded(Rect2(x+30,390,70,32),PINK,8)
		else:
			rounded(Rect2(x+30,399,286,16),LINE,8)
			rounded(Rect2(x+30,399,210,16),LIME,8)
	center("先试试：敲响下面四个键",Vector2(720,545),23)
	for i in range(4):
		rounded(Rect2(470+i*130,578,110,88),COLORS[i] if tutorial_hits[i] else PANEL,15,COLORS[i])
		center(KEY_NAMES[i]+(" ✓" if tutorial_hits[i] else ""),Vector2(525+i*130,635),30,BG if tutorial_hits[i] else COLORS[i])
	center("手机或平板：直接点击轨道，支持多指。",Vector2(720,708),18,MUTED)
	button("start",Rect2(535,749,370,65),"准备好了，开始打碟！",true)
	center("不用担心漏拍，音乐不会停下来。",Vector2(720,858),17,MUTED)

func draw_settings() -> void:
	brand()
	button("menu",Rect2(1245,28,147,44),"返回歌单",false,true)
	center("找到你的节奏",Vector2(720,192),42)
	rounded(Rect2(350,245,740,466),PANEL,24,LINE)
	text("游戏模式",Vector2(392,305),23)
	button("mode",Rect2(792,269,247,54),"轻松模式 ⇄" if easy else "挑战模式 ⇄")
	text("战斗5/4心；冒险4/3心；经典模式同步切换谱面。",Vector2(392,361),17,MUTED)
	draw_line(Vector2(392,390),Vector2(1040,390),LINE)
	text("游戏声音",Vector2(392,439),23)
	button("sound",Rect2(792,405,247,54),"静音" if muted else "音乐与音效 开")
	draw_line(Vector2(392,484),Vector2(1040,484),LINE)
	text("输入延迟补偿",Vector2(392,535),23)
	button("offset_minus",Rect2(760,501,61,52),"−")
	center("%+d ms" % offset_ms,Vector2(891,537),24,LIME)
	button("offset_plus",Rect2(977,501,61,52),"+")
	text("蓝牙耳机觉得判定偏早？试着增加补偿。",Vector2(392,597),18,MUTED)
	text("可调范围 −200 ～ +200 ms，建议使用扬声器或有线耳机。",Vector2(392,638),16,MUTED)
	button("menu",Rect2(535,754,370,63),"保存好了，去选歌",true)
