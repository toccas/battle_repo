@tool
extends Node
## Cottura delle animazioni (VAT, Vertex Animation Textures).
##
## I soldati sono disegnati in massa con MultiMesh, che non può usare scheletri: le animazioni
## di un modello con scheletro vanno quindi "cotte" in una texture, che contiene la posizione
## di ogni vertice in ogni fotogramma. Lo shader dei soldati la legge e muove i vertici.
##
## Nell'editor: apri tools/vat_baker.tscn e seleziona il nodo. Qui sotto:
## 1. "Source File": il modello (.glb o .gltf) già nel progetto, oppure "Source Folder" per
##    cuocere tutti i modelli di una cartella;
## 2. "Assign To" (facoltativo): la scheda dell'unità che userà il modello (data/units/*.tres);
## 3. spunta "Bake Now".
## Le animazioni si riconoscono dal nome (Idle, Walk, Run, Attack, HitRecieve, Death...); se un
## nome non viene trovato, scrivilo a mano nel campo dello stato. Nasce data/visuals/<nome>/aspetto.tres,
## già assegnato all'unità scelta (altrimenti trascinalo su Aspetto → Visual).
## Da riga di comando:
##   godot --headless --path . --script res://tools/vat_bake_cli.gd -- --src=res://data/.../Modello.gltf --unit=res://data/units/troll.tres

## Il modello con scheletro e animazioni (.glb o .gltf).
@export_file("*.glb", "*.gltf") var source_file := ""
## In alternativa: una cartella; si cuociono tutti i .glb/.gltf che contiene.
@export_dir var source_folder := ""
## Dove salvare: per ogni modello una sottocartella con il suo nome.
@export_dir var output_dir := "res://data/visuals"
## La scheda dell'unità a cui assegnare l'aspetto cotto (solo con un singolo modello).
@export var assign_to: UnitStats
@export_group("Animazione per ogni stato (vuoto = riconosci dal nome, - = procedurale)")
@export var idle := ""
@export var walk := ""
@export var run := ""
@export var attack := ""
@export var shoot := ""
@export var hit := ""
@export var death := ""
@export_group("Modello")
## Altezza a cui scalare il modello (m). 0 = l'altezza dell'unità scelta in "Assign To",
## o la dimensione originale del modello se non c'è un'unità.
@export var target_height := 0.0
## I modelli glTF guardano verso +Z, i soldati verso -Z: lascia attivo per girarli.
@export var turn_around := true
## Preimpostazione procedurale per gli stati senza animazione cotta ("auto" = dal tipo dell'unità).
@export_enum("auto", "infantry", "cavalry", "monster", "catapult", "cannon") var fallback_preset := "auto"
@export var fps := 20.0
@export_group("")
## Spunta per cuocere (nell'editor). Il risultato compare nel pannello Output.
@export var bake_now := false:
	set(v):
		if v and Engine.is_editor_hint():
			for line in run_bake():
				print(line)

## Nomi tipici delle animazioni per ogni stato, in ordine di preferenza.
const AUTO_NAMES := {
	"death": ["death", "die", "dying", "dead"],
	"hit": ["hitrecieve", "hitreceive", "hitreact", "gethit", "damage", "hurt", "hit"],
	"shoot": ["shoot", "bow", "throw", "cast", "spell"],
	"attack": ["attack", "punch", "slash", "sword", "stab", "bite", "swing", "smash"],
	"run": ["run", "sprint", "gallop", "charge"],
	"walk": ["walk"],
	"idle": ["idle", "stand", "breath", "wait"],
}


func _mapping() -> Dictionary:
	return {"idle": idle, "walk": walk, "run": run, "attack": attack, "shoot": shoot, "hit": hit, "death": death}


