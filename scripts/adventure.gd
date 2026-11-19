extends RefCounted

const WIDTH := 9
const HEIGHT := 7
const TILE := 76
const ORIGIN := Vector2(367,198)
const HOME := Vector2i(4,3)
const EXIT := Vector2i(4,0)
const DIRS: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const STEMS: Array[String] = ["drums","bass","chords","melody"]
const STEM_NAMES: Array[String] = ["鼓点","贝斯","和弦","旋律"]
const ORANGE := Color("ffac77")
const RED := Color("ff637e")
var h
var textures: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var rng := RandomNumberGenerator.new()
var walls: Array[Vector2i] = []
var pickups: Array = []
var player := Vector2i(4,6)
var draw_pos := Vector2(4,6)
var queued := Vector2i.ZERO
var queued_perfect := false
var dash_armed := false
var charge := 2.0
var bank := 0
var bag := 0
var repaired := 0
var hearts := 4
var max_hearts := 4
var beat := -5
var last_move := -99
var immune_until := -1
var max_beats := 192
var elapsed := 0.0
var last_raw := 0.0
var wraps := 0
var loop_length := 9.6
var beat_length := 0.6
var moves := 0
var perfect_moves := 0
var damage_taken := 0
var total_score := 0
var pulse := 0.0
var toast := ""
var toast_timer := 0.0
var toast_color := Color.WHITE
var seed_value := 0
var hazard_shift := 0
var won := false
var result_reason := ""
var notes_fx: Array = []

func _init(host) -> void:
	h = host
	for id in ["cat-runner","deck","speaker-bot","note-token","gold-record","exit","hero"]:
		var path: String = "res://assets/adventure/"+id+".svg"
		if ResourceLoader.exists(path): textures[id] = load(path)
	for i in range(4):
		var audio := AudioStreamPlayer.new()
		audio.volume_db = -3 if i==0 else -80
		h.add_child(audio)
		players.append(audio)

func show_intro() -> void:
	stop_audio()
	h.music.stop()
	h.screen = "adv_intro"

func new_run(seed_override := -1) -> void:
	stop_audio()
	h.music.stop()
	if seed_override < 0: rng.randomize()
	else: rng.seed = seed_override
	seed_value = rng.seed
	hazard_shift = rng.randi_range(0,8)
	player = Vector2i(4,6)
	draw_pos = Vector2(player)
	queued = Vector2i.ZERO
	dash_armed = false
	charge = 2.0
	bank = 0
	bag = 0
	repaired = 0
	max_hearts = 4 if h.easy else 3
	hearts = max_hearts
	beat = -5
	last_move = -99
	immune_until = -1
	max_beats = 192 if h.easy else 160
	elapsed = 0
	last_raw = 0
	wraps = 0
	moves = 0
	perfect_moves = 0
	damage_taken = 0
	total_score = 0
	won = false
	result_reason = ""
	notes_fx.clear()
	toast = "先捡旋律，再回中央唱机交付"
	toast_timer = 5
	toast_color = h.LIME
	make_map()
	beat_length = 60.0 / h.BPMS[h.selected]
	loop_length = beat_length * 16
	for i in range(4):
		var path: String = "res://assets/audio/adventure/%s_%s.wav" % [h.IDS[h.selected],STEMS[i]]
		if not streams.has(path):
			var audio: AudioStreamWAV = load(path).duplicate()
			audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
			audio.loop_begin = 0
			audio.loop_end = int(round(loop_length*audio.mix_rate))
			streams[path] = audio
		players[i].stream = streams[path]
		players[i].volume_db = -3 if i==0 else -80
		players[i].stream_paused = false
		players[i].play()
	h.screen = "adv_play"

func stop_audio() -> void:
	for audio in players:
		audio.stop()
		audio.stream_paused = false

func make_map() -> void:
	walls.clear()
	pickups.clear()
	for attempt in range(100):
		if walls.size() >= (8 if h.easy else 11): break
		var cell := Vector2i(rng.randi_range(0,8),rng.randi_range(0,6))
		if cell.x==4 or cell.distance_to(HOME)<2 or walls.has(cell): continue
		walls.append(cell)
		if reachable().size() != WIDTH*HEIGHT-walls.size(): walls.erase(cell)
	spawn_pickups(8)

