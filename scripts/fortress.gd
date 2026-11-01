class_name Fortress
extends Node3D
## Fortezza per le battaglie d'assedio, costruita da una pianta (FortressLayout): mura
## invalicabili con camminamento, porte da abbattere, postierle per i soli difensori, torri che
## tirano frecce, punto di vittoria. Gli attaccanti arrivano da sud (z positivo).
##
## Le porte chiuse sono muro per gli attaccanti; i difensori ci passano (le aprono per sé).
## Il movimento dei reggimenti passa da route(): un grafo di visibilità tra gli angoli di mura e
## torri e i due lati di ogni porta, risolto con Dijkstra. La visibilità tra i nodi fissi è
## calcolata una volta e rifatta solo quando cade una porta.

const WALL_T := FortressLayout.WALL_T
const WALL_H := 7.0
const CAPTURE_TIME := 45.0       ## secondi di presidio indisturbato per conquistare
const CAPTURE_DECAY := 30.0      ## i difensori riportano il punto a zero in 30 s
const SIEGE_TIME := 20.0 * 60.0  ## allo scadere vincono i difensori
const TOWER_RANGE := 110.0
const TOWER_RELOAD := 2.5
const TOWER_H := 11.0

const WALK_Y := WALL_H        ## quota dei piedi sul camminamento
const WALL_COVER := 0.4       ## probabilità che i merli fermino una freccia tirata dal basso
const WALL_RANGE_BONUS := 1.2 ## dall'alto si tira più lontano
const STONE := Color(0.36, 0.34, 0.31)
const WOOD := Color(0.42, 0.27, 0.14)


class Gate:
	var name := ""
	var center := Vector3.ZERO
	var normal := Vector3.ZERO      ## verso l'esterno
	var width := 10.0
	var max_hp := 4000.0
	var hp := 4000.0
	var breakable := true
	var destroyed := false
	var rect := Rect2()
	var mesh: MeshInstance3D
	var mat: StandardMaterial3D
	var label: Label3D
	var rubble: MeshInstance3D
	var hovered := false

	func outside_point(d: float) -> Vector3:
		return center + normal * d

	func inside_point(d: float) -> Vector3:
		return center - normal * d

	func is_closed() -> bool:
		return not destroyed


var battle: BattleManager
var layout: FortressLayout
var defender_team := 1
var attacker_team := 0
var gates: Array[Gate] = []
var walls: Array[Rect2] = []      ## muri e torri: sempre solidi
var sides: Array[Dictionary] = [] ## lati percorribili: {"a", "b", "n", "len", "dir"}
var towers: Array[Dictionary] = []
var capture_center := Vector3(0.0, 0.0, -78.0)
var capture_radius := 14.0
var capture_progress := 0.0       ## 0 = difensori, 1 = conquistato dagli attaccanti
var capture_counts := Vector2i.ZERO  ## (attaccanti, difensori) nell'area
var last_route_gate: Gate = null
var last_route_ok := true         ## false se l'ultimo route() non ha trovato strada

var _solids_cache := {}
var _graph_cache := {}            ## squadra -> {"nodes", "gate_of", "vis"}
var _capture_acc := 0.0
var _im: ImmediateMesh
var _cap_label: Label3D


func setup(b: BattleManager, p_defender_team: int, p_layout: FortressLayout = null) -> void:
	battle = b
	defender_team = p_defender_team
	attacker_team = 1 - defender_team
	layout = p_layout if p_layout != null else FortressLayout.from_data(FortressLayout.classic_data())
	sides = layout.sides
	capture_center = layout.capture
	_fm = FortressMeshes.new(int(absf(capture_center.x * 13.0 + capture_center.z * 7.0)) + 1)
	for g: Dictionary in layout.gates:
		_add_gate(g)
	for r in layout.wall_rects:
		_add_wall(r)
	for t: Dictionary in layout.towers:
		_add_tower(t["pos"], float(t["size"]))
	_build_adjacency()
	_build_parapets()
	# mura, torri e cornici delle porte: una sola mesh
	var mi := MeshInstance3D.new()
	mi.mesh = _fm.commit()
	mi.material_override = _stone_material()
	add_child(mi)
	_fm = null
	_build_capture_visuals()


