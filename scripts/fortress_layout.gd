class_name FortressLayout
extends RefCounted
## Pianta di una fortezza come dati: la usano la battaglia (Fortress) e l'editor.
##
## Formato JSON (coordinate in metri sul piano X/Z; gli attaccanti arrivano da sud, z positivo):
## {
##   "name": "Classica",
##   "walls":  [[ax, az, bx, bz], ...],          segmenti di muro orizzontali o verticali
##   "gates":  [{"wall": 0, "t": 60, "width": 10, "type": "porta", "name": "Porta principale"}],
##             t = distanza del centro della porta dall'inizio (a) del muro
##             type "porta" = abbattibile; "postierla" = solo per i difensori, indistruttibile
##   "towers": [[x, z, lato], ...],
##   "capture": [x, z]                             punto di vittoria
## }
## Le fortezze del gioco stanno in res://data/fortezze/, quelle create con l'editor in user://fortezze/.

const WALL_T := 3.0
const CELL := 2.0                   ## griglia per calcolare l'interno
const MAP_HALF := 220.0
## Area in cui si può costruire: a sud resta lo spazio per lo schieramento degli attaccanti.
const BUILD_AREA := Rect2(-130.0, -170.0, 260.0, 160.0)
const GATE_HP_PER_M := 900.0        ## resistenza della porta per metro di larghezza
const USER_DIR := "user://fortezze"
const BUILTIN_DIR := "res://data/fortezze"

var data := {}
var name := ""
var sides: Array[Dictionary] = []   ## {"a", "b", "n", "len", "dir"} per ogni muro
var gates: Array[Dictionary] = []   ## {"name","center","normal","width","hp","breakable","rect","wall","t"}
var wall_rects: Array[Rect2] = []   ## muri già tagliati dalle porte
var towers: Array[Dictionary] = []  ## {"pos": Vector3, "size": float, "rect": Rect2}
var capture := Vector3.ZERO
var has_capture := false
## griglia: 0 fuori, 1 dentro, 2 muro/torre/porta (con le porte chiuse)
var grid := PackedByteArray()
var grid_n := 0


static func from_data(d: Dictionary) -> FortressLayout:
	var l := FortressLayout.new()
	l.data = d
	l._build()
	return l


# ---------------------------------------------------------------- costruzione

func _build() -> void:
	name = str(data.get("name", "Senza nome"))
	has_capture = data.has("capture") and (data["capture"] as Array).size() == 2
	if has_capture:
		capture = Vector3(float(data["capture"][0]), 0.0, float(data["capture"][1]))
	var ref := capture if has_capture else Vector3(0, 0, -80)
	for w: Array in data.get("walls", []):
		var a := Vector3(float(w[0]), 0.0, float(w[1]))
		var b := Vector3(float(w[2]), 0.0, float(w[3]))
		var length := a.distance_to(b)
		if length < 0.5:
			continue
		var dir := (b - a) / length
		var n := Vector3(-dir.z, 0.0, dir.x)
		# la normale punta verso l'esterno: lontano dal punto di vittoria
		if n.dot((a + b) * 0.5 - ref) < 0.0:
			n = -n
		sides.append({"a": a, "b": b, "n": n, "len": length, "dir": dir})
	for gd: Dictionary in data.get("gates", []):
		var wi := int(gd.get("wall", -1))
		if wi < 0 or wi >= sides.size():
			continue
		var s: Dictionary = sides[wi]
		var width := float(gd.get("width", 10.0))
		var t := clampf(float(gd.get("t", 0.0)), width * 0.5, float(s["len"]) - width * 0.5)
		var c: Vector3 = s["a"] + s["dir"] * t
		var breakable := str(gd.get("type", "porta")) == "porta"
		gates.append({
			"name": str(gd.get("name", "Porta")), "center": c, "normal": s["n"], "width": width,
			"hp": width * GATE_HP_PER_M if breakable else 1.0, "breakable": breakable,
			"rect": _seg_rect(c - s["dir"] * width * 0.5, c + s["dir"] * width * 0.5, 0.0), "wall": wi, "t": t,
		})
	# muri: ogni segmento allungato di mezzo spessore alle estremità (gli angoli si chiudono),
	# poi tagliato in corrispondenza delle porte
	for wi in sides.size():
		var s: Dictionary = sides[wi]
		var cuts: Array[Vector2] = []
		for g in gates:
			if int(g["wall"]) == wi:
				cuts.append(Vector2(float(g["t"]) - float(g["width"]) * 0.5, float(g["t"]) + float(g["width"]) * 0.5))
		cuts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
		var start := -WALL_T * 0.5
		var a: Vector3 = s["a"]
		var dir: Vector3 = s["dir"]
		for c in cuts:
			if c.x - start > 0.05:
				wall_rects.append(_seg_rect(a + dir * start, a + dir * c.x, 0.0))
			start = c.y
		var end_t := float(s["len"]) + WALL_T * 0.5
		if end_t - start > 0.05:
			wall_rects.append(_seg_rect(a + dir * start, a + dir * end_t, 0.0))
	for tw: Array in data.get("towers", []):
		var size := float(tw[2]) if tw.size() > 2 else 8.0
		var p := Vector3(float(tw[0]), 0.0, float(tw[1]))
		towers.append({"pos": p, "size": size, "rect": Rect2(p.x - size * 0.5, p.z - size * 0.5, size, size)})
	_compute_grid()