func reachable() -> Array[Vector2i]:
	var seen: Array[Vector2i] = [HOME]
	var index := 0
	while index<seen.size():
		for dir in DIRS:
			var cell := seen[index]+dir
			if valid(cell) and not seen.has(cell): seen.append(cell)
		index += 1
	return seen

func valid(cell: Vector2i) -> bool:
	return cell.x>=0 and cell.x<WIDTH and cell.y>=0 and cell.y<HEIGHT and not walls.has(cell)

func pickup_at(cell: Vector2i) -> int:
	for i in range(pickups.size()):
		if pickups[i].cell == cell: return i
	return -1

func spawn_pickups(count: int) -> void:
	var choices: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x,y)
			if valid(cell) and cell != player and cell != EXIT and cell.distance_to(HOME)>1.5 and pickup_at(cell)<0:
				choices.append(cell)
	for i in range(mini(count,choices.size())):
		var index := rng.randi_range(0,choices.size()-1)
		var cell := choices[index]
		choices.remove_at(index)
		pickups.append({"cell":cell,"value":2 if (i%4==3 or repaired>=2 and i%2==0) else 1})

func audio_time() -> float:
	var raw := maxf(0,players[0].get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency())
	if raw < last_raw-loop_length*0.5: wraps += 1
	last_raw = raw
	return wraps*loop_length+raw

func update(delta: float) -> void:
	toast_timer = maxf(0,toast_timer-delta)
	pulse = maxf(0,pulse-delta*4)
	draw_pos = draw_pos.lerp(Vector2(player),minf(1,delta*17))
	for fx in notes_fx:
		fx.pos.y -= delta*60
		fx.life -= delta
	notes_fx = notes_fx.filter(func(fx): return fx.life>0)
	if h.screen != "adv_play": return
	elapsed = maxf(elapsed,audio_time())
	var target := int(floor(elapsed/beat_length))-4
	while beat<target and h.screen=="adv_play":
		advance_beat(beat+1)
	for i in range(4):
		players[i].volume_db = move_toward(players[i].volume_db,-3 if i<=repaired else -80,delta*100)

func advance_beat(index: int) -> void:
	beat = index
	pulse = 1
	if beat<0: return
	if queued != Vector2i.ZERO:
		move_player(queued,queued_perfect)
		queued = Vector2i.ZERO
	if h.screen != "adv_play": return
	check_danger()
	if beat>=max_beats: finish(false,"天亮了，舞池即将关门。下次早点把旋律带出来！")
	if beat==8: say("红色虚线提前预告！倒数结束时别站上去。",RED,4)
	if beat==32: say("机关开始横向扫场，注意下一次预告。",ORANGE,4)

func queue_move(direction: Vector2i) -> void:
	if h.screen != "adv_play": return
	var time: float = maxf(elapsed,audio_time()) - h.offset_ms/1000.0
	var phase := fposmod(time,beat_length)
	var close: bool = minf(phase,beat_length-phase) <= (0.14 if h.easy else 0.105)
	if beat>=0 and phase<0.12 and last_move!=beat:
		move_player(direction,close)
		check_danger()
	else:
		queued = direction
		queued_perfect = close

func move_player(direction: Vector2i, precise: bool) -> void:
	if last_move==beat: return
	if not valid(player+direction):
		say("前面是音箱墙，换个方向。",h.MUTED,1)
		return
	var steps := 2 if dash_armed and charge>=2 else 1
	if steps==2: charge -= 2
	dash_armed = false
	last_move = beat
	moves += 1
	if precise:
		perfect_moves += 1
		charge = minf(4,charge+0.4)
		total_score += 40
	else: total_score += 15
	for i in range(steps):
		if not valid(player+direction): break
		player += direction
		collect_here()
		if h.screen != "adv_play": break
	if steps==2: notes_fx.append({"pos":cell_center(player),"life":0.7,"label":"冲刺！","color":h.CYAN})
	elif precise: notes_fx.append({"pos":cell_center(player)-Vector2(0,25),"life":0.5,"label":"踩准 +","color":h.LIME})