# ---------------------------------------------------------------- costruzione

func _add_gate(d: Dictionary) -> void:
	var g := Gate.new()
	g.name = d["name"]
	g.center = d["center"]
	g.normal = d["normal"]
	g.width = d["width"]
	g.max_hp = d["hp"]
	g.hp = g.max_hp
	g.breakable = d["breakable"]
	g.rect = d["rect"]
	var c := g.center
	var nrm := g.normal
	var breakable := g.breakable
	var along_x := absf(nrm.z) >= absf(nrm.x)
	var along := Vector3.RIGHT if along_x else Vector3.BACK
	var gw := g.rect.size.x if along_x else g.rect.size.y
	var gt := g.rect.size.y if along_x else g.rect.size.x
	_fm.gate_frame(Vector3(c.x, 0, c.z), along, nrm, gw, gt, WALL_H, breakable)
	var doors := FortressMeshes.new(gates.size() + 3)
	doors.gate_doors(Vector3(c.x, 0, c.z), along, nrm, gw, breakable)
	g.mat = FortressMeshes.material()
	g.mesh = MeshInstance3D.new()
	g.mesh.mesh = doors.commit()
	g.mesh.material_override = g.mat
	add_child(g.mesh)
	if breakable:
		# barra piccola appoggiata sul battente, dal lato esterno: ha una dimensione reale
		# (si rimpicciolisce con la distanza), le mura la coprono e oltre 90 m sparisce
		g.label = Label3D.new()
		g.label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		g.label.pixel_size = 0.006
		g.label.font_size = 48
		g.label.outline_size = 10
		g.label.visibility_range_end = 90.0
		g.label.visibility_range_end_margin = 10.0
		g.label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		g.label.position = Vector3(c.x, 1.6, c.z) + nrm * (WALL_T * 0.5 + 0.3)
		add_child(g.label)
	gates.append(g)
	_update_gate_visual(g)


func _add_wall(r: Rect2) -> void:
	if r.size.x <= 0.01 or r.size.y <= 0.01:
		return
	walls.append(r)
	# verso l'esterno: il lato più lontano dal punto di vittoria (merli da quella parte)
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var w := Vector3.BACK if r.size.x >= r.size.y else Vector3.RIGHT
	var d := Regiment._flat(c - capture_center)
	var out := w if d.dot(w) >= 0.0 else -w
	_fm.wall(r, WALL_H, out)


func _add_tower(c: Vector3, size: float) -> void:
	var r := Rect2(c.x - size * 0.5, c.z - size * 0.5, size, size)
	walls.append(r)
	_fm.tower(r, TOWER_H)
	towers.append({"pos": c + Vector3(0, TOWER_H + 0.5, 0), "timer": randf() * TOWER_RELOAD})


var _fm: FortressMeshes
var _adj: Array = []   ## per lato: [vicini all'estremità a, vicini all'estremità b], ognuno {"side", "end"}
const JOIN := 1.5      ## estremità più vicine di così sono lo stesso angolo


func _build_adjacency() -> void:
	_adj.clear()
	for i in sides.size():
		var ends := [[], []]
		for e in 2:
			var p: Vector3 = sides[i]["a"] if e == 0 else sides[i]["b"]
			for j in sides.size():
				if j == i:
					continue
				for je in 2:
					var q: Vector3 = sides[j]["a"] if je == 0 else sides[j]["b"]
					if p.distance_to(q) < JOIN:
						(ends[e] as Array).append({"side": j, "end": je})
		_adj.append(ends)


