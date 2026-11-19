extends RefCounted
## Static shop dressing. Breakable displays are placed separately by the game.

const Art = preload("res://scripts/wreck3d_art.gd")
const INK := Color("273650")
const TEAL := Color("315d64")
const CREAM := Color("e3bd90")
const CORAL := Color("d47572")
const MINT := Color("8fcab5")
const GOLD := Color("e5a965")
static var terrazzo: ImageTexture
static var city_view: ImageTexture
static var stage_shadow: ImageTexture

static func build(stage: Node3D) -> void:
	var decor := Node3D.new()
	decor.name = "MidnightMartDressing"
	stage.add_child(decor)
	make_floor(decor)
	make_walls(decor)
	make_windows(decor)
	make_awning(decor)
	make_marquee(decor)
	make_sign(decor,"PLAY ARCADE",Vector3(-7.75,3.30,-6.73),3.9,Color("ffd5a0"))
	make_sign(decor,"SWEET GOODS",Vector3(7.05,3.30,-6.73),4.30,Color("b6f5d8"))
	make_floor_trim(decor)

static func plank(parent: Node3D, name: String, p: Vector3, size: Vector3, color: Color, bevel := 0.04, emission := 0.0) -> MeshInstance3D:
	return Art.box(parent,name,p,size,Art.material(color,emission),bevel)

static func make_floor(parent: Node3D) -> void:
	plank(parent,"PlinthBottom",Vector3(0,-0.69,0),Vector3(25.6,0.34,15.6),INK,0.13)
	plank(parent,"PlinthEdge",Vector3(0,-0.49,0),Vector3(25.56,0.10,15.52),GOLD,0.044)
	plank(parent,"FloorFoundation",Vector3(0,-0.27,0),Vector3(25.42,0.43,15.40),TEAL,0.12)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(25.2,15.2)
	var surface := MeshInstance3D.new()
	surface.name = "Terrazzo"
	surface.mesh = floor_mesh
	surface.position.y = 0.007
	var glaze := StandardMaterial3D.new()
	glaze.albedo_texture = floor_texture()
	glaze.albedo_color = Color("cbb8aa")
	glaze.roughness = 0.83
	glaze.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	surface.material_override = glaze
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(surface)

	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(35.0,24.0)
	var shadow := MeshInstance3D.new()
	shadow.mesh = shadow_mesh
	shadow.position = Vector3(1.5,-0.88,1.6)
	var shadow_material := StandardMaterial3D.new()
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_texture = shadow_texture()
	shadow.material_override = shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)