func collect_here() -> void:
	var index := pickup_at(player)
	if index>=0:
		var amount := mini(5-bag,int(pickups[index].value))
		if amount>0:
			bag += amount
			pickups[index].value -= amount
			if pickups[index].value==0: pickups.remove_at(index)
			total_score += amount*80
			h.hit_players[(bag+repaired)%4].play()
			say("抢到旋律 +%d！带回中央才算安全。" % amount,h.CYAN,2)
			if bag==5: say("背包满了！回中央唱机交付。",h.LIME,3)
		else: say("背包只能装5枚，先回中央交付。",ORANGE,2)
	if player==HOME and bag>0:
		var delivered := mini(bag,9-bank)
		bank += delivered
		bag = 0
		total_score += delivered*200
		var new_layers := mini(3,bank/3)
		if new_layers>repaired:
			var gained := new_layers-repaired
			repaired = new_layers
			hearts = mini(max_hearts,hearts+gained)
			total_score += 500*gained
			say("找回%d层声音！%s加入，回复%d颗心。" % [gained,STEM_NAMES[repaired],gained],h.LIME,4)
			spawn_pickups(4*gained)
		else: say("安全存下旋律！已交付 %d / 9。" % bank,h.CYAN,3)
		if bank>=9: say("完整旋律已找回！前往最上方出口。",h.LIME,6)
	if player==EXIT and bank>=9: finish(true,"你把整首歌，从寂静里偷了回来。")
	if pickups.size()<4 and bank<9: spawn_pickups(5)

func next_strike() -> int:
	return maxi(12,(maxi(beat,8)/4+1)*4)