## Rettangolo di un tratto di muro tra due punti allineati agli assi.
static func _seg_rect(a: Vector3, b: Vector3, extend: float) -> Rect2:
	var x0 := minf(a.x, b.x) - extend
	var x1 := maxf(a.x, b.x) + extend
	var z0 := minf(a.z, b.z) - extend
	var z1 := maxf(a.z, b.z) + extend
	if x1 - x0 < WALL_T:
		var cx := (x0 + x1) * 0.5
		x0 = cx - WALL_T * 0.5
		x1 = cx + WALL_T * 0.5
	if z1 - z0 < WALL_T:
		var cz := (z0 + z1) * 0.5
		z0 = cz - WALL_T * 0.5
		z1 = cz + WALL_T * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func solid_rects(include_gates: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.append_array(wall_rects)
	for t in towers:
		out.append(t["rect"])
	if include_gates:
		for g in gates:
			out.append(g["rect"])
	return out


# ---------------------------------------------------------------- interno

func _compute_grid() -> void:
	grid_n = int(MAP_HALF * 2.0 / CELL)
	grid = PackedByteArray()
	grid.resize(grid_n * grid_n)
	for r in solid_rects(true):
		var c0 := _cell(Vector3(r.position.x, 0, r.position.y))
		var c1 := _cell(Vector3(r.end.x, 0, r.end.y))
		for z in range(maxi(c0.y, 0), mini(c1.y, grid_n - 1) + 1):
			for x in range(maxi(c0.x, 0), mini(c1.x, grid_n - 1) + 1):
				grid[z * grid_n + x] = 2
	# tutto ciò che non si raggiunge dal bordo della mappa senza attraversare muri o porte è interno
	var reach := PackedByteArray()
	reach.resize(grid.size())
	var stack := PackedInt32Array()
	for k in grid_n:
		for idx in [k, (grid_n - 1) * grid_n + k, k * grid_n, k * grid_n + grid_n - 1]:
			if grid[idx] == 0 and reach[idx] == 0:
				reach[idx] = 1
				stack.append(idx)
	while not stack.is_empty():
		var idx := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := idx % grid_n
		var z := idx / grid_n
		for nb in [idx - 1 if x > 0 else -1, idx + 1 if x < grid_n - 1 else -1,
				idx - grid_n if z > 0 else -1, idx + grid_n if z < grid_n - 1 else -1]:
			if nb >= 0 and grid[nb] == 0 and reach[nb] == 0:
				reach[nb] = 1
				stack.append(nb)
	for idx in grid.size():
		if grid[idx] == 0 and reach[idx] == 0:
			grid[idx] = 1


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x + MAP_HALF) / CELL)), int(floor((p.z + MAP_HALF) / CELL)))


func cell_value(p: Vector3) -> int:
	var c := _cell(p)
	if c.x < 0 or c.y < 0 or c.x >= grid_n or c.y >= grid_n:
		return 0
	return grid[c.y * grid_n + c.x]


func is_inside(p: Vector3) -> bool:
	return cell_value(p) == 1


