extends Node3D
## Ritratti delle unità per le carte in basso: apri tools/genera_ritratti.tscn e avvialo con F6
## (serve la finestra, non funziona in --headless). Per ogni scheda di data/units/ fotografa il
## modello (Aspetto → Visual) e salva data/icons/<id>.res, poi lo assegna a Aspetto → Icon.
## Rilancialo quando cambi il modello di un'unità.
##   godot --path . res://tools/genera_ritratti.tscn

const T := 100.0
const SIZE := Vector2i(320, 400)       ## risoluzione della foto
const OUT := Vector2i(120, 138)        ## ritratto salvato (proporzioni della finestra sulla carta)
const TEAM := Color(0.25, 0.45, 0.95)

## Inquadratura per tipo di modello: altezza del punto guardato e distanza (in altezze del modello),
## rotazione del soldato verso la camera.
const FRAMING := {
	"infantry": {"y": 0.74, "dist": 1.7, "yaw": -30.0},
	"monster": {"y": 0.72, "dist": 1.7, "yaw": -30.0},
	"cavalry": {"y": 0.72, "dist": 1.5, "yaw": 38.0},   # il cavaliere da vicino, con la testa del cavallo di lato
	"artillery": {"y": 0.40, "dist": 4.4, "yaw": -35.0},
}


func _ready() -> void:
	get_viewport().transparent_bg = true
	get_window().size = SIZE
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 160, 0)
	sun.light_energy = 1.25
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -40, 0)
	fill.light_energy = 0.35
	add_child(fill)
	var mi := MultiMeshInstance3D.new()
	add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://data/icons")
	for f in DirAccess.get_files_at("res://data/units"):
		if not f.ends_with(".tres"):
			continue
		var path := "res://data/units/" + f
		var u: UnitStats = load(path)
		var v: UnitVisual = u.visual if u.visual != null and u.visual.mesh != null else UnitVisual.preset(u.mesh_kind)
		var kind := "infantry"
		if u.role in ["cavalry", "general"]:
			kind = "cavalry"
		elif u.role == "monster":
			kind = "monster"
		elif u.role == "artillery":
			kind = "artillery"
		var fr: Dictionary = FRAMING[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = v.mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, deg_to_rad(fr["yaw"])), Vector3.ZERO))
		mm.set_instance_color(0, TEAM * u.tint)
		mm.set_instance_custom_data(0, Color(1, 0, T, 0))
		mi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = load("res://scripts/unit.gdshader")
		v.apply_to(mat)
		mi.material_override = mat
		var h := u.model_height
		var target := Vector3(0, h * float(fr["y"]), 0)
		cam.position = target + Vector3(0.0, 0.16, -1.0).normalized() * h * float(fr["dist"])
		cam.look_at(target)
		RenderingServer.global_shader_parameter_set("unit_anim_time", T)
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var icon := _portrait(img, kind)
		var tex := ImageTexture.create_from_image(icon)
		var out := "res://data/icons/%s.res" % u.id
		ResourceSaver.save(tex, out)
		u.icon = ResourceLoader.load(out, "", ResourceLoader.CACHE_MODE_REPLACE)
		ResourceSaver.save(u, path)
		print("ritratto: %s -> %s" % [u.display_name, out])
	get_tree().quit()


## Ritaglia la foto attorno al corpo (le aste sottili di lance e bandiere non contano)
## e la porta alle proporzioni della finestra della carta.
func _portrait(img: Image, kind: String) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var rows := PackedInt32Array()
	rows.resize(h)
	var cols := PackedInt32Array()
	cols.resize(w)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.05:
				rows[y] += 1
				cols[x] += 1
	var min_px := 10
	var r := Rect2i()
	var y0 := -1
	var y1 := -1
	for y in h:
		if rows[y] > min_px:
			if y0 < 0:
				y0 = y
			y1 = y
	var x0 := -1
	var x1 := -1
	for x in w:
		if cols[x] > min_px:
			if x0 < 0:
				x0 = x
			x1 = x
	if y0 < 0 or x0 < 0:
		r = Rect2i(0, 0, w, h)
	else:
		r = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	var aspect := float(OUT.x) / OUT.y
	# un po' di margine attorno
	r = r.grow(4).intersection(Rect2i(0, 0, w, h))
	if float(r.size.x) / r.size.y < aspect:
		if kind == "artillery":
			var nw := int(r.size.y * aspect)
			r = Rect2i(r.position.x - (nw - r.size.x) / 2, r.position.y, nw, r.size.y)
		else:
			# più alto che largo: si tiene la parte alta (testa e busto)
			r.size.y = int(r.size.x / aspect)
	else:
		var nh := int(r.size.x / aspect)
		r = Rect2i(r.position.x, r.position.y - (nh - r.size.y) / 2, r.size.x, nh)
	var canvas := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var src := r.intersection(Rect2i(0, 0, w, h))
	canvas.blit_rect(img, src, src.position - r.position)
	canvas.resize(OUT.x, OUT.y, Image.INTERPOLATE_LANCZOS)
	return canvas