static func floor_texture() -> ImageTexture:
	if terrazzo: return terrazzo
	var image := Image.create_empty(960,580,false,Image.FORMAT_RGB8)
	image.fill(Color("927d83"))
	var colors := [Color("cab7a0"),Color("abaaa0"),Color("b29da0"),Color("a096a4")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4196
	for y in range(10):
		for x in range(16):
			var tone: Color = colors[(y*3+x+int(x/4))%colors.size()]
			var pos := Vector2i(x*60,y*58)
			image.fill_rect(Rect2i(pos+Vector2i(1,1),Vector2i(58,56)),tone)
			image.fill_rect(Rect2i(pos+Vector2i(1,1),Vector2i(58,1)),tone.lightened(0.14))
			for speck in range(13):
				var point := pos+Vector2i(rng.randi_range(3,55),rng.randi_range(3,53))
				var fleck := tone.darkened(0.16) if speck%3==0 else tone.lightened(0.23)
				image.fill_rect(Rect2i(point,Vector2i(rng.randi_range(1,3),rng.randi_range(1,2))),fleck)
	# Brass and ochre double inlay around the floor edge.
	for inset in [7,13]:
		var stripe := Color("8e6269") if inset==7 else Color("d5ad83")
		image.fill_rect(Rect2i(inset,inset,960-2*inset,2),stripe)
		image.fill_rect(Rect2i(inset,578-inset,960-2*inset,2),stripe)
		image.fill_rect(Rect2i(inset,inset,2,580-2*inset),stripe)
		image.fill_rect(Rect2i(958-inset,inset,2,580-2*inset),stripe)
	image.generate_mipmaps()
	terrazzo = ImageTexture.create_from_image(image)
	return terrazzo

static func shadow_texture() -> ImageTexture:
	if stage_shadow: return stage_shadow
	var image := Image.create_empty(128,96,false,Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var uv := Vector2(float(x)/127.0-0.5,float(y)/95.0-0.5)
			var alpha := 1.0-smoothstep(0.68,1.0,Vector2(uv.x*2.0,uv.y*2.0).length())
			image.set_pixel(x,y,Color(0.07,0.045,0.10,alpha*0.47))
	stage_shadow = ImageTexture.create_from_image(image)
	return stage_shadow

static func make_walls(parent: Node3D) -> void:
	plank(parent,"BackWall",Vector3(0,1.59,-7.28),Vector3(25.0,3.21,0.39),TEAL)
	plank(parent,"SideWall",Vector3(-12.25,1.59,0),Vector3(0.38,3.21,15.0),TEAL.darkened(0.13))
	for height in [0.12,0.81,3.20]:
		var tint := GOLD if height==0.81 else CREAM.darkened(0.18)
		plank(parent,"BackRail",Vector3(0,height,-7.045),Vector3(25.0,0.09,0.13),tint,0.025)
		plank(parent,"SideRail",Vector3(-12.02,height,0),Vector3(0.13,0.09,15.0),tint,0.025)
	for x in [-11.95,-4.05,3.24,11.85]:
		plank(parent,"Pilaster",Vector3(x,1.62,-7.02),Vector3(0.27,3.18,0.19),INK,0.037)
		plank(parent,"PilasterFoot",Vector3(x,0.21,-6.93),Vector3(0.41,0.40,0.33),INK,0.036)
		plank(parent,"PilasterCornice",Vector3(x,3.07,-6.95),Vector3(0.47,0.19,0.34),CREAM,0.047)
	for x in [-10.64,-3.60,2.85,10.80]:
		plank(parent,"SconceFrame",Vector3(x,2.55,-6.99),Vector3(0.49,0.65,0.23),INK,0.085)
		plank(parent,"SconceGlass",Vector3(x,2.57,-6.855),Vector3(0.33,0.42,0.115),Color("f8c590"),0.052,0.44)
		plank(parent,"SconceBrass",Vector3(x,2.76,-6.78),Vector3(0.40,0.055,0.08),GOLD,0.022)

static func make_windows(parent: Node3D) -> void:
	var glass_mesh := QuadMesh.new()
	glass_mesh.size = Vector2(3.08,1.54)
	var glass := StandardMaterial3D.new()
	glass.albedo_texture = city_texture()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for z in [-4.7,-0.30,4.15]:
		var frame := Node3D.new()
		frame.position = Vector3(-11.98,1.91,z)
		frame.rotation.y = PI/2
		parent.add_child(frame)
		plank(frame,"WindowCasement",Vector3.ZERO,Vector3(3.39,1.85,0.16),INK,0.10)
		plank(frame,"WindowGasket",Vector3(0,0,0.085),Vector3(3.21,1.65,0.10),GOLD,0.055)
		var pane := MeshInstance3D.new()
		pane.mesh = glass_mesh
		pane.material_override = glass
		pane.position.z = 0.146
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(pane)
		for x in [-0.53,0.53]:
			plank(frame,"WindowMullion",Vector3(x,0,0.173),Vector3(0.065,1.54,0.05),CREAM,0.016)
		plank(frame,"WindowTransom",Vector3(0,0.32,0.173),Vector3(3.08,0.061,0.05),CREAM,0.016)
		plank(frame,"WindowSill",Vector3(0,-0.88,0.17),Vector3(3.54,0.11,0.43),CORAL,0.037)

static func city_texture() -> ImageTexture:
	if city_view: return city_view
	var image := Image.create_empty(384,192,false,Image.FORMAT_RGB8)
	for y in range(192):
		var tint := Color("192840").lerp(Color("648299"),float(y)/192.0)
		image.fill_rect(Rect2i(0,y,384,1),tint)
	var rng := RandomNumberGenerator.new()
	rng.seed = 721
	for i in range(25):
		var p := Vector2i(rng.randi_range(4,378),rng.randi_range(12,110))
		image.fill_rect(Rect2i(p,Vector2i.ONE if i%4 else Vector2i(2,2)),Color("ddd8c0"))
	for x in range(262,307):
		var half := int(sqrt(maxf(0.0,484.0-pow(x-284.0,2))))
		image.fill_rect(Rect2i(x,48-half,1,half*2+1),Color("efc7a0"))
	for i in range(18):
		var x := i*22
		var roof := rng.randi_range(106,160)
		image.fill_rect(Rect2i(x,roof,21,192-roof),Color("293e59").lerp(Color("344e66"),rng.randf()))
		for y in range(roof+5,186,8):
			for column in range(3):
				if rng.randf()>0.48:
					image.fill_rect(Rect2i(x+3+column*5,y,2,3),Color("d9aa7f"))
	image.generate_mipmaps()
	city_view = ImageTexture.create_from_image(image)
	return city_view

static func make_awning(parent: Node3D) -> void:
	for config in [[-7.05,7.2],[7.16,8.4]]:
		var center: float = config[0]
		var width: float = config[1]
		plank(parent,"AwningBeam",Vector3(center,2.98,-6.95),Vector3(width+0.18,0.13,0.24),INK)
		for index in range(12):
			var tint := CORAL if index%2==0 else Color("d4bfa6")
			if center>0: tint = TEAL.lightened(0.28) if index%2==0 else Color("c9d6b6")
			var x := center-width*0.5+(index+0.5)*width/12.0
			var shade := plank(parent,"AwningStripe",Vector3(x,2.97,-6.72),Vector3(width/12.0+0.01,0.073,0.53),tint,0.021)
			shade.rotation.x = 0.16
			plank(parent,"AwningValance",Vector3(x,2.85,-6.47),Vector3(width/12.0+0.013,0.16,0.10),tint,0.037)

static func make_marquee(parent: Node3D) -> void:
	var pos := Vector3(-0.16,3.46,-7.04)
	plank(parent,"MarqueeFrame",pos,Vector3(7.15,1.15,0.30),GOLD,0.21)
	plank(parent,"MarqueeFace",pos+Vector3(0,0,0.16),Vector3(6.86,0.90,0.12),INK,0.16)
	mounted_text(parent,"MIDNIGHT MART",pos+Vector3(0,0.075,0.245),Color("ffe2ae"),0.0086,80)
	mounted_text(parent,"OPEN LATE",pos+Vector3(0,-0.265,0.247),Color("a5e4cf"),0.0038,40)
	for x in [-3.1,-2.86,2.86,3.1]:
		Art.sphere(parent,"MarqueeBulb",pos+Vector3(x,0,0.23),Vector3.ONE*0.115,Art.material(GOLD,0.48))

static func make_sign(parent: Node3D, title: String, pos: Vector3, width: float, color: Color) -> void:
	plank(parent,"DepartmentSign",pos,Vector3(width,0.41,0.14),INK,0.093)
	mounted_text(parent,title,pos+Vector3(0,0.009,0.081),color,0.005,55)

static func mounted_text(parent: Node3D, title: String, pos: Vector3, color: Color, pixel: float, size: int) -> void:
	var sign := Label3D.new()
	sign.text = title
	sign.font_size = size
	sign.pixel_size = pixel
	sign.position = pos
	sign.modulate = color
	sign.outline_size = 0
	parent.add_child(sign)

static func make_floor_trim(parent: Node3D) -> void:
	make_rug(parent,Vector3(-8.26,0.031,3.90),Vector2(7.25,4.48),Color("904d65"),Color("c28886"))
	make_rug(parent,Vector3(-5.15,0.031,-1.53),Vector2(10.9,2.85),Color("556e7c"),Color("a5bba9"))
	make_rug(parent,Vector3(6.98,0.031,-0.73),Vector2(9.45,3.36),Color("496f6f"),Color("a1b88f"))
	for x in [-10.96,11.32]:
		plank(parent,"SafetyStripe",Vector3(x,0.033,6.62),Vector3(1.85,0.028,0.35),INK,0.014)
		for i in range(4):
			var mark := plank(parent,"SafetyMark",Vector3(x-0.62+i*0.42,0.05,6.62),Vector3(0.16,0.011,0.35),Color("d6a16e"),0.004)
			mark.rotation.y = -0.37

static func make_rug(parent: Node3D, pos: Vector3, size: Vector2, color: Color, border: Color) -> void:
	plank(parent,"RugBinding",pos,Vector3(size.x,0.035,size.y),border,0.017)
	plank(parent,"RugPile",pos+Vector3(0,0.02,0),Vector3(size.x-0.16,0.02,size.y-0.16),color,0.009)
	for z in [-0.42,0.42]:
		plank(parent,"RugPiping",pos+Vector3(0,0.035,z*size.y),Vector3(size.x-0.43,0.01,0.025),border,0.004)
	for x in [-0.47,0.47]:
		plank(parent,"RugPiping",pos+Vector3(x*size.x,0.035,0),Vector3(0.025,0.01,size.y-0.38),border,0.004)