## Direzione in cui il lato j si allontana dalla sua estremità je.
func _away(j: int, je: int) -> Vector3:
	return sides[j]["dir"] if je == 0 else -(sides[j]["dir"] as Vector3)


func _build_parapets() -> void:
	var t := WALL_T
	var pt := FortressMeshes.PARAPET_T
	var inner_ring := {}
	for i in sides.size():
		# lato di una cinta interna: oltre c'è ancora l'interno della fortezza → merli da tutte e due le parti
		var mid: Vector3 = (sides[i]["a"] + sides[i]["b"]) * 0.5
		var outside: Vector3 = mid + (sides[i]["n"] as Vector3) * (t * 0.5 + 3.0)
		inner_ring[i] = layout.is_inside(outside)
	for i in sides.size():
		var n: Vector3 = sides[i]["n"]
		var ext := [[t * 0.5, t * 0.5], [t * 0.5, t * 0.5]]   # [fuori, dentro] per estremità a, b
		for e in 2:
			var list: Array = _adj[i][e]
			if list.is_empty():
				# estremità che finisce contro il fianco di un altro muro (a T): ci si ferma al suo parapetto
				var pe: Vector3 = sides[i]["a"] if e == 0 else sides[i]["b"]
				for j in sides.size():
					if j != i and _dist_to_side(j, pe) < JOIN:
						ext[e] = [-(t * 0.5 - pt), -(t * 0.5 - pt)]
						break
				continue
			var nb: Dictionary = list[0]
			var turn := _away(nb["side"], nb["end"]).dot(n)
			for k in 2:
				var o := 1.0 if k == 0 else -1.0
				if o * turn < 0.0:
					# lato esterno dell'angolo: arriva fino allo spigolo (solo uno dei due, per non sovrapporsi)
					ext[e][k] = t * 0.5 if i < int(nb["side"]) else t * 0.5 - pt
				else:
					# lato interno dell'angolo: si ferma contro il parapetto dell'altro muro
					ext[e][k] = -(t * 0.5 - pt)
		_fm.side_parapets(sides[i]["a"], sides[i]["b"], n, t, WALL_H, ext[0][0], ext[1][0], ext[0][1], ext[1][1], inner_ring[i])


func _dist_to_side(j: int, p: Vector3) -> float:
	var t := clampf(_side_t(j, p), 0.0, side_length(j))
	return Regiment._flat(_side_point(j, t) - p).length()


