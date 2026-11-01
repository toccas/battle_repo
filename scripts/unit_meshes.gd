class_name UnitMeshes
extends RefCounted
## Le mesh semplici del prototipo (capsule e scatole), costruite in codice.
## tools/generate_units.gd le salva in res://data/meshes/ così compaiono nell'Inspector delle
## unità e si possono sostituire con modelli veri (vedi UnitVisual).

const KINDS := ["infantry", "spear", "archer", "cavalry", "general", "monster", "catapult", "cannon"]


static func build(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"spear":
			_add(st, _capsule(0.28, 1.75), Vector3(0, 0.875, 0))
			_add(st, _box(Vector3(0.55, 0.75, 0.08)), Vector3(0, 0.95, -0.3))
			_add(st, _box(Vector3(0.05, 0.05, 2.6)), Vector3(0.28, 1.25, -0.9))
		"archer":
			_add(st, _capsule(0.26, 1.7), Vector3(0, 0.85, 0))
			_add(st, _box(Vector3(0.18, 0.6, 0.18)), Vector3(0.12, 1.15, 0.28))
		"cavalry", "general":
			_add(st, _box(Vector3(0.7, 0.9, 2.0)), Vector3(0, 1.05, 0))
			_add(st, _box(Vector3(0.3, 0.55, 0.7)), Vector3(0, 1.6, -1.1))
			_add(st, _box(Vector3(0.18, 0.75, 0.18)), Vector3(0.22, 0.38, -0.75))
			_add(st, _box(Vector3(0.18, 0.75, 0.18)), Vector3(-0.22, 0.38, -0.75))
			_add(st, _box(Vector3(0.18, 0.75, 0.18)), Vector3(0.22, 0.38, 0.75))
			_add(st, _box(Vector3(0.18, 0.75, 0.18)), Vector3(-0.22, 0.38, 0.75))
			_add(st, _capsule(0.25, 1.1), Vector3(0, 2.05, 0.1))
			_add(st, _box(Vector3(0.05, 0.05, 2.8)), Vector3(0.3, 2.0, -1.1))
			if kind == "general":
				_add(st, _box(Vector3(0.06, 2.6, 0.06)), Vector3(-0.3, 3.0, 0.4))
				_add(st, _box(Vector3(0.9, 0.6, 0.03)), Vector3(-0.75, 4.0, 0.4))
		"catapult":
			# telaio su ruote, braccio inclinato con il cucchiaio, contrappeso
			_add(st, _box(Vector3(2.4, 0.5, 4.2)), Vector3(0, 0.9, 0))
			for wx in [-1.3, 1.3]:
				for wz in [-1.5, 1.5]:
					_add_t(st, _cyl(0.55, 0.3), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx, 0.55, wz)))
			_add(st, _box(Vector3(0.3, 2.2, 0.3)), Vector3(-0.9, 2.1, 0.4))
			_add(st, _box(Vector3(0.3, 2.2, 0.3)), Vector3(0.9, 2.1, 0.4))
			_add(st, _box(Vector3(2.1, 0.3, 0.3)), Vector3(0, 3.1, 0.4))
			_add_t(st, _box(Vector3(0.3, 0.3, 4.6)), Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 2.6, -0.4)))
			_add(st, _box(Vector3(0.9, 0.4, 0.9)), Vector3(0, 4.1, -2.2))
			_add(st, _box(Vector3(1.1, 1.0, 1.1)), Vector3(0, 1.6, 1.6))
		"cannon":
			# affusto con due ruote e canna rivolta in avanti (-Z)
			_add(st, _box(Vector3(1.0, 0.5, 2.6)), Vector3(0, 0.7, 0.5))
			for wx in [-0.85, 0.85]:
				_add_t(st, _cyl(0.75, 0.25), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx, 0.75, 0.0)))
			_add_t(st, _cyl(0.32, 3.2), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.12), Vector3(0, 1.25, -0.9)))
			_add_t(st, _cyl(0.42, 0.6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.12), Vector3(0, 1.1, 0.5)))
		"monster":
			_add(st, _capsule(0.85, 3.4), Vector3(0, 1.7, 0))
			_add(st, _box(Vector3(0.75, 0.7, 0.8)), Vector3(0, 3.55, -0.35))
			_add(st, _box(Vector3(0.38, 1.7, 0.38)), Vector3(1.05, 2.1, -0.2))
			_add(st, _box(Vector3(0.38, 1.7, 0.38)), Vector3(-1.05, 2.1, -0.2))
		_:
			_add(st, _capsule(0.28, 1.75), Vector3(0, 0.875, 0))
			_add(st, _box(Vector3(0.55, 0.75, 0.08)), Vector3(0, 0.95, -0.3))
	var mesh := st.commit()
	mesh.resource_name = kind
	return mesh


static func _add(st: SurfaceTool, m: Mesh, at: Vector3) -> void:
	st.append_from(m, 0, Transform3D(Basis(), at))


static func _add_t(st: SurfaceTool, m: Mesh, t: Transform3D) -> void:
	st.append_from(m, 0, t)


static func _cyl(r: float, h: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c


static func _capsule(r: float, h: float) -> Mesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c


static func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b
