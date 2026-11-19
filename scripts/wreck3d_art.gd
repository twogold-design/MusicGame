extends RefCounted
## Rounded toy geometry. Front is +Z; every prop rests at local Y = 0.
## No textures, imported models, lights, collision or gameplay are added here.

static var _materials: Dictionary = {}
static var _rounded_meshes: Dictionary = {}
static var _cylinder_meshes: Dictionary = {}
static var _ring_meshes: Dictionary = {}
static var _sphere_mesh: SphereMesh

static func material(tint: Color, glow: float = 0.0, metal: float = 0.05) -> StandardMaterial3D:
	var key := "%s:%.2f:%.2f" % [tint.to_html(), glow, metal]
	if _materials.has(key):
		return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = 0.49
	result.metallic = minf(metal, 0.07)
	result.metallic_specular = 0.32
	result.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if glow > 0.0:
		result.emission_enabled = true
		result.emission = tint
		result.emission_energy_multiplier = glow
	_materials[key] = result
	return result


static func _axis_samples(half_size: float, radius: float) -> PackedFloat32Array:
	# Two samples inside each bevel, plus a single broad planar middle face.
	return PackedFloat32Array([-half_size, -half_size + radius * 0.34, -half_size + radius,
		half_size - radius, half_size - radius * 0.34, half_size])


static func rounded_box_mesh(dimensions: Vector3, radius: float) -> ArrayMesh:
	var key := "%s:%.5f" % [dimensions, radius]
	if _rounded_meshes.has(key):
		return _rounded_meshes[key]
	var half_size := dimensions * 0.5
	var inner := half_size - Vector3.ONE * radius
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var face_normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
		Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var face_u: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.LEFT]
	var face_v: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.FORWARD,
		Vector3.BACK, Vector3.UP, Vector3.UP]
	for face_index: int in range(6):
		var normal := face_normals[face_index]
		var u_axis := face_u[face_index]
		var v_axis := face_v[face_index]
		var half_u := absf(u_axis.dot(half_size))
		var half_v := absf(v_axis.dot(half_size))
		var half_n := absf(normal.dot(half_size))
		var samples_u := _axis_samples(half_u, radius)
		var samples_v := _axis_samples(half_v, radius)
		var start := vertices.size()
		for row: int in range(6):
			for column: int in range(6):
				var point := normal * half_n + u_axis * samples_u[column] + v_axis * samples_v[row]
				var nearest := Vector3(clampf(point.x, -inner.x, inner.x),
					clampf(point.y, -inner.y, inner.y), clampf(point.z, -inner.z, inner.z))
				var rounded_normal := (point - nearest).normalized()
				vertices.append(nearest + rounded_normal * radius)
				normals.append(rounded_normal)
				uv.append(Vector2(float(column) / 5.0, float(row) / 5.0))
		for row: int in range(5):
			for column: int in range(5):
				var a := start + row * 6 + column
				var b := a + 1
				var c := a + 6
				var d := c + 1
				# Godot front faces use clockwise winding; explicit normals face out.
				indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rounded_meshes[key] = shape
	return shape


static func box(parent: Node3D, label: String, center: Vector3, dimensions: Vector3, surface: Material, bevel: float = -1.0) -> MeshInstance3D:
	var minimum := minf(dimensions.x, minf(dimensions.y, dimensions.z))
	var radius := minf(minimum * 0.31, 0.085) if bevel < 0.0 else bevel
	radius = clampf(radius, 0.0001, minimum * 0.48)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = rounded_box_mesh(dimensions, radius)
	instance.material_override = surface
	instance.position = center
	parent.add_child(instance)
	return instance


static func sphere(parent: Node3D, label: String, center: Vector3, dimensions: Vector3, surface: Material) -> MeshInstance3D:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = _sphere_mesh
	instance.material_override = surface
	instance.position = center
	instance.scale = dimensions
	parent.add_child(instance)
	return instance