## Cuoce secondo i campi qui sopra; restituisce le righe del resoconto.
func run_bake() -> PackedStringArray:
	var out := PackedStringArray()
	var files := PackedStringArray()
	if source_folder != "":
		for f in DirAccess.get_files_at(source_folder):
			if f.get_extension().to_lower() in ["glb", "gltf"]:
				files.append(source_folder.path_join(f))
	elif source_file != "":
		files.append(source_file)
	if files.is_empty():
		return PackedStringArray(["Scegli un modello in Source File o una cartella in Source Folder."])
	for f in files:
		var unit := assign_to if files.size() == 1 else null
		var res := bake_model(f, _mapping(), output_dir, target_height, turn_around, fps, fallback_preset, unit)
		out.append(res.get("message", ""))
	return out


## Cottura completa di un modello: riconosce le animazioni, cuoce, salva in
## <out_root>/<nome del modello>/ e, se c'è, assegna l'aspetto all'unità.
static func bake_model(path: String, mapping: Dictionary, out_root: String, height: float, turn: bool,
		p_fps: float, preset: String, unit: UnitStats = null, tree: SceneTree = null) -> Dictionary:
	var name := path.get_file().get_basename()
	var out_dir := out_root.path_join(name.to_snake_case())
	if height <= 0.0 and unit != null:
		height = unit.model_height
	if preset == "auto":
		preset = _preset_for(unit.mesh_kind) if unit != null else "infantry"
	var res := bake_file(path, mapping, out_dir, height, turn, p_fps, preset, tree)
	if not res.get("ok", false):
		res["message"] = "%s: %s" % [name, res.get("message", "")]
		return res
	if unit != null:
		unit.visual = ResourceLoader.load(res["visual_path"], "", ResourceLoader.CACHE_MODE_REPLACE)
		unit.model_height = res["height"]
		ResourceSaver.save(unit, unit.resource_path)
		res["message"] += "\n   assegnato a %s (%s)" % [unit.display_name, unit.resource_path]
	return res


static func _preset_for(kind: String) -> String:
	match kind:
		"cavalry", "general":
			return "cavalry"
		"monster", "catapult", "cannon":
			return kind
	return "infantry"


## Associa a ogni stato un'animazione del modello: quelle scritte a mano, poi per nome.
## Restituisce {stato: nome} ("" = procedurale).
static func auto_map(available: PackedStringArray, manual: Dictionary) -> Dictionary:
	var result := {}
	var used := {}
	for st: String in manual:
		var m: String = manual[st]
		if m == "-":
			result[st] = ""
		elif m != "":
			result[st] = m
			used[m] = true
	for st: String in AUTO_NAMES:
		if result.has(st):
			continue
		result[st] = ""
		for key: String in AUTO_NAMES[st]:
			var best := ""
			for a in available:
				var clean := a.to_lower().replace("_", "").replace(" ", "").replace("-", "")
				if clean.contains(key) and not used.has(a) and (best == "" or a.length() < best.length()):
					best = a
			if best != "":
				result[st] = best
				used[best] = true
				break
	return result


## Carica il modello, cuoce e salva. Restituisce {"ok", "message", "visual_path", ...}.
static func bake_file(path: String, mapping: Dictionary, out_dir: String, height: float, turn: bool,
		p_fps: float, fallback: String, tree: SceneTree = null) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if doc.append_from_file(abs_path, state) != OK:
		return {"ok": false, "message": "Impossibile leggere %s" % path}
	var root: Node = doc.generate_scene(state)
	if root == null:
		return {"ok": false, "message": "Il file non contiene una scena."}
	var t := tree if tree != null else (Engine.get_main_loop() as SceneTree)
	t.root.add_child(root)
	var res := bake_node(root, mapping, out_dir, height, turn, p_fps, fallback)
	root.queue_free()
	return res