func laser_cells(strike: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if strike<12 or strike%4!=0: return cells
	var group := strike/4
	var column := (group*2+hazard_shift)%WIDTH
	var row := (group+hazard_shift)%HEIGHT
	if strike<32 or group%2==0:
		for y in range(HEIGHT): cells.append(Vector2i(column,y))
	else:
		for x in range(WIDTH): cells.append(Vector2i(x,row))
	# Each attack is fixed by its beat, so depositing during a telegraph cannot
	# silently change the cells that will fire. Crossfire starts after beat 64.
	if strike>=64 and group%3==0:
		for x in range(WIDTH):
			var cell := Vector2i(x,row)
			if not cells.has(cell): cells.append(cell)
	cells.erase(HOME)
	cells.erase(EXIT)
	return cells

func speaker_cells(at: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if repaired<1 or at<16: return cells
	var ring: Array[Vector2i] = []
	for x in range(1,8): ring.append(Vector2i(x,1))
	for y in range(2,6): ring.append(Vector2i(7,y))
	for x in range(6,0,-1): ring.append(Vector2i(x,5))
	for y in range(4,1,-1): ring.append(Vector2i(1,y))
	for count in range(2 if repaired>=2 else 1):
		var pos: Vector2i = ring[(maxi(at,0)+hazard_shift+count*10)%ring.size()]
		if valid(pos): cells.append(pos)
	return cells

func check_danger() -> void:
	if h.screen!="adv_play" or beat<immune_until or player==HOME or player==EXIT: return
	if laser_cells(beat).has(player) or speaker_cells(beat).has(player):
		hearts -= 1
		damage_taken += 1
		var lost := mini(2,bag)
		bag -= lost
		immune_until = beat+3
		say("被击中了！掉落 %d 枚旋律，短暂无敌。" % lost,RED,3)
		if hearts<=0: finish(false,"音箱保安发现了你。看准红色预告，再试一条路线。")

func say(value: String,color: Color,seconds := 2.0) -> void:
	toast = value
	toast_timer = seconds
	toast_color = color

func toggle_dash() -> void:
	if charge<2:
		say("冲刺需要2格能量，踩准鼓点就能补充。",ORANGE,2)
		return
	dash_armed = not dash_armed
	say("下一步冲刺两格！留意落点。" if dash_armed else "已取消冲刺。",h.CYAN,2)

func finish(success: bool,reason: String) -> void:
	if h.screen=="adv_result": return
	won = success
	result_reason = reason
	queued = Vector2i.ZERO
	if success: total_score += maxi(0,max_beats-beat)*20+hearts*300
	var key: String = "adventure_"+h.IDS[h.selected]+("_easy" if h.easy else "_normal")
	if total_score>int(h.records.get(key,0)): h.records[key] = total_score
	h.save_data()
	h.screen = "adv_result"
	for audio in players:
		audio.stream_paused = not success
		if success: audio.volume_db = -3

func pause_game() -> void:
	if h.screen!="adv_play": return
	for audio in players: audio.stream_paused = true
	queued = Vector2i.ZERO
	h.screen = "adv_pause"

func resume_game() -> void:
	for audio in players: audio.stream_paused = false
	h.screen = "adv_play"

func input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: h.hover = h.get_global_mouse_position()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if h.screen=="adv_play": pause_game()
			elif h.screen=="adv_pause": resume_game()
			else: action("adv_menu")
			return
		if event.keycode==KEY_ENTER:
			if h.screen in ["adv_intro","adv_result"]: new_run()
			elif h.screen=="adv_pause": resume_game()
			return
		if h.screen!="adv_play": return
		if event.physical_keycode in [KEY_W,KEY_UP]: queue_move(Vector2i.UP)
		elif event.physical_keycode in [KEY_D,KEY_RIGHT]: queue_move(Vector2i.RIGHT)
		elif event.physical_keycode in [KEY_S,KEY_DOWN]: queue_move(Vector2i.DOWN)
		elif event.physical_keycode in [KEY_A,KEY_LEFT]: queue_move(Vector2i.LEFT)
		elif event.keycode==KEY_SHIFT: toggle_dash()
		elif event.keycode==KEY_SPACE:
			queued = Vector2i.ZERO
			say("等一拍，观察下一次攻击。",h.MUTED,1)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		pointer(h.get_global_mouse_position())
	if event is InputEventScreenTouch and event.pressed:
		pointer(h.get_canvas_transform().affine_inverse()*event.position)

func pointer(point: Vector2) -> void:
	for b in h.buttons:
		if b.rect.has_point(point):
			action(b.id)
			return
	if h.screen=="adv_play" and Rect2(ORIGIN,Vector2(WIDTH*TILE,HEIGHT*TILE)).has_point(point):
		var cell := Vector2i((point-ORIGIN)/TILE)
		var diff := cell-player
		if diff==Vector2i.ZERO: queued = Vector2i.ZERO
		elif absi(diff.x)>absi(diff.y): queue_move(Vector2i(signi(diff.x),0))
		else: queue_move(Vector2i(0,signi(diff.y)))

func action(id: String) -> void:
	if id=="adv_start": new_run()
	elif id=="adv_menu":
		stop_audio()
		h.screen = "menu"
	elif id=="adv_pause": pause_game()
	elif id=="adv_resume": resume_game()
	elif id=="adv_intro": show_intro()
	elif id=="adv_dash": toggle_dash()
	elif id=="adv_wait": queued = Vector2i.ZERO
	elif id.begins_with("adv_dir_"): queue_move(DIRS[int(id.trim_prefix("adv_dir_"))])
	elif id=="sound": h.action("sound")

func cell_center(cell: Vector2i) -> Vector2:
	return ORIGIN+Vector2(cell)*TILE+Vector2.ONE*(TILE/2.0)

func icon(id: String,rect: Rect2,tint := Color.WHITE) -> void:
	if textures.has(id): h.draw_texture_rect(textures[id],rect,false,tint)

func render() -> void:
	if h.screen=="adv_intro":
		draw_intro()
		return
	draw_board()
	if h.screen=="adv_pause": draw_pause()
	elif h.screen=="adv_result": draw_result()

func draw_intro() -> void:
	h.brand()
	h.button("adv_menu",Rect2(1220,28,172,44),"返回歌单",false,true)
	h.text("节拍夺回行动",Vector2(74,182),52,h.LIME)
	h.text("跟着鼓点走，把被偷走的音乐带回来。",Vector2(78,230),23)
	h.text("不必每拍都动，你可以等、绕路，也可以大胆冲刺。",Vector2(78,272),19,h.MUTED)
	icon("hero",Rect2(812,120,556,337))
	var titles := ["抢旋律","回唱机","躲预告"]
	var lines := ["普通音符1枚，金唱片2枚。","每交付3枚，唤回一个声部。","红色格子会在倒数后发射。"]
	var hints := ["背包最多5枚，受伤会掉落。","累计交付9枚，再去顶部出口。","音箱下一步的位置也会预告。"]
	for i in range(3):
		var x := 77+i*437
		h.rounded(Rect2(x,477,413,180),h.PANEL,20,h.LINE)
		h.text("0%d  %s" % [i+1,titles[i]],Vector2(x+25,523),28,h.COLORS[i])
		h.text(lines[i],Vector2(x+25,570),18)
		h.text(hints[i],Vector2(x+25,610),17,h.MUTED)
	h.text("WASD / 方向键  选方向",Vector2(80,340),22,h.CYAN)
	h.text("每拍走一格 · 提前按也可以，踩准拍子额外攒能量",Vector2(80,381),17,h.MUTED)
	h.text("Shift  准备冲刺两格     Space  等一拍",Vector2(80,424),20,h.CYAN)
	h.button("adv_start",Rect2(516,712,408,69),"出发！抢回整首歌  →",true)
	h.center("%s  /  %d BPM  /  %s  ·  每局地图与唱片位置不同" % [h.TITLES[h.selected],h.BPMS[h.selected],"轻松冒险" if h.easy else "极限冒险"],Vector2(720,832),17,h.MUTED)

func draw_board() -> void:
	h.brand()
	h.center("节拍夺回行动",Vector2(720,55),25)
	h.button("sound",Rect2(1123,28,110,44),"静音" if h.muted else "声音 开",false,true)
	h.button("adv_pause",Rect2(1245,28,147,44),"Ⅱ  暂停",false,true)
	h.draw_line(Vector2(48,91),Vector2(1392,91),h.LINE)
	h.text("%s  /  %d BPM" % [h.TITLES[h.selected],h.BPMS[h.selected]],Vector2(54,135),18,h.MUTED)
	h.text("轻松冒险" if h.easy else "极限冒险",Vector2(1230,135),18,h.MUTED)
	var remaining := maxi(0,max_beats-maxi(beat,0))
	h.text("剩余拍数",Vector2(62,223),17,h.MUTED)
	h.text(str(remaining),Vector2(58,289),59,h.INK if remaining>32 else RED)
	for i in range(max_hearts): h.center("♥",Vector2(77+i*44,338),34,RED if i<hearts else h.LINE)
	h.rounded(Rect2(53,372,272,143),h.PANEL,18,h.LINE)
	h.text("背包里的旋律",Vector2(74,407),18,h.MUTED)
	h.text("%d / 5" % bag,Vector2(73,456),34,h.LIME if bag>=3 else h.CYAN)
	h.text("受伤会掉落，带回中央存好",Vector2(74,490),15,h.MUTED)
	h.text("音乐修复",Vector2(60,560),21)
	for i in range(4):
		var y := 584+i*39
		h.rounded(Rect2(60,y,254,31),Color("27392e") if i<=repaired else h.PANEL,9)
		h.text(("●  " if i<=repaired else "○  ")+STEM_NAMES[i],Vector2(75,y+23),17,h.LIME if i<=repaired else h.MUTED)
	h.text("已安全交付  %d / 9" % bank,Vector2(61,776),21,h.LIME)
	h.text("9枚集齐 → 顶部出口撤离",Vector2(61,810),16,h.MUTED)
	h.rounded(Rect2(ORIGIN-Vector2(10,10),Vector2(WIDTH*TILE+20,HEIGHT*TILE+20)),Color("202638"),18,h.LINE)
	var future := laser_cells(next_strike())
	var current := laser_cells(beat)
	var phase := fposmod(elapsed,beat_length)/beat_length
	var next_bots := speaker_cells(beat+1)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x,y)
			var rect := Rect2(ORIGIN+Vector2(cell)*TILE+Vector2(3,3),Vector2(TILE-6,TILE-6))
			var color := Color("182333") if (x+y)%2==0 else Color("141d2b")
			if future.has(cell) and beat>=8: color = color.lerp(RED,0.13+0.09*phase)
			if current.has(cell) and pulse>0.2: color = RED.lerp(Color.WHITE,pulse*0.25)
			if cell==HOME: color = Color("244135")
			if cell==EXIT: color = Color("2e4333") if bank>=9 else Color("252a3c")
			h.rounded(rect,color,8)
			if walls.has(cell):
				h.rounded(rect.grow(-5),Color("30364a"),8)
				h.draw_circle(rect.get_center(),19,Color("171d2b"))
				h.draw_circle(rect.get_center(),9,Color("2a3143"))
			elif future.has(cell) and beat>=8 and cell!=HOME:
				h.draw_dashed_line(rect.position+Vector2(7,8),rect.end-Vector2(7,8),Color(RED,0.65),2,5)
			if next_bots.has(cell):
				h.rounded(rect.grow(-3),Color.TRANSPARENT,8,ORANGE)
				h.center("!",rect.position+Vector2(14,25),21,ORANGE)
	icon("deck",Rect2(cell_center(HOME)-Vector2(35,35),Vector2(70,70)))
	icon("exit",Rect2(cell_center(EXIT)-Vector2(35,35),Vector2(70,70)),Color.WHITE if bank>=9 else Color(0.6,0.6,0.7,0.8))
	for token in pickups:
		var pos := cell_center(token.cell)
		var bob := sin(h.anim*3+pos.x)*3
		icon("gold-record" if token.value==2 else "note-token",Rect2(pos-Vector2(24,24+bob),Vector2(48,48)))
		if token.value==2: h.center("2",pos+Vector2(23,25),14,ORANGE)
	for cell in speaker_cells(beat): icon("speaker-bot",Rect2(cell_center(cell)-Vector2(31,31),Vector2(62,62)))
	var cat_pos := ORIGIN+draw_pos*TILE+Vector2.ONE*(TILE/2.0)
	var cat_color := Color.WHITE
	if beat<immune_until and int(h.anim*12)%2==0: cat_color.a = 0.4
	h.draw_circle(cat_pos+Vector2(0,23),25,Color(0,0,0,0.35))
	icon("cat-runner",Rect2(cat_pos-Vector2(34,38+pulse*4),Vector2(68,68)),cat_color)
	if dash_armed: h.draw_arc(cat_pos,34,0,TAU,48,h.CYAN,3,true)
	if queued!=Vector2i.ZERO:
		var destination := player+queued
		if valid(destination): h.rounded(Rect2(ORIGIN+Vector2(destination)*TILE+Vector2(5,5),Vector2(66,66)),Color(h.LIME,0.06),10,h.LIME)
	for fx in notes_fx: h.center(fx.label,fx.pos,17,Color(fx.color,minf(1,fx.life*3)))
	h.text("下一次激光",Vector2(1100,223),18,h.MUTED)
	h.text("%d 拍后" % maxi(1,next_strike()-beat),Vector2(1095,269),34,RED)
	h.text("红色虚线 = 即将攻击",Vector2(1097,304),16,h.MUTED)
	h.text("橙色边框 = 音箱下一步",Vector2(1097,335),16,h.MUTED)
	h.text("冲刺能量",Vector2(1097,393),20,h.CYAN)
	for i in range(4): h.rounded(Rect2(1098+i*66,413,55,13),h.CYAN if charge>=i+1 else h.LINE,5)
	h.button("adv_dash",Rect2(1097,445,264,52),"已准备冲刺  ✓" if dash_armed else "Shift  冲刺 · 2能量",dash_armed,true)
	h.button("adv_dir_0",Rect2(1183,530,84,62),"↑")
	h.button("adv_dir_3",Rect2(1091,600,84,62),"←")
	h.button("adv_dir_2",Rect2(1183,600,84,62),"↓")
	h.button("adv_dir_1",Rect2(1275,600,84,62),"→")
	h.button("adv_wait",Rect2(1100,685,255,47),"Space  等一拍",false,true)
	h.center("WASD / 方向键 · 点击格子",Vector2(1228,770),15,h.MUTED)
	h.center("踩准节拍 +能量",Vector2(1228,803),17,h.CYAN)
	h.rounded(Rect2(ORIGIN.x,754,WIDTH*TILE,58),h.PANEL,14,h.LINE)
	for i in range(4):
		var cx := 601+i*72
		h.draw_circle(Vector2(cx,783),12+(pulse*4 if posmod(beat,4)==i else 0),h.LIME if posmod(beat,4)==i else h.LINE)
		h.center(str(i+1),Vector2(cx,788),13,h.BG if posmod(beat,4)==i else h.MUTED)
	var marker := Vector2(492,783)
	h.draw_arc(marker,10+(1-phase)*16,0,TAU,48,Color(h.CYAN,0.5),2,true)
	h.draw_circle(marker,8,h.CYAN if phase<0.18 else h.LINE)
	if toast_timer>0:
		h.rounded(Rect2(282,836,876,42),Color("202a35"),12)
		h.center(toast,Vector2(720,864),18,toast_color)
	if beat<0:
		h.rounded(Rect2(542,366,332,150),Color("111b28"),22,h.LIME)
		h.center(str(maxi(1,-beat)),Vector2(708,442),62,h.LIME)
		h.center("先看路线，听好鼓点",Vector2(708,485),20)
	elif bank>=9: h.center("↑ 带着整首歌从这里撤离",Vector2(708,180),18,h.LIME)
	else: h.center("中央唱机是安全区 · 捡到就能交付",Vector2(708,180),16,h.MUTED)

func draw_pause() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.88))
	h.buttons.clear()
	h.rounded(Rect2(465,250,510,397),h.PANEL,24,h.LINE)
	h.center("先歇一拍，想好路线。",Vector2(720,321),30)
	h.center("音乐、机关和倒计时都已暂停",Vector2(720,365),18,h.MUTED)
	h.button("adv_resume",Rect2(520,407,400,61),"继续行动  ▶",true)
	h.button("adv_start",Rect2(520,485,191,55),"换张地图")
	h.button("adv_menu",Rect2(729,485,191,55),"返回歌单")
	h.center("ESC / Enter 继续",Vector2(720,596),17,h.MUTED)