static func cylinder(parent: Node3D, label: String, center: Vector3, radius: float, height: float, surface: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var upper_radius := radius if top_radius < 0.0 else top_radius
	var key := "%.5f:%.5f:%.5f" % [radius, height, upper_radius]
	if not _cylinder_meshes.has(key):
		var shape := CylinderMesh.new()
		shape.bottom_radius = radius
		shape.top_radius = upper_radius
		shape.height = height
		shape.radial_segments = 20
		_cylinder_meshes[key] = shape
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = _cylinder_meshes[key]
	instance.material_override = surface
	instance.position = center
	parent.add_child(instance)
	return instance


static func badge(parent: Node3D, label: String, center: Vector3, radius: float, surface: Material) -> MeshInstance3D:
	var instance := cylinder(parent, label, center, radius, 0.016, surface)
	instance.rotation_degrees.x = 90
	return instance


static func ring(parent: Node3D, label: String, center: Vector3, radius: float, thickness: float, surface: Material) -> MeshInstance3D:
	var key := "%.5f:%.5f" % [radius, thickness]
	if not _ring_meshes.has(key):
		var shape := TorusMesh.new()
		shape.inner_radius = radius - thickness
		shape.outer_radius = radius + thickness
		shape.rings = 24
		shape.ring_segments = 8
		_ring_meshes[key] = shape
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = _ring_meshes[key]
	instance.material_override = surface
	instance.position = center
	instance.rotation_degrees.x = 90
	parent.add_child(instance)
	return instance


static func create_prop(kind: String, size: Vector3, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop_" + kind
	var ink := material(Color("193b42"))
	var dark := material(Color("31575d"))
	var purple := material(Color("bd7773"))
	var lilac := material(Color("e8a493"))
	var teal := material(Color("78b6a6"))
	var cyan := material(Color("a8d3b8"))
	var gold := material(Color("caa15f"), 0.0, 0.07)
	var yellow := material(Color("ded3a3"))
	var pink := material(Color("d9897d"))
	var wood := material(Color("987566"))
	var cream := material(Color("e3d4b6"))
	var variant_id := posmod(variant, 4)
	match kind:
		"television":
			box(root, "StandFoot", Vector3(0, 0.04, 0.02), Vector3(0.62, 0.08, 0.60), dark)
			box(root, "Stand", Vector3(0, 0.22, -0.08), Vector3(0.12, 0.36, 0.12), ink)
			box(root, "ScreenCase", Vector3(0, 0.66, -0.08), Vector3(1.0, 0.68, 0.17), purple)
			box(root, "ScreenGlass", Vector3(0, 0.68, 0.012), Vector3(0.91, 0.54, 0.025), dark)
			sphere(root, "ScreenMoon", Vector3(0.24, 0.78, 0.035), Vector3(0.17, 0.17, 0.035), pink)
			box(root, "ScreenSkyline", Vector3(-0.19, 0.55, 0.04), Vector3(0.40, 0.14, 0.03), teal)
			box(root, "ScreenTower", Vector3(0.02, 0.61, 0.04), Vector3(0.12, 0.26, 0.03), cyan)
			box(root, "PowerLight", Vector3(0.39, 0.365, 0.025), Vector3(0.045, 0.02, 0.03), yellow)
			box(root, "ScreenHorizon", Vector3(0, 0.49, 0.06), Vector3(0.80, 0.025, 0.035), lilac)
		"sofa":
			box(root, "SofaBase", Vector3(0, 0.30, 0), Vector3(0.94, 0.22, 0.90), purple)
			box(root, "SofaBack", Vector3(0, 0.72, -0.36), Vector3(0.92, 0.56, 0.27), purple, 0.12)
			box(root, "LeftArm", Vector3(-0.42, 0.53, 0.04), Vector3(0.16, 0.42, 0.92), lilac, 0.075)
			box(root, "RightArm", Vector3(0.42, 0.53, 0.04), Vector3(0.16, 0.42, 0.92), lilac, 0.075)
			box(root, "LeftCushion", Vector3(-0.18, 0.47, 0.12), Vector3(0.33, 0.16, 0.60), lilac, 0.073)
			box(root, "RightCushion", Vector3(0.18, 0.47, 0.12), Vector3(0.33, 0.16, 0.60), lilac, 0.073)
			var pillow := box(root, "LimePillow", Vector3(-0.22, 0.70, -0.13), Vector3(0.24, 0.26, 0.12), yellow, 0.055)
			pillow.rotation_degrees.z = -12
			var pink_pillow := box(root, "PinkPillow", Vector3(0.23, 0.70, -0.12), Vector3(0.23, 0.25, 0.13), pink, 0.06)
			pink_pillow.rotation_degrees.z = 13
			box(root, "LeftCushionPiping", Vector3(-0.18, 0.475, 0.12), Vector3(0.342, 0.014, 0.612), cream)
			box(root, "RightCushionPiping", Vector3(0.18, 0.475, 0.12), Vector3(0.342, 0.014, 0.612), cream)
			for x: float in [-0.34, 0.34]:
				for z: float in [-0.31, 0.31]:
					box(root, "SofaLeg", Vector3(x, 0.095, z), Vector3(0.09, 0.19, 0.10), ink)
		"cabinet":
			box(root, "CabinetBody", Vector3(0, 0.52, 0), Vector3(0.96, 0.90, 0.90), wood)
			box(root, "CabinetTop", Vector3(0, 0.97, 0), Vector3(1.0, 0.06, 1.0), cream)
			box(root, "LeftDoor", Vector3(-0.235, 0.62, 0.464), Vector3(0.43, 0.58, 0.045), cream)
			box(root, "RightDoor", Vector3(0.235, 0.62, 0.464), Vector3(0.43, 0.58, 0.045), cream)
			box(root, "LeftHandle", Vector3(-0.08, 0.62, 0.493), Vector3(0.035, 0.15, 0.025), yellow)
			box(root, "RightHandle", Vector3(0.08, 0.62, 0.493), Vector3(0.035, 0.15, 0.025), yellow)
			box(root, "Drawer", Vector3(0, 0.19, 0.464), Vector3(0.89, 0.17, 0.045), pink)
			box(root, "DrawerPull", Vector3(0, 0.19, 0.493), Vector3(0.19, 0.025, 0.025), cream)
			box(root, "LeftFoot", Vector3(-0.35, 0.04, 0), Vector3(0.14, 0.08, 0.74), ink)
			box(root, "RightFoot", Vector3(0.35, 0.04, 0), Vector3(0.14, 0.08, 0.74), ink)
			box(root, "LeftDoorInset", Vector3(-0.235, 0.65, 0.493), Vector3(0.33, 0.45, 0.025), lilac)
			box(root, "RightDoorInset", Vector3(0.235, 0.65, 0.493), Vector3(0.33, 0.45, 0.025), teal)
		"desk":
			box(root, "Desktop", Vector3(0, 0.82, 0), Vector3(1.0, 0.10, 1.0), cream)
			for x: float in [-0.40, 0.40]:
				for z: float in [-0.39, 0.39]:
					box(root, "DeskLeg", Vector3(x, 0.385, z), Vector3(0.10, 0.77, 0.10), purple)
			box(root, "DrawerBody", Vector3(0.28, 0.58, 0.06), Vector3(0.30, 0.38, 0.67), wood)
			box(root, "DrawerOne", Vector3(0.28, 0.68, 0.41), Vector3(0.28, 0.15, 0.045), pink)
			box(root, "DrawerTwo", Vector3(0.28, 0.50, 0.41), Vector3(0.28, 0.15, 0.045), pink)
			box(root, "DrawerHandleOne", Vector3(0.28, 0.68, 0.44), Vector3(0.12, 0.025, 0.025), yellow)
			box(root, "DrawerHandleTwo", Vector3(0.28, 0.50, 0.44), Vector3(0.12, 0.025, 0.025), yellow)
			box(root, "Notebook", Vector3(-0.19, 0.89, 0.16), Vector3(0.29, 0.04, 0.32), teal)
			cylinder(root, "Mug", Vector3(0.23, 0.935, -0.24), 0.065, 0.13, purple)
			cylinder(root, "MugCoffee", Vector3(0.23, 0.998, -0.24), 0.051, 0.006, dark)
			box(root, "NotebookPages", Vector3(-0.19, 0.891, 0.16), Vector3(0.27, 0.018, 0.30), cream)
		"monitor":
			box(root, "MonitorFoot", Vector3(0, 0.04, 0.03), Vector3(0.65, 0.08, 0.80), dark)
			box(root, "MonitorStem", Vector3(0, 0.24, -0.08), Vector3(0.12, 0.38, 0.12), ink)
			box(root, "MonitorBody", Vector3(0, 0.66, -0.06), Vector3(1.0, 0.68, 0.19), teal)
			box(root, "MonitorScreen", Vector3(0, 0.69, 0.05), Vector3(0.90, 0.51, 0.035), dark)
			box(root, "WindowTitle", Vector3(0, 0.88, 0.075), Vector3(0.83, 0.07, 0.025), cyan)
			box(root, "WindowLeft", Vector3(-0.26, 0.64, 0.078), Vector3(0.20, 0.29, 0.025), purple)
			box(root, "WindowMain", Vector3(0.12, 0.68, 0.078), Vector3(0.43, 0.14, 0.025), pink)
			box(root, "WindowChart", Vector3(0.05, 0.51, 0.078), Vector3(0.29, 0.10, 0.025), yellow)
		"arcade":
			var shell_colors: Array[Color] = [Color("c4776d"), Color("4f968d"), Color("b3965f"), Color("365f6c")]
			var panel_colors: Array[Color] = [Color("e2d1b2"), Color("c6d8ba"), Color("d59781"), Color("8bbdaf")]
			var shell := material(shell_colors[variant_id])
			var panel := material(panel_colors[variant_id])
			box(root, "CabinetBase", Vector3(0, 0.27, 0.02), Vector3(0.83, 0.54, 0.84), shell)
			box(root, "CabinetUpper", Vector3(0, 0.72, -0.14), Vector3(0.83, 0.56, 0.65), shell)
			box(root, "ScreenBezel", Vector3(0, 0.72, 0.19), Vector3(0.73, 0.37, 0.065), panel)
			box(root, "ScreenRecess", Vector3(0, 0.72, 0.231), Vector3(0.65, 0.29, 0.025), ink)
			box(root, "Marquee", Vector3(0, 0.94, 0.21), Vector3(0.72, 0.11, 0.045), panel)
			box(root, "ControlPanel", Vector3(0, 0.48, 0.18), Vector3(1.0, 0.09, 0.60), panel)
			cylinder(root, "JoystickStem", Vector3(-0.24, 0.575, 0.22), 0.020, 0.12, ink)
			sphere(root, "JoystickBall", Vector3(-0.24, 0.64, 0.22), Vector3.ONE * 0.105, shell)
			cylinder(root, "ButtonOne", Vector3(0.15, 0.54, 0.27), 0.047, 0.04, pink)
			cylinder(root, "ButtonTwo", Vector3(0.30, 0.54, 0.21), 0.047, 0.04, teal)
			box(root, "CoinSlot", Vector3(0, 0.25, 0.458), Vector3(0.20, 0.12, 0.025), ink)
			box(root, "CoinLip", Vector3(0, 0.265, 0.478), Vector3(0.10, 0.015, 0.025), gold)
			box(root, "BaseTrim", Vector3(0, 0.055, 0.46), Vector3(0.77, 0.035, 0.04), panel)
			var side_emblem := badge(root, "SideEmblem", Vector3(0.423, 0.73, -0.11), 0.13, panel)
			side_emblem.rotation_degrees = Vector3(0, 0, -90)
			for symbol_x: float in [-0.19, 0.0, 0.19]:
				badge(root, "MarqueeDot", Vector3(symbol_x, 0.94, 0.243), 0.025, shell)
			match variant_id:
				0:
					sphere(root, "MintGhost", Vector3(0, 0.735, 0.26), Vector3(0.24, 0.18, 0.025), teal)
					sphere(root, "GhostEyeLeft", Vector3(-0.055, 0.765, 0.277), Vector3(0.029, 0.036, 0.015), ink)
					sphere(root, "GhostEyeRight", Vector3(0.055, 0.765, 0.277), Vector3(0.029, 0.036, 0.015), ink)
					box(root, "GhostSmile", Vector3(0, 0.69, 0.278), Vector3(0.055, 0.018, 0.015), cream)
				1:
					badge(root, "Planet", Vector3(0, 0.735, 0.262), 0.075, gold)
					var orbit := ring(root, "PlanetRing", Vector3(0, 0.735, 0.278), 0.12, 0.009, teal)
					orbit.scale.y = 0.45
					orbit.rotation_degrees.z = -22
					sphere(root, "PlanetMoon", Vector3(0.19, 0.79, 0.26), Vector3(0.035, 0.035, 0.025), cream)
				2:
					for road_x: float in [-0.11, 0.11]:
						box(root, "RacingLine", Vector3(road_x, 0.72, 0.26), Vector3(0.013, 0.23, 0.015), yellow)
					box(root, "TinyCar", Vector3(0, 0.71, 0.273), Vector3(0.11, 0.14, 0.025), pink)
					box(root, "CarWindow", Vector3(0, 0.745, 0.29), Vector3(0.065, 0.035, 0.015), cyan)
				3:
					sphere(root, "CherryLeft", Vector3(-0.07, 0.70, 0.26), Vector3(0.13, 0.13, 0.025), pink)
					sphere(root, "CherryRight", Vector3(0.07, 0.70, 0.26), Vector3(0.13, 0.13, 0.025), pink)
					var stalk := box(root, "CherryStem", Vector3(0, 0.79, 0.26), Vector3(0.021, 0.08, 0.015), cream)
					stalk.rotation_degrees.z = -14
					sphere(root, "CherryLeaf", Vector3(0.055, 0.81, 0.267), Vector3(0.10, 0.032, 0.02), teal)
		"vending":
			box(root, "VendingShell", Vector3(0, 0.50, 0), Vector3(1.0, 1.0, 1.0), teal)
			box(root, "DisplayRecess", Vector3(-0.12, 0.57, 0.505), Vector3(0.65, 0.61, 0.025), dark)
			box(root, "BrandPanel", Vector3(0, 0.915, 0.505), Vector3(0.88, 0.10, 0.025), yellow)
			box(root, "DisplayShelfOne", Vector3(-0.12, 0.54, 0.53), Vector3(0.61, 0.035, 0.035), cream)
			box(root, "DisplayShelfTwo", Vector3(-0.12, 0.30, 0.53), Vector3(0.61, 0.035, 0.035), cream)
			cylinder(root, "PinkCan", Vector3(-0.29, 0.66, 0.53), 0.065, 0.18, pink)
			cylinder(root, "LimeCan", Vector3(0.02, 0.66, 0.53), 0.065, 0.18, yellow)
			cylinder(root, "PurpleCan", Vector3(-0.29, 0.42, 0.53), 0.065, 0.18, purple)
			cylinder(root, "TealCan", Vector3(0.02, 0.42, 0.53), 0.065, 0.18, cyan)
			box(root, "ButtonBank", Vector3(0.36, 0.64, 0.525), Vector3(0.13, 0.35, 0.04), ink)
			box(root, "PurchaseButton", Vector3(0.36, 0.65, 0.555), Vector3(0.07, 0.09, 0.03), pink)
			box(root, "PickupSlot", Vector3(-0.10, 0.15, 0.52), Vector3(0.67, 0.12, 0.04), ink)
			for can_center: Vector3 in [Vector3(-0.29, 0.754, 0.53), Vector3(0.02, 0.754, 0.53),
				Vector3(-0.29, 0.514, 0.53), Vector3(0.02, 0.514, 0.53)]:
				cylinder(root, "CanLid", can_center, 0.059, 0.015, cream)
		"plant":
			cylinder(root, "FlowerPot", Vector3(0, 0.18, 0), 0.23, 0.36, pink, 0.32)
			cylinder(root, "PotRim", Vector3(0, 0.35, 0), 0.34, 0.07, wood)
			cylinder(root, "Earth", Vector3(0, 0.391, 0), 0.29, 0.015, dark)
			cylinder(root, "Trunk", Vector3(0, 0.62, 0), 0.035, 0.46, material(Color("657f62")))
			var leaf_left := sphere(root, "LeafLeft", Vector3(-0.21, 0.72, 0.05), Vector3(0.58, 0.18, 0.30), teal)
			leaf_left.rotation_degrees.z = -28
			var leaf_right := sphere(root, "LeafRight", Vector3(0.21, 0.80, -0.06), Vector3(0.58, 0.17, 0.31), material(Color("a7cf8b")))
			leaf_right.rotation_degrees.z = 28
			sphere(root, "LeafTop", Vector3(0, 0.88, 0), Vector3(0.26, 0.24, 0.25), yellow)
			var leaf_front := sphere(root, "LeafFront", Vector3(0.02, 0.58, 0.22), Vector3(0.22, 0.15, 0.50), teal)
			leaf_front.rotation_degrees.x = -20
		"safe":
			box(root, "SafeBody", Vector3(0, 0.50, -0.03), Vector3(1.0, 1.0, 0.94), dark, 0.14)
			box(root, "SafeDoor", Vector3(0, 0.51, 0.445), Vector3(0.87, 0.85, 0.16), gold, 0.072)
			box(root, "DoorInner", Vector3(0, 0.51, 0.55), Vector3(0.70, 0.68, 0.08), ink, 0.036)
			box(root, "HingeTop", Vector3(-0.43, 0.77, 0.49), Vector3(0.10, 0.15, 0.13), cream)
			box(root, "HingeBottom", Vector3(-0.43, 0.25, 0.49), Vector3(0.10, 0.15, 0.13), cream)
			var dial := cylinder(root, "SafeDial", Vector3(-0.16, 0.61, 0.61), 0.10, 0.045, cream)
			dial.rotation_degrees.x = 90
			box(root, "DialMark", Vector3(-0.16, 0.67, 0.638), Vector3(0.021, 0.042, 0.021), dark)
			box(root, "HandleStem", Vector3(0.16, 0.43, 0.62), Vector3(0.06, 0.06, 0.09), gold)
			ring(root, "HandWheel", Vector3(0.16, 0.43, 0.68), 0.125, 0.021, cream)
			box(root, "WheelSpokeHorizontal", Vector3(0.16, 0.43, 0.68), Vector3(0.25, 0.027, 0.03), cream)
			box(root, "WheelSpokeVertical", Vector3(0.16, 0.43, 0.68), Vector3(0.027, 0.25, 0.03), cream)
			box(root, "GoldBadge", Vector3(0.10, 0.80, 0.60), Vector3(0.25, 0.045, 0.025), gold)
			for screw_center: Vector3 in [Vector3(-0.355, 0.865, 0.538), Vector3(0.355, 0.865, 0.538),
				Vector3(-0.355, 0.155, 0.538), Vector3(0.355, 0.155, 0.538)]:
				badge(root, "DoorScrew", screw_center, 0.021, dark)
		"dummy":
			box(root, "LeftLeg", Vector3(-0.16, 0.13, 0), Vector3(0.20, 0.26, 0.32), ink)
			box(root, "RightLeg", Vector3(0.16, 0.13, 0), Vector3(0.20, 0.26, 0.32), ink)
			box(root, "Body", Vector3(0, 0.43, 0), Vector3(0.58, 0.39, 0.36), material(Color("4b787c")), 0.11)
			box(root, "LeftArm", Vector3(-0.37, 0.40, 0), Vector3(0.14, 0.34, 0.19), material(Color("4b787c")), 0.065)
			box(root, "RightArm", Vector3(0.37, 0.40, 0), Vector3(0.14, 0.34, 0.19), material(Color("4b787c")), 0.065)
			box(root, "Tie", Vector3(0, 0.46, 0.195), Vector3(0.09, 0.25, 0.03), gold)
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0, 0.745, 0.015)
			root.add_child(head)
			sphere(head, "CartoonHead", Vector3.ZERO, Vector3(0.73, 0.49, 0.60), cream)
			sphere(head, "SidePartHair", Vector3(-0.025, 0.165, -0.045), Vector3(0.69, 0.17, 0.54), dark)
			sphere(head, "LeftEye", Vector3(-0.115, 0.035, 0.286), Vector3(0.064, 0.070, 0.035), ink)
			sphere(head, "RightEye", Vector3(0.115, 0.035, 0.286), Vector3(0.064, 0.070, 0.035), ink)
			sphere(head, "Nose", Vector3(0, -0.025, 0.30), Vector3(0.14, 0.11, 0.15), pink)
			var mouth := box(head, "DispleasedMouth", Vector3(0.015, -0.125, 0.255), Vector3(0.15, 0.027, 0.035), ink)
			mouth.rotation_degrees.z = -8
			var brow_left := box(head, "LeftBrow", Vector3(-0.12, 0.105, 0.267), Vector3(0.12, 0.032, 0.035), dark)
			brow_left.rotation_degrees.z = -16
			var brow_right := box(head, "RightBrow", Vector3(0.12, 0.105, 0.267), Vector3(0.12, 0.032, 0.035), dark)
			brow_right.rotation_degrees.z = 16
			sphere(head, "LeftCheek", Vector3(-0.235, -0.06, 0.225), Vector3(0.09, 0.045, 0.025), pink)
			sphere(head, "RightCheek", Vector3(0.235, -0.06, 0.225), Vector3(0.09, 0.045, 0.025), pink)
		"shelf":
			box(root, "LeftWall", Vector3(-0.46, 0.50, 0), Vector3(0.08, 1.0, 1.0), ink)
			box(root, "RightWall", Vector3(0.46, 0.50, 0), Vector3(0.08, 1.0, 1.0), ink)
			box(root, "ShelfBack", Vector3(0, 0.50, -0.45), Vector3(0.84, 1.0, 0.10), dark)
			for shelf_y: float in [0.045, 0.36, 0.68, 0.96]:
				box(root, "ShelfBoard", Vector3(0, shelf_y, 0), Vector3(0.92, 0.06, 1.0), dark)
			box(root, "LowerBin", Vector3(-0.21, 0.19, 0.11), Vector3(0.32, 0.23, 0.55), teal, 0.06)
			badge(root, "BinSticker", Vector3(-0.21, 0.20, 0.395), 0.060, cream)
			box(root, "LowerParcel", Vector3(0.20, 0.18, 0.11), Vector3(0.26, 0.22, 0.51), cream)
			badge(root, "ParcelSticker", Vector3(0.20, 0.18, 0.378), 0.052, pink)
			box(root, "MiddleBookCoral", Vector3(-0.28, 0.51, 0.09), Vector3(0.11, 0.24, 0.48), pink)
			var leaning_book := box(root, "MiddleBookMint", Vector3(-0.14, 0.50, 0.09), Vector3(0.105, 0.22, 0.44), cyan)
			leaning_book.rotation_degrees.z = -9
			cylinder(root, "MiddleBottle", Vector3(0.21, 0.495, 0.17), 0.085, 0.21, gold, 0.055)
			cylinder(root, "BottleNeck", Vector3(0.21, 0.615, 0.17), 0.038, 0.04, gold)
			cylinder(root, "BottleLid", Vector3(0.21, 0.638, 0.17), 0.049, 0.022, teal)
			badge(root, "BottleSticker", Vector3(0.21, 0.49, 0.259), 0.040, cream)
			cylinder(root, "TopCandyJar", Vector3(-0.23, 0.81, 0.12), 0.115, 0.19, pink)
			cylinder(root, "CandyJarLid", Vector3(-0.23, 0.916, 0.12), 0.124, 0.025, cream)
			badge(root, "CandyJarSticker", Vector3(-0.23, 0.81, 0.24), 0.048, ink)
			box(root, "TopParcel", Vector3(0.15, 0.81, 0.05), Vector3(0.35, 0.19, 0.55), cyan)
			box(root, "ParcelStripe", Vector3(0.15, 0.81, 0.34), Vector3(0.065, 0.19, 0.025), gold)
		_:
			box(root, "Crate", Vector3(0, 0.50, 0), Vector3.ONE, purple)
			box(root, "CrateStripe", Vector3(0, 0.50, 0.505), Vector3(0.12, 0.95, 0.025), yellow)
	root.scale = Vector3(maxf(size.x, 0.01), maxf(size.y, 0.01), maxf(size.z, 0.01))
	return root


static func create_hero() -> Node3D:
	var root := Node3D.new()
	root.name = "CatHammerHero"
	var ink := material(Color("203f45"))
	var fur := material(Color("e7cda4"))
	var muzzle := material(Color("ecdbbc"))
	var purple := material(Color("c58378"))
	var lime := material(Color("d9d09e"))
	var teal := material(Color("76b5a5"))
	var pink := material(Color("d89185"))
	box(root, "LeftShoe", Vector3(-0.13, 0.085, 0.07), Vector3(0.20, 0.17, 0.30), purple)
	box(root, "RightShoe", Vector3(0.13, 0.085, 0.07), Vector3(0.20, 0.17, 0.30), purple)
	box(root, "LeftLeg", Vector3(-0.12, 0.27, 0), Vector3(0.15, 0.24, 0.17), fur)
	box(root, "RightLeg", Vector3(0.12, 0.27, 0), Vector3(0.15, 0.24, 0.17), fur)
	box(root, "Shorts", Vector3(0, 0.43, 0), Vector3(0.42, 0.20, 0.29), ink)
	box(root, "HoodieBody", Vector3(0, 0.65, 0), Vector3(0.51, 0.47, 0.37), purple, 0.14)
	box(root, "WaistBand", Vector3(0, 0.46, 0.005), Vector3(0.43, 0.065, 0.32), lime)
	box(root, "ChestBadge", Vector3(0, 0.66, 0.194), Vector3(0.11, 0.10, 0.035), lime)
	sphere(root, "CatHead", Vector3(0, 1.045, 0.025), Vector3(0.69, 0.57, 0.54), fur)
	var ear_left := cylinder(root, "LeftEar", Vector3(-0.225, 1.325, 0.015), 0.125, 0.19, fur, 0.018)
	ear_left.rotation_degrees.z = 12
	var ear_right := cylinder(root, "RightEar", Vector3(0.225, 1.325, 0.015), 0.125, 0.19, fur, 0.018)
	ear_right.rotation_degrees.z = -12
	sphere(root, "LeftEarPink", Vector3(-0.225, 1.327, 0.070), Vector3(0.09, 0.10, 0.045), pink)
	sphere(root, "RightEarPink", Vector3(0.225, 1.327, 0.070), Vector3(0.09, 0.10, 0.045), pink)
	box(root, "HeadphoneBridge", Vector3(0, 1.295, -0.025), Vector3(0.67, 0.065, 0.14), lime)
	box(root, "HeadphoneLeftStem", Vector3(-0.335, 1.17, -0.025), Vector3(0.06, 0.25, 0.14), ink)
	box(root, "HeadphoneRightStem", Vector3(0.335, 1.17, -0.025), Vector3(0.06, 0.25, 0.14), ink)
	sphere(root, "LeftEarpad", Vector3(-0.345, 1.075, 0), Vector3(0.16, 0.25, 0.26), lime)
	sphere(root, "RightEarpad", Vector3(0.345, 1.075, 0), Vector3(0.16, 0.25, 0.26), lime)
	sphere(root, "LeftEye", Vector3(-0.12, 1.095, 0.274), Vector3(0.074, 0.105, 0.04), ink)
	sphere(root, "RightEye", Vector3(0.12, 1.095, 0.274), Vector3(0.074, 0.105, 0.04), ink)
	sphere(root, "LeftEyeShine", Vector3(-0.13, 1.115, 0.296), Vector3(0.024, 0.029, 0.013), muzzle)
	sphere(root, "RightEyeShine", Vector3(0.11, 1.115, 0.296), Vector3(0.024, 0.029, 0.013), muzzle)
	sphere(root, "LeftMuzzle", Vector3(-0.060, 0.985, 0.274), Vector3(0.15, 0.11, 0.10), muzzle)
	sphere(root, "RightMuzzle", Vector3(0.060, 0.985, 0.274), Vector3(0.15, 0.11, 0.10), muzzle)
	sphere(root, "Nose", Vector3(0, 1.025, 0.324), Vector3(0.075, 0.05, 0.045), pink)
	sphere(root, "Smile", Vector3(0, 0.956, 0.301), Vector3(0.055, 0.032, 0.025), ink)
	sphere(root, "LeftBlush", Vector3(-0.23, 1.0, 0.219), Vector3(0.085, 0.045, 0.035), pink)
	sphere(root, "RightBlush", Vector3(0.23, 1.0, 0.219), Vector3(0.085, 0.045, 0.035), pink)
	var stripe_mat := material(Color("d9aa7d"))
	box(root, "ForeheadStripeLeft", Vector3(-0.07, 1.229, 0.21), Vector3(0.033, 0.080, 0.025), stripe_mat)
	box(root, "ForeheadStripeRight", Vector3(0.07, 1.229, 0.21), Vector3(0.033, 0.080, 0.025), stripe_mat)
	var left_arm := box(root, "LeftArm", Vector3(-0.27, 0.68, 0.12), Vector3(0.14, 0.30, 0.16), purple)
	left_arm.rotation_degrees.x = -35
	var right_arm := box(root, "RightArm", Vector3(0.27, 0.72, 0.13), Vector3(0.14, 0.29, 0.16), purple)
	right_arm.rotation_degrees.x = -40
	sphere(root, "LeftPaw", Vector3(-0.27, 0.57, 0.21), Vector3.ONE * 0.16, fur)
	sphere(root, "RightPaw", Vector3(0.30, 0.67, 0.24), Vector3.ONE * 0.16, fur)
	var tail := cylinder(root, "TailBase", Vector3(0, 0.47, -0.28), 0.052, 0.36, fur)
	tail.rotation_degrees.x = -60
	sphere(root, "TailTip", Vector3(0, 0.57, -0.44), Vector3(0.12, 0.20, 0.13), fur)
	var hammer := Node3D.new()
	hammer.name = "Hammer"
	hammer.position = Vector3(0.32, 0.68, 0.25)
	hammer.rotation_degrees.z = -14
	root.add_child(hammer)
	cylinder(hammer, "HammerHandle", Vector3(0, 0.19, 0), 0.038, 0.64, material(Color("d6ad7b")))
	cylinder(hammer, "Grip", Vector3(0, -0.035, 0), 0.047, 0.17, purple)
	box(hammer, "HammerHead", Vector3(0, 0.54, 0), Vector3(0.62, 0.28, 0.34), teal, 0.10)
	var cap_left := cylinder(hammer, "LeftHammerCap", Vector3(-0.29, 0.54, 0), 0.195, 0.105, lime)
	cap_left.rotation_degrees.z = 90
	var cap_right := cylinder(hammer, "RightHammerCap", Vector3(0.29, 0.54, 0), 0.195, 0.105, lime)
	cap_right.rotation_degrees.z = 90
	box(hammer, "HammerStripe", Vector3(0, 0.54, 0.175), Vector3(0.13, 0.18, 0.03), material(Color("c9ddc3")))
	cylinder(hammer, "GripRingLower", Vector3(0, -0.105, 0), 0.052, 0.035, lime)
	cylinder(hammer, "GripRingUpper", Vector3(0, 0.04, 0), 0.052, 0.035, lime)
	return root