static func bake_node(root: Node, mapping: Dictionary, out_dir: String, height: float, turn: bool,
		p_fps: float, fallback: String) -> Dictionary:
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		return {"ok": false, "message": "Nel modello non ci sono mesh."}
	var available := PackedStringArray(player.get_animation_list()) if player != null else PackedStringArray()
	mapping = auto_map(available, mapping)
	# 1. dati dei vertici di tutte le superfici
	var surfaces: Array[Dictionary] = []
	var total := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var mat := mi.get_active_material(s)
			surfaces.append({"mi": mi, "arr": arr, "verts": verts, "nrm": nrm, "idx": idx, "bones": bones, "weights": weights,
					"per": (bones.size() / verts.size()) if verts.size() > 0 else 0, "first": total, "mat": mat})
			total += verts.size()
	# 2. fotogrammi di ogni stato
	var frames: Array = []   # per fotogramma: [PackedVector3Array posizioni, PackedVector3Array normali]
	var ranges := {}
	var missing := PackedStringArray()
	for st: String in UnitVisual.STATES:
		var name: String = mapping.get(st, "")
		if name == "":
			continue
		if not available.has(name):
			missing.append(name)
			continue
		var anim := player.get_animation(name)
		var count := maxi(2, int(ceil(anim.length * p_fps)) + (0 if anim.loop_mode != Animation.LOOP_NONE else 1))
		ranges[st] = {"first": frames.size(), "count": count, "length": anim.length, "loop": anim.loop_mode != Animation.LOOP_NONE}
		player.play(name)
		for f in count:
			var tt := minf(f / p_fps, anim.length)
			player.seek(tt, true)
			frames.append(_pose(root, surfaces, total))
		player.stop()
	if not missing.is_empty():
		return {"ok": false, "message": "Animazioni non trovate: %s. Nel modello ci sono: %s" % [", ".join(missing), ", ".join(available)]}
	if frames.is_empty():
		frames.append(_pose(root, surfaces, total))   # nessuna animazione: solo la posa di riposo
	# 3. trasformazione per portare il modello a terra, all'altezza voluta, rivolto verso -Z
	# l'altezza si misura sul corpo: armi e oggetti in mano (lance, stendardi...) non contano
	var rest: PackedVector3Array = frames[0][0]
	var body := _body_mask(surfaces, total)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for i in total:
		if body[i] == 1:
			lo = lo.min(rest[i])
			hi = hi.max(rest[i])
	var sc := height / maxf(hi.y - lo.y, 0.0001) if height > 0.0 else 1.0
	var basis := Basis().scaled(Vector3.ONE * sc)
	if turn:
		basis = Basis(Vector3.UP, PI) * basis
	var center := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var fit := Transform3D(basis, -(basis * center))
	# 4. texture: una riga (o più) per fotogramma, un texel per vertice
	var w := mini(total, 2048)
	var rows := int(ceil(float(total) / w))
	var h := frames.size() * rows
	if h > 16384:
		return {"ok": false, "message": "Troppi fotogrammi o vertici: abbassa gli fps o semplifica il modello."}
	var pimg := Image.create(w, h, false, Image.FORMAT_RGBAH)
	var nimg := Image.create(w, h, false, Image.FORMAT_RGBAH)
	for f in frames.size():
		var ps: PackedVector3Array = frames[f][0]
		var ns: PackedVector3Array = frames[f][1]
		for i in total:
			var p := fit * ps[i]
			var n := (fit.basis * ns[i]).normalized()
			var px := Vector2i(i % w, f * rows + i / w)
			pimg.set_pixelv(px, Color(p.x, p.y, p.z, 1.0))
			nimg.set_pixelv(px, Color(n.x, n.y, n.z, 1.0))
	# 5. mesh di uscita: posa di riposo, UV2 = posizione del vertice nella texture
	var mesh := ArrayMesh.new()
	var albedo: Texture2D = null
	for sd in surfaces:
		var arr: Array = (sd["arr"] as Array).duplicate()
		var n: int = (sd["verts"] as PackedVector3Array).size()
		var first: int = sd["first"]
		var pv := PackedVector3Array()
		var nv := PackedVector3Array()
		var uv2 := PackedVector2Array()
		pv.resize(n)
		nv.resize(n)
		uv2.resize(n)
		for i in n:
			var gi := first + i
			pv[i] = fit * (frames[0][0] as PackedVector3Array)[gi]
			nv[i] = (fit.basis * (frames[0][1] as PackedVector3Array)[gi]).normalized()
			uv2[i] = Vector2(gi % w, gi / w)
		arr[Mesh.ARRAY_VERTEX] = pv
		arr[Mesh.ARRAY_NORMAL] = nv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		arr[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat = sd["mat"]
		if albedo == null and mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			albedo = (mat as BaseMaterial3D).albedo_texture
	# 6. aspetto: animazioni cotte dove ci sono, procedurali negli altri stati
	var visual := UnitVisual.preset(fallback, mesh)
	visual.team_color_strength = 0.45 if albedo != null else 1.0
	for st: String in ranges:
		var r: Dictionary = ranges[st]
		var once := st in ["attack", "shoot", "hit", "death"]
		var a := UnitAnimation.make({"vat_first_frame": r["first"], "vat_frame_count": r["count"], "vat_fps": p_fps,
				"one_shot": once, "duration": maxf(float(r["length"]), 0.1), "hold_lean": st == "death"})
		visual.set(st, a)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var saved := []
	var save := func(res: Resource, file: String) -> Resource:
		var p := out_dir.path_join(file)
		ResourceSaver.save(res, p, ResourceSaver.FLAG_COMPRESS)
		saved.append(p)
		return ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
	visual.mesh = save.call(mesh, "mesh.res")
	visual.vat_positions = save.call(ImageTexture.create_from_image(pimg), "vat_posizioni.res")
	visual.vat_normals = save.call(ImageTexture.create_from_image(nimg), "vat_normali.res")
	visual.vat_rows_per_frame = rows
	if albedo != null:
		var img := albedo.get_image()
		if img != null:
			visual.albedo_texture = save.call(ImageTexture.create_from_image(img), "colori.res")
			visual.pixel_texture = maxi(img.get_width(), img.get_height()) <= 256
	var vpath := out_dir.path_join("aspetto.tres")
	ResourceSaver.save(visual, vpath)
	var used := PackedStringArray()
	for st: String in UnitVisual.STATES:
		used.append("%s=%s" % [st, mapping.get(st, "") if mapping.get(st, "") != "" else "procedurale"])
	var msg := "Cotte %d animazioni (%d fotogrammi, %d vertici, texture %d×%d) → %s\n   %s" % [
			ranges.size(), frames.size(), total, w, h, vpath, ", ".join(used)]
	return {"ok": true, "message": msg, "visual_path": vpath, "frames": frames.size(), "vertices": total,
			"height": (hi.y - lo.y) * sc, "mapping": mapping,
			"ranges": ranges, "available": available}


## Posizioni e normali di tutti i vertici nella posa attuale, nello spazio della radice del modello.
## Parole che indicano un'arma o un oggetto, nel nome della mesh o dell'osso che la muove.
const PROP_WORDS := ["spear", "lance", "pike", "sword", "axe", "mace", "hammer", "staff", "bow", "arrow",
		"shield", "weapon", "banner", "flag", "prop", "item", "lancia", "spada", "scudo", "arco", "freccia", "arma"]


static func _is_prop(name: String) -> bool:
	var n := name.to_lower()
	for w: String in PROP_WORDS:
		if n.contains(w):
			return true
	return false


## 1 = vertice del corpo, 0 = di un'arma. Se tutto risulta arma, conta tutto.
static func _body_mask(surfaces: Array[Dictionary], total: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(total)
	mask.fill(1)
	var any := false
	for sd in surfaces:
		var mi: MeshInstance3D = sd["mi"]
		var first: int = sd["first"]
		var verts: PackedVector3Array = sd["verts"]
		var prop_mesh := _is_prop(mi.name) or (mi.get_parent() is BoneAttachment3D \
				and _is_prop((mi.get_parent() as BoneAttachment3D).bone_name))
		var per: int = sd["per"]
		var skin := mi.skin
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var prop_bind := {}
		if skin != null and per > 0:
			for b in skin.get_bind_count():
				var bn := skin.get_bind_name(b)
				if bn == "" and skel != null and skin.get_bind_bone(b) >= 0:
					bn = skel.get_bone_name(skin.get_bind_bone(b))
				prop_bind[b] = _is_prop(bn)
		var bones: PackedInt32Array = sd["bones"]
		var weights: PackedFloat32Array = sd["weights"]
		for i in verts.size():
			var prop := prop_mesh
			if not prop and not prop_bind.is_empty():
				var best := 0
				for k in per:
					if weights[i * per + k] > weights[i * per + best]:
						best = k
				prop = prop_bind.get(bones[i * per + best], false)
			if prop:
				mask[first + i] = 0
			else:
				any = true
	if not any:
		mask.fill(1)
	return mask


static func _pose(root: Node, surfaces: Array[Dictionary], total: int) -> Array:
	var ps := PackedVector3Array()
	var ns := PackedVector3Array()
	ps.resize(total)
	ns.resize(total)
	var root_inv := (root as Node3D).global_transform.affine_inverse() if root is Node3D else Transform3D()
	var cache := {}
	for sd in surfaces:
		var mi: MeshInstance3D = sd["mi"]
		var verts: PackedVector3Array = sd["verts"]
		var nrm: PackedVector3Array = sd["nrm"]
		var first: int = sd["first"]
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin := mi.skin
		var per: int = sd["per"]
		if skel != null and skin != null and per > 0:
			# matrici di skinning: posa dell'osso × posa di legame, nello spazio della radice
			if not cache.has(mi):
				skel.force_update_all_bone_transforms()
				var sk_xf := root_inv * skel.global_transform
				var mats: Array[Transform3D] = []
				for b in skin.get_bind_count():
					var bone := skin.get_bind_bone(b)
					if bone < 0:
						bone = skel.find_bone(skin.get_bind_name(b))
					var pose := skel.get_bone_global_pose(bone) if bone >= 0 else Transform3D()
					mats.append(sk_xf * pose * skin.get_bind_pose(b))
				cache[mi] = mats
			var m: Array[Transform3D] = cache[mi]
			var bones: PackedInt32Array = sd["bones"]
			var weights: PackedFloat32Array = sd["weights"]
			for i in verts.size():
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				for k in per:
					var wgt := weights[i * per + k]
					if wgt <= 0.0:
						continue
					var xf: Transform3D = m[bones[i * per + k]]
					p += (xf * verts[i]) * wgt
					if not nrm.is_empty():
						n += (xf.basis * nrm[i]) * wgt
				ps[first + i] = p
				ns[first + i] = n.normalized() if n != Vector3.ZERO else Vector3.UP
		else:
			var xf := root_inv * mi.global_transform
			for i in verts.size():
				ps[first + i] = xf * verts[i]
				ns[first + i] = (xf.basis * nrm[i]).normalized() if not nrm.is_empty() else Vector3.UP
	# modelli senza normali: si calcolano dai triangoli della posa
	for sd in surfaces:
		if not (sd["nrm"] as PackedVector3Array).is_empty():
			continue
		var first: int = sd["first"]
		var n: int = (sd["verts"] as PackedVector3Array).size()
		var idx: PackedInt32Array = sd["idx"]
		if idx.is_empty():
			idx = PackedInt32Array(range(n))
		var acc := PackedVector3Array()
		acc.resize(n)
		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			# Godot: triangoli in senso orario visti da fuori
			var fn := (ps[first + c] - ps[first + a]).cross(ps[first + b] - ps[first + a])
			acc[a] += fn
			acc[b] += fn
			acc[c] += fn
		for i in n:
			ns[first + i] = acc[i].normalized() if acc[i] != Vector3.ZERO else Vector3.UP
	return [ps, ns]


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)