## Rettangolo che contiene tutto l'interno (vuoto se la fortezza non è chiusa).
func interior_bounds() -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for idx in grid.size():
		if grid[idx] == 1:
			var x := (idx % grid_n) * CELL - MAP_HALF
			var z := (idx / grid_n) * CELL - MAP_HALF
			lo = Vector2(minf(lo.x, x), minf(lo.y, z))
			hi = Vector2(maxf(hi.x, x + CELL), maxf(hi.y, z + CELL))
	if lo.x > hi.x:
		return Rect2()
	return Rect2(lo, hi - lo)


func interior_area() -> float:
	return grid.count(1) * CELL * CELL


## Punto dell'interno libero più vicino a `p` (per piazzare le truppe).
func nearest_inside(p: Vector3, margin := 2.0) -> Vector3:
	if is_inside(p) and _clear(p, margin):
		return p
	for ring in range(1, 40):
		var best := Vector3.ZERO
		var bd := 1e9
		var step := ring * CELL
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector3(cos(a), 0, sin(a)) * step
			if is_inside(q) and _clear(q, margin):
				var d := q.distance_to(p)
				if d < bd:
					bd = d
					best = q
		if bd < 1e9:
			return best
	return p


func _clear(p: Vector3, margin: float) -> bool:
	for dx in [-margin, margin]:
		for dz in [-margin, margin]:
			if cell_value(p + Vector3(dx, 0, dz)) != 1:
				return false
	return true


# ---------------------------------------------------------------- controllo

## Problemi che impediscono di giocare questa fortezza (lista vuota = va bene).
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if sides.is_empty():
		out.append("Non ci sono mura.")
	if not has_capture:
		out.append("Manca il punto di vittoria.")
	elif cell_value(capture) != 1:
		out.append("Il punto di vittoria non è chiuso dalle mura: gli attaccanti potrebbero entrare senza abbattere nulla.")
	var breakable := 0
	for g in gates:
		if g["breakable"]:
			breakable += 1
	if breakable == 0:
		out.append("Serve almeno una porta abbattibile, altrimenti gli attaccanti non possono entrare.")
	if has_capture and cell_value(capture) == 1 and interior_area() < 900.0:
		out.append("L'interno è troppo piccolo (meno di 30 × 30 m).")
	for t in towers:
		if not BUILD_AREA.has_point(Vector2(t["pos"].x, t["pos"].z)):
			out.append("Una torre è fuori dall'area costruibile.")
			break
	return out


# ---------------------------------------------------------------- file

static func classic_data() -> Dictionary:
	return {
		"name": "Classica",
		"walls": [[-60, -30, 60, -30], [-60, -110, 60, -110], [-60, -110, -60, -30], [60, -110, 60, -30]],
		"gates": [
			{"wall": 0, "t": 60, "width": 10, "type": "porta", "name": "Porta principale"},
			{"wall": 3, "t": 40, "width": 8, "type": "porta", "name": "Porta est"},
			{"wall": 1, "t": 60, "width": 6, "type": "postierla", "name": "Postierla"},
		],
		"towers": [[-60, -110, 8], [60, -110, 8], [-60, -30, 8], [60, -30, 8], [-10, -30, 7], [10, -30, 7]],
		"capture": [0, -78],
	}


## Tutte le fortezze disponibili: {"name", "path", "builtin"}; la classica per prima.
static func list_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir_path in [BUILTIN_DIR, USER_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var files := dir.get_files()
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var path: String = dir_path + "/" + f
			var d := load_file(path)
			if d.is_empty():
				continue
			out.append({"name": str(d.get("name", f.get_basename())), "path": path, "builtin": dir_path == BUILTIN_DIR})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["builtin"] != y["builtin"]:
			return x["builtin"]
		return str(x["name"]).naturalcasecmp_to(str(y["name"])) < 0)
	return out


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


## Salva nella cartella dell'utente; restituisce il percorso (vuoto se fallisce).
static func save_user(d: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var slug := str(d.get("name", "fortezza")).to_lower().strip_edges()
	var clean := ""
	for ch in slug:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	if clean.replace("_", "") == "":
		clean = "fortezza"
	var path := "%s/%s.json" % [USER_DIR, clean]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return path


static func delete_user(path: String) -> void:
	if path.begins_with(USER_DIR):
		DirAccess.remove_absolute(path)