## I due lati sono collegati lungo il camminamento (stessa cinta)?
func walkway_connected(a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or b < 0 or a >= _adj.size() or b >= _adj.size():
		return false
	var seen := {a: true}
	var stack := [a]
	while not stack.is_empty():
		var s: int = stack.pop_back()
		for e in 2:
			for nb: Dictionary in _adj[s][e]:
				var j: int = nb["side"]
				if j == b:
					return true
				if not seen.has(j):
					seen[j] = true
					stack.append(j)
	return false


## Posti per n soldati sul camminamento, su due file, attorno al punto p del lato `side`:
## si riempie prima il tratto più vicino e, se il lato non basta, si gira l'angolo sui lati vicini.
## Le torri si saltano. Restituisce {"pos": PackedVector3Array, "face": PackedVector3Array}.
func wall_slots(side: int, p: Vector3, n: int, spacing: float) -> Dictionary:
	var cand: Array = []   # [distanza lungo le mura, posizione, normale]
	var need := n * 0.5 * spacing + 4.0
	var t_p := clampf(_side_t(side, p), 0.0, side_length(side))
	var seen := {}
	var queue: Array = [[side, -1, 0.0]]   # lato, estremità da cui si entra (-1 = lato di partenza), distanza
	var front := 0.55
	var back := -0.75
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var si: int = item[0]
		if seen.has(si):
			continue
		seen[si] = true
		var entry: int = item[1]
		var base: float = item[2]
		var length := side_length(si)
		var nrm: Vector3 = sides[si]["n"]
		var lo := (WALL_T * 0.5 + 0.6) if not (_adj[si][0] as Array).is_empty() else 1.0
		var hi := length - ((WALL_T * 0.5 + 0.6) if not (_adj[si][1] as Array).is_empty() else 1.0)
		var t := lo
		while t <= hi + 0.01:
			var d := absf(t - t_p) if entry < 0 else base + (t if entry == 0 else length - t)
			for rank in 2:
				var q := _side_point(si, t) + nrm * (front if rank == 0 else back)
				if not _in_tower(q):
					cand.append([d + rank * 0.01, q, nrm])
			t += spacing
		# si prosegue sui lati collegati finché serve spazio
		for e in 2:
			if e == entry:
				continue
			var d_end := (absf((0.0 if e == 0 else length) - t_p)) if entry < 0 else base + length
			if d_end > need:
				continue
			for nb: Dictionary in _adj[si][e]:
				queue.append([nb["side"], nb["end"], d_end])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var pos := PackedVector3Array()
	var face := PackedVector3Array()
	for k in mini(n, cand.size()):
		pos.append(cand[k][1])
		face.append(cand[k][2])
	# se le mura non bastano (cinta piccolissima), gli ultimi si stringono sugli ultimi posti
	while pos.size() < n and not cand.is_empty():
		var k := pos.size() % cand.size()
		pos.append((cand[k][1] as Vector3) + Vector3(0.3, 0, 0.3))
		face.append(cand[k][2])
	return {"pos": pos, "face": face}


func _in_tower(q: Vector3) -> bool:
	for t: Dictionary in layout.towers:
		var r: Rect2 = t["rect"]
		if r.grow(0.4).has_point(Vector2(q.x, q.z)):
			return true
	return false
var _stone_mat_shared: StandardMaterial3D
func _stone_material() -> StandardMaterial3D:
	if _stone_mat_shared == null:
		_stone_mat_shared = FortressMeshes.material()
	return _stone_mat_shared


var _stone_cache := {}
func _stone_mat(shade := 1.0) -> StandardMaterial3D:
	if not _stone_cache.has(shade):
		var m := StandardMaterial3D.new()
		m.albedo_color = STONE * shade
		m.roughness = 1.0
		_stone_cache[shade] = m
	return _stone_cache[shade]


func _build_capture_visuals() -> void:
	_im = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	_cap_label = Label3D.new()
	_cap_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cap_label.no_depth_test = true
	_cap_label.fixed_size = true
	_cap_label.pixel_size = 0.0011
	_cap_label.font_size = 22
	_cap_label.outline_size = 10
	_cap_label.modulate = Color(1.0, 0.92, 0.6)
	_cap_label.position = capture_center + Vector3(0, 1.5, capture_radius + 2.0)
	add_child(_cap_label)
	var pole := BoxMesh.new()
	pole.size = Vector3(0.25, 9.0, 0.25)
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = _stone_mat(0.6)
	pm.position = capture_center + Vector3(0, 4.5, 0)
	add_child(pm)


# ---------------------------------------------------------------- geometria

# ---------------------------------------------------------------- camminamenti

func side_length(side: int) -> float:
	return sides[side]["len"]


func wall_normal(side: int) -> Vector3:
	return sides[side]["n"]


func _side_t(side: int, p: Vector3) -> float:
	var a: Vector3 = sides[side]["a"]
	return (Regiment._flat(p) - a).dot(sides[side]["dir"])


func _side_point(side: int, t: float) -> Vector3:
	return sides[side]["a"] + sides[side]["dir"] * t


## Il lato di mura sotto un punto preso alla quota del camminamento (-1 se nessuno).
func wall_side_at(p: Vector3) -> int:
	for side in sides.size():
		var t := _side_t(side, p)
		if t < 0.0 or t > side_length(side):
			continue
		var q := _side_point(side, t)
		if Regiment._flat(p - q).length() <= WALL_T * 0.5 + 0.8:
			return side
	return -1


## Centro del fronte di un reggimento largo `width` sul lato `side`, il più vicino a `p`.
func wall_center_for(side: int, p: Vector3, width: float) -> Vector3:
	var length := side_length(side)
	var half := width * 0.5 + 1.0
	var t := length * 0.5 if half * 2.0 >= length else clampf(_side_t(side, p), half, length - half)
	return _side_point(side, t) + wall_normal(side) * 0.6


## Punto a terra, dentro le mura, da cui si sale sul lato `side` vicino a `p`.
func wall_foot(side: int, p: Vector3) -> Vector3:
	var m := minf(8.0, side_length(side) * 0.5)
	var t := clampf(_side_t(side, p), m, side_length(side) - m)
	return _side_point(side, t) - wall_normal(side) * (WALL_T * 0.5 + 3.5)


## Colonne per stare sul camminamento: due file, ma mai più largo del lato.
func wall_cols_for(r: Regiment, side: int) -> int:
	var max_cols := int((side_length(side) - 6.0) / r.stats.spacing) + 1
	# il camminamento è largo 3 m: i pezzi d'artiglieria stanno in fila, uno accanto all'altro
	var want := r.alive_count if r.stats.is_artillery else ceili(r.alive_count / 2.0)
	return clampi(want, 1, max_cols)


static func can_man_walls(r: Regiment) -> bool:
	return r.stats.role == "ranged" or r.stats.role == "infantry" or r.stats.wall_mount


func inside(p: Vector3) -> bool:
	return layout.is_inside(p)


func interior_rect(margin := 3.0) -> Rect2:
	return layout.interior_bounds().grow(-margin)


## Rettangoli solidi per una squadra: mura e torri, più le porte chiuse se è l'attaccante.
func solids_for(team: int) -> Array[Rect2]:
	if _solids_cache.has(team):
		return _solids_cache[team]
	var out: Array[Rect2] = []
	out.append_array(walls)
	if team != defender_team:
		for g in gates:
			if g.is_closed():
				out.append(g.rect)
	_solids_cache[team] = out
	return out


## I rettangoli solidi abbastanza vicini a un reggimento da poterlo toccare.
func solids_near(p: Vector3, radius: float, team: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in solids_for(team):
		if r.grow(radius).has_point(Vector2(p.x, p.z)):
			out.append(r)
	return out


static func push_out_of(p: Vector3, radius: float, rects: Array[Rect2]) -> Vector3:
	for r in rects:
		var g := r.grow(radius)
		if p.x > g.position.x and p.x < g.end.x and p.z > g.position.y and p.z < g.end.y:
			var left := p.x - g.position.x
			var right := g.end.x - p.x
			var top := p.z - g.position.y
			var bottom := g.end.y - p.z
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left:
				p.x = g.position.x
			elif m == right:
				p.x = g.end.x
			elif m == top:
				p.z = g.position.y
			else:
				p.z = g.end.y
	return p


func push_out(p: Vector3, radius: float, team: int) -> Vector3:
	return push_out_of(p, radius, solids_for(team))


static func _seg_rect(a: Vector3, b: Vector3, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := Vector2(b.x - a.x, b.z - a.z)
	var p := Vector2(a.x, a.z)
	for axis in 2:
		var pa := p[axis]
		var da := d[axis]
		var lo := r.position[axis]
		var hi := r.end[axis]
		if absf(da) < 1e-6:
			if pa < lo or pa > hi:
				return false
		else:
			var ta := (lo - pa) / da
			var tb := (hi - pa) / da
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true


func _blocked(a: Vector3, b: Vector3, solids: Array[Rect2]) -> bool:
	for r in solids:
		var g := r.grow(1.0)
		# se un estremo è a ridosso del muro, controlla il muro "vero" e non quello allargato
		if g.has_point(Vector2(a.x, a.z)) or g.has_point(Vector2(b.x, b.z)):
			g = r
		if _seg_rect(a, b, g):
			return true
	return false


## Grafo dei nodi fissi per una squadra: angoli (allargati) di mura e torri, i due lati di ogni
## porta percorribile, e la visibilità reciproca già calcolata.
func _graph(team: int) -> Dictionary:
	if _graph_cache.has(team):
		return _graph_cache[team]
	var solids := solids_for(team)
	var nodes: Array[Vector3] = []
	var gate_of := {}
	for r in solids:
		var big := r.grow(5.0)
		for c in [big.position, Vector2(big.end.x, big.position.y), Vector2(big.position.x, big.end.y), big.end]:
			var p := Vector3(c.x, 0, c.y)
			if absf(p.x) > FortressLayout.MAP_HALF - 2.0 or absf(p.z) > FortressLayout.MAP_HALF - 2.0:
				continue
			var free := true
			for o in solids:
				if o.grow(1.5).has_point(c):
					free = false
					break
			if free:
				nodes.append(p)
	for g in gates:
		if team == defender_team or g.destroyed:
			gate_of[nodes.size()] = g
			nodes.append(g.outside_point(6.0))
			gate_of[nodes.size()] = g
			nodes.append(g.inside_point(6.0))
	var n := nodes.size()
	var vis := PackedByteArray()
	vis.resize(n * n)
	for i in n:
		for j in range(i + 1, n):
			var ok := 0 if _blocked(nodes[i], nodes[j], solids) else 1
			vis[i * n + j] = ok
			vis[j * n + i] = ok
	var gr := {"nodes": nodes, "gate_of": gate_of, "vis": vis}
	_graph_cache[team] = gr
	return gr


## Percorso dal punto `from` al punto `to` per una squadra: lista di tappe (l'ultima è `to`).
## Se l'arrivo è irraggiungibile (porte chiuse) porta davanti alla porta più vicina.
func route(from: Vector3, to: Vector3, team: int) -> PackedVector3Array:
	last_route_gate = null
	last_route_ok = true
	var solids := solids_for(team)
	to = push_out_of(Vector3(to.x, 0, to.z), 1.5, solids)
	if not _blocked(from, to, solids):
		return PackedVector3Array([to])
	var gr := _graph(team)
	var fixed: Array[Vector3] = gr["nodes"]
	var gate_of: Dictionary = gr["gate_of"]
	var vis: PackedByteArray = gr["vis"]
	var m := fixed.size()
	# indici: 0..m-1 nodi fissi, m = partenza, m+1 = arrivo
	var n := m + 2
	var from_vis := PackedByteArray()
	var to_vis := PackedByteArray()
	from_vis.resize(m)
	to_vis.resize(m)
	for i in m:
		from_vis[i] = 0 if _blocked(from, fixed[i], solids) else 1
		to_vis[i] = 0 if _blocked(fixed[i], to, solids) else 1
	var pos := func(i: int) -> Vector3:
		return fixed[i] if i < m else (from if i == m else to)
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(1e20)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[m] = 0.0
	for _iter in n:
		var u := -1
		var best := 1e20
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0 or u == m + 1:
			break
		done[u] = 1
		var pu: Vector3 = pos.call(u)
		for v in n:
			if done[v] == 1 or v == u:
				continue
			var visible := false
			if u == m:
				visible = v < m and from_vis[v] == 1
			elif v == m + 1:
				visible = u < m and to_vis[u] == 1
			elif v < m and u < m:
				visible = vis[u * m + v] == 1
			if not visible:
				continue
			var w := pu.distance_to(pos.call(v))
			if dist[u] + w < dist[v]:
				dist[v] = dist[u] + w
				prev[v] = u
	if prev[m + 1] < 0:
		last_route_ok = false
		# irraggiungibile: vai alla porta chiusa più vicina
		var g := nearest_closed_gate(from)
		if g != null:
			last_route_gate = g
			return PackedVector3Array([g.outside_point(4.0)])
		return PackedVector3Array([to])
	var path: Array[Vector3] = []
	var k := m + 1
	while k != m:
		path.push_front(pos.call(k))
		var pk := prev[k]
		if gate_of.has(k) and gate_of.has(pk) and gate_of[k] == gate_of[pk]:
			last_route_gate = gate_of[k]
		k = pk
	return PackedVector3Array(path)


## Si può andare da `from` a `to` senza abbattere nulla?
func can_reach(from: Vector3, to: Vector3, team: int) -> bool:
	route(from, to, team)
	return last_route_ok


func nearest_closed_gate(p: Vector3) -> Gate:
	var best: Gate = null
	var bd := 1e20
	for g in gates:
		if g.breakable and g.is_closed():
			var d := p.distance_to(g.center)
			if d < bd:
				bd = d
				best = g
	return best


func gate_at(p: Vector3, margin: float) -> Gate:
	for g in gates:
		if g.breakable and g.is_closed() and g.rect.grow(margin).has_point(Vector2(p.x, p.z)):
			return g
	return null


func dist_to_gate(g: Gate, p: Vector3) -> float:
	var q := Vector2(clampf(p.x, g.rect.position.x, g.rect.end.x), clampf(p.z, g.rect.position.y, g.rect.end.y))
	return q.distance_to(Vector2(p.x, p.z))


func open_gates() -> Array[Gate]:
	var out: Array[Gate] = []
	for g in gates:
		if g.breakable and g.destroyed:
			out.append(g)
	return out


func closed_breakable_gates() -> Array[Gate]:
	var out: Array[Gate] = []
	for g in gates:
		if g.breakable and g.is_closed():
			out.append(g)
	return out


# ---------------------------------------------------------------- porte

func damage_gate(g: Gate, dmg: float) -> void:
	if g.destroyed or not g.breakable:
		return
	g.hp -= dmg
	if g.hp <= 0.0:
		g.hp = 0.0
		g.destroyed = true
		_solids_cache.clear()
		_graph_cache.clear()
		for r in battle.regiments:
			r.on_gate_destroyed(g)
	_update_gate_visual(g)


func set_gate_hover(g: Gate, on: bool) -> void:
	if g == null:
		return
	g.hovered = on
	_update_gate_visual(g)


func _update_gate_visual(g: Gate) -> void:
	if g.destroyed:
		g.mesh.visible = false
		if g.rubble == null:
			var along_x := absf(g.normal.z) >= absf(g.normal.x)
			var rb := FortressMeshes.new(gates.find(g) + 11)
			rb.rubble(Vector3(g.center.x, 0, g.center.z), Vector3.RIGHT if along_x else Vector3.BACK, g.normal,
					g.rect.size.x if along_x else g.rect.size.y, g.rect.size.y if along_x else g.rect.size.x)
			g.rubble = MeshInstance3D.new()
			g.rubble.mesh = rb.commit()
			g.rubble.material_override = _stone_material()
			add_child(g.rubble)
	if g.label != null:
		if g.destroyed:
			g.label.text = "ABBATTUTA"
			g.label.modulate = Color(1.0, 0.55, 0.4)
		else:
			var pct := int(round(100.0 * g.hp / g.max_hp))
			var bars := int(round(pct / 10.0))
			g.label.text = "%s %d%%" % ["■".repeat(bars) + "□".repeat(10 - bars), pct]
			g.label.modulate = Color(1.0, 0.95, 0.85)
	g.mat.emission_enabled = g.hovered and not g.destroyed
	g.mat.emission = Color(1.0, 0.15, 0.05)
	g.mat.emission_energy_multiplier = 0.9


# ---------------------------------------------------------------- simulazione

func update(dt: float) -> void:
	_update_towers(dt)
	_capture_acc += dt
	if _capture_acc >= 0.5:
		_update_capture(_capture_acc)
		_capture_acc = 0.0


func _update_towers(dt: float) -> void:
	for t in towers:
		t["timer"] = float(t["timer"]) - dt
		if float(t["timer"]) > 0.0:
			continue
		t["timer"] = TOWER_RELOAD * randf_range(0.85, 1.15)
		var origin: Vector3 = t["pos"]
		var best: Regiment = null
		var bd := TOWER_RANGE
		for r in battle.regiments:
			if r.team != attacker_team or not r.is_on_field():
				continue
			var d := Regiment._flat(r.mid() - origin).length()
			if d < bd:
				bd = d
				best = r
		if best != null:
			battle.projectiles.fire_from(origin, best, 10.0, 4.0, -1, defender_team)


func _update_capture(dt: float) -> void:
	var att := 0
	var def := 0
	var r2 := capture_radius * capture_radius
	for r in battle.regiments:
		if not r.is_on_field() or r.state == Regiment.State.ROUTING:
			continue
		if r.mid().distance_to(capture_center) > capture_radius + r.bound_radius() + 5.0:
			continue
		var n := 0
		var rp := r.pos
		var al := r.alive
		for i in r.count:
			if al[i] == 1 and Regiment._flat(rp[i] - capture_center).length_squared() < r2:
				n += 1
		if r.team == attacker_team:
			att += n
		else:
			def += n
	capture_counts = Vector2i(att, def)
	if att > 0 and def == 0:
		capture_progress = minf(1.0, capture_progress + dt / CAPTURE_TIME)
	elif def > 0 and att == 0:
		capture_progress = maxf(0.0, capture_progress - dt / CAPTURE_DECAY)
	if capture_progress >= 1.0 and battle.phase == BattleManager.Phase.BATTLE:
		battle.end_battle(attacker_team, "Punto di vittoria conquistato")


func capture_state_text() -> String:
	if capture_counts.x > 0 and capture_counts.y > 0:
		return "conteso"
	if capture_counts.x > 0:
		return "in conquista"
	if capture_progress > 0.0 and capture_counts.y > 0:
		return "riconquista"
	return "sicuro" if capture_progress == 0.0 else "in pausa"


func _process(_delta: float) -> void:
	_draw_capture()


func _draw_capture() -> void:
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := capture_center + Vector3(0, 0.1, 0)
	var seg := 64
	var att_col := Color(0.3, 0.5, 1.0) if attacker_team == 0 else Color(0.95, 0.3, 0.22)
	var def_col := Color(0.95, 0.3, 0.22) if attacker_team == 0 else Color(0.3, 0.5, 1.0)
	var filled := int(round(capture_progress * seg))
	for k in seg:
		var a0 := TAU * k / seg - PI * 0.5
		var a1 := TAU * (k + 1) / seg - PI * 0.5
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var fill := Color(att_col, 0.35) if k < filled else Color(def_col, 0.12)
		_im.surface_set_color(fill)
		_im.surface_add_vertex(c)
		_im.surface_set_color(fill)
		_im.surface_add_vertex(c + d0 * capture_radius)
		_im.surface_set_color(fill)
		_im.surface_add_vertex(c + d1 * capture_radius)
		var ring := Color(1.0, 0.9, 0.55, 0.85)
		for tri in [[d0 * (capture_radius - 0.4), d1 * (capture_radius - 0.4), d1 * (capture_radius + 0.4)],
				[d0 * (capture_radius - 0.4), d1 * (capture_radius + 0.4), d0 * (capture_radius + 0.4)]]:
			for v: Vector3 in tri:
				_im.surface_set_color(ring)
				_im.surface_add_vertex(c + v)
	_im.surface_end()
	_cap_label.text = "PUNTO DI VITTORIA\n%d%% · %s" % [int(capture_progress * 100.0), capture_state_text()]