func draw_result() -> void:
	h.draw_rect(Rect2(0,0,1440,900),Color(0.02,0.03,0.05,0.91))
	h.buttons.clear()
	h.rounded(Rect2(295,175,850,552),h.PANEL,25,h.LIME if won else RED)
	h.center("整座舞池，重新有了音乐。" if won else "这次差一点，下一拍再来。",Vector2(720,248),35,h.LIME if won else h.INK)
	h.center(result_reason,Vector2(720,294),18,h.MUTED)
	icon("cat-runner",Rect2(360,344,200,200))
	h.text("行动得分",Vector2(620,364),18,h.MUTED)
	h.text(str(total_score),Vector2(615,429),53,h.LIME)
	h.text("修复声部   %d / 3" % repaired,Vector2(620,475),23)
	h.text("精准踩拍   %d / %d" % [perfect_moves,moves],Vector2(620,516),21,h.CYAN)
	h.text("交付旋律   %d / 9       受伤   %d 次" % [bank,damage_taken],Vector2(620,556),19,h.MUTED)
	h.button("adv_start",Rect2(440,616,294,62),"再潜入一次 · 新地图",true)
	h.button("adv_menu",Rect2(754,616,245,62),"返回歌单")
	h.center("听听你抢回的完整合奏。下一局，再换一条路线。" if won else "每次行动的布局、唱片位置与激光次序都会变化",Vector2(720,786),18,h.MUTED)

func state() -> Dictionary:
	var wall_list: Array = []
	var token_list: Array = []
	var danger_list: Array = []
	var bot_list: Array = []
	for cell in walls: wall_list.append([cell.x,cell.y])
	for token in pickups: token_list.append({"x":token.cell.x,"y":token.cell.y,"value":token.value})
	for cell in laser_cells(next_strike()): danger_list.append([cell.x,cell.y])
	for cell in speaker_cells(beat+1): bot_list.append([cell.x,cell.y])
	return {"player":[player.x,player.y],"beat":beat,"elapsed":elapsed,"beatLength":beat_length,"bank":bank,"bag":bag,"repaired":repaired,"hearts":hearts,"charge":charge,"dash":dash_armed,"moves":moves,"perfectMoves":perfect_moves,"score":total_score,"remaining":max_beats-maxi(beat,0),"won":won,"walls":wall_list,"pickups":token_list,"nextStrike":next_strike(),"danger":danger_list,"nextBots":bot_list,"seed":seed_value}
