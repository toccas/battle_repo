class_name FortressMeshes
extends RefCounted
## Mesh della fortezza generate da codice: pietre squadrate con la malta, zoccolo a scarpa,
## merli, feritoie, cornici; porte di tavole con fasce di ferro sotto un arco a sesto acuto.
## Tutto in colori per vertice (un solo materiale), in coordinate del mondo: le mura e le torri
## di una fortezza finiscono in una sola mesh. Le dimensioni (rettangoli, altezze) restano quelle
## della simulazione: cambia solo l'aspetto.

const STONE := Color8(98, 86, 70)
const STONE_DARK := Color8(76, 66, 54)
const STONE_LIGHT := Color8(124, 110, 90)
const MORTAR := Color8(52, 46, 40)
const WALKWAY := Color8(88, 76, 62)
const WOOD := Color8(122, 80, 44)
const WOOD_DARK := Color8(88, 56, 30)
const IRON := Color8(58, 58, 62)
const SLIT := Color8(18, 16, 14)
const HERALD := Color8(150, 36, 34)
const GOLD := Color8(214, 176, 76)

const BLOCK := Vector2(1.7, 0.85)   ## pietre: lunghezza e altezza (m)
const MERLON_W := 1.2
const MERLON_GAP := 0.9
const MERLON_H := 1.0
const PARAPET_T := 0.45

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 7) -> void:
	_rng.seed = seed_value


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	return m


func commit() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	var m := ArrayMesh.new()
	if _v.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func is_empty() -> bool:
	return _v.is_empty()


# ---------------------------------------------------------------- primitive

## Triangolo rivolto verso n (Godot vuole le facce anteriori in senso orario).
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	_v.append_array([a, b, c])
	var nn := n.normalized()
	_n.append_array([nn, nn, nn])
	_c.append_array([col, col, col])


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	tri(a, b, c, n, col)
	tri(a, c, d, n, col)


## Parallelepipedo orientato: centro, assi (u lungo, w in profondità), mezze misure, altezza da y0 a y1.
func block(center: Vector3, u: Vector3, w: Vector3, hu: float, hw: float, y0: float, y1: float, col: Color,
		skip_bottom := true) -> void:
	var up := Vector3.UP
	var p := func(su: float, sw: float, y: float) -> Vector3:
		return Vector3(center.x, y, center.z) + u * (su * hu) + w * (sw * hw)
	quad(p.call(-1, -1, y1), p.call(1, -1, y1), p.call(1, 1, y1), p.call(-1, 1, y1), up, col)
	if not skip_bottom:
		quad(p.call(-1, -1, y0), p.call(1, -1, y0), p.call(1, 1, y0), p.call(-1, 1, y0), -up, col)
	quad(p.call(-1, 1, y0), p.call(1, 1, y0), p.call(1, 1, y1), p.call(-1, 1, y1), w, col)
	quad(p.call(-1, -1, y0), p.call(1, -1, y0), p.call(1, -1, y1), p.call(-1, -1, y1), -w, col)
	quad(p.call(1, -1, y0), p.call(1, 1, y0), p.call(1, 1, y1), p.call(1, -1, y1), u, col)
	quad(p.call(-1, -1, y0), p.call(-1, 1, y0), p.call(-1, 1, y1), p.call(-1, -1, y1), -u, col)


func _shade(col: Color, amount: float) -> Color:
	var k := 1.0 + _rng.randf_range(-amount, amount)
	return Color(col.r * k, col.g * k, col.b * k)


## Paramento di pietre squadrate su un rettangolo verticale: origin è l'angolo in basso a sinistra,
## u la direzione orizzontale (lunga lu), la faccia guarda verso n. Corsi sfalsati e malta tra le pietre.
func stone_face(origin: Vector3, u: Vector3, lu: float, y0: float, y1: float, n: Vector3, base := STONE,
		jitter := 0.09) -> void:
	if lu <= 0.01 or y1 <= y0:
		return
	var o := Vector3(origin.x, 0.0, origin.z)
	var nn := n.normalized()
	# fondo di malta
	quad(o + Vector3(0, y0, 0), o + u * lu + Vector3(0, y0, 0), o + u * lu + Vector3(0, y1, 0), o + Vector3(0, y1, 0), nn, MORTAR)
	var gap := 0.06
	var lift := nn * 0.035
	var row := 0
	var y := y0
	while y < y1 - 0.01:
		var h := minf(BLOCK.y, y1 - y)
		var x := -BLOCK.x * 0.5 if row % 2 == 1 else 0.0
		while x < lu - 0.01:
			var a := maxf(x, 0.0)
			var b := minf(x + BLOCK.x * _rng.randf_range(0.8, 1.2), lu)
			if b - a > gap * 2.0:
				var col := _shade(base, jitter)
				var p0 := o + u * (a + gap) + Vector3(0, y + gap, 0) + lift
				var p1 := o + u * (b - gap) + Vector3(0, y + gap, 0) + lift
				var p2 := o + u * (b - gap) + Vector3(0, y + h - gap, 0) + lift
				var p3 := o + u * (a + gap) + Vector3(0, y + h - gap, 0) + lift
				quad(p0, p1, p2, p3, nn, col)
			x = b
		y += h
		row += 1


# ---------------------------------------------------------------- mura

## Un tratto di mura: rect a terra, altezza h, out = normale verso l'esterno (o ZERO: merli su tutti e due i lati).
func wall(r: Rect2, h: float, out: Vector3) -> void:
	var along_x := r.size.x >= r.size.y
	var u := Vector3.RIGHT if along_x else Vector3.BACK
	var w := Vector3.BACK if along_x else Vector3.RIGHT
	var length := r.size.x if along_x else r.size.y
	var thick := r.size.y if along_x else r.size.x
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var start := c - u * length * 0.5
	var both := out == Vector3.ZERO
	var outer_sign := 1.0 if both or out.dot(w) >= 0.0 else -1.0
	for sgn: float in [-1.0, 1.0]:
		var nrm := w * sgn
		var face_o := start + nrm * thick * 0.5
		stone_face(face_o, u, length, 0.0, h, nrm)
		_plinth(face_o, u, length, nrm)
		var is_outer := both or sgn == outer_sign
		if is_outer:
			_string_course(face_o, u, length, h - 0.55, nrm)
			_slits(face_o, u, length, h - 2.6, nrm, 7.0)
	# testate (dove il muro è tagliato da una porta o finisce contro una torre)
	for sgn: float in [-1.0, 1.0]:
		var e := c + u * sgn * length * 0.5
		stone_face(e - w * thick * 0.5 * sgn, w * sgn, thick, 0.0, h, u * sgn, STONE_DARK)
	# camminamento
	quad(Vector3(start.x, h, start.z) - w * thick * 0.5, Vector3(start.x, h, start.z) + w * thick * 0.5,
			Vector3(start.x, h, start.z) + w * thick * 0.5 + u * length, Vector3(start.x, h, start.z) - w * thick * 0.5 + u * length,
			Vector3.UP, WALKWAY)
	# i parapetti (merli e muretto interno) si disegnano per lato intero: vedi side_parapets()


func _plinth(face_o: Vector3, u: Vector3, length: float, n: Vector3) -> void:
	# zoccolo a scarpa: sporge di 0,4 m alla base e rientra a 1,2 m d'altezza
	var o := Vector3(face_o.x, 0, face_o.z)
	var a := o + n * 0.4
	var b := a + u * length
	var top_a := o + Vector3(0, 1.2, 0)
	var top_b := top_a + u * length
	var slope := (n * 1.2 + Vector3.UP * 0.4).normalized()
	quad(a, b, top_b, top_a, slope, STONE_DARK)
	tri(o, a, top_a, -u, STONE_DARK)
	tri(o + u * length, b, top_b, u, STONE_DARK)


func _string_course(face_o: Vector3, u: Vector3, length: float, y: float, n: Vector3) -> void:
	var c := Vector3(face_o.x, 0, face_o.z) + u * length * 0.5 + n * 0.06
	block(c, u, n, length * 0.5, 0.12, y - 0.14, y + 0.14, STONE_LIGHT, false)


func _slits(face_o: Vector3, u: Vector3, length: float, y: float, n: Vector3, step: float) -> void:
	var count := int(length / step)
	if count <= 0:
		return
	var o := Vector3(face_o.x, 0, face_o.z) + n * 0.05
	for k in count:
		var x := (k + 0.5) * length / count
		var p := o + u * x
		quad(p - u * 0.1 + Vector3(0, y, 0), p + u * 0.1 + Vector3(0, y, 0), p + u * 0.1 + Vector3(0, y + 1.3, 0),
				p - u * 0.1 + Vector3(0, y + 1.3, 0), n, SLIT)
		block(p + Vector3(0, 0, 0), u, n, 0.24, 0.04, y + 1.3, y + 1.45, STONE_LIGHT, false)   # architrave


## Parapetto merlato lungo un bordo: edge = centro del parapetto, u lungo il bordo, out verso fuori.
func battlements(edge: Vector3, u: Vector3, length: float, h: float, out: Vector3) -> void:
	var w := out.normalized()
	block(edge, u, w, length * 0.5, PARAPET_T * 0.5, h, h + 0.55, STONE)
	var pitch := MERLON_W + MERLON_GAP
	var count := maxi(1, int((length + MERLON_GAP) / pitch))
	var used := count * pitch - MERLON_GAP
	var first := -used * 0.5 + MERLON_W * 0.5
	for k in count:
		var p := edge + u * (first + k * pitch)
		block(p, u, w, MERLON_W * 0.5, PARAPET_T * 0.5, h + 0.55, h + 0.55 + MERLON_H, _shade(STONE, 0.06))
		block(p, u, w, MERLON_W * 0.5 + 0.03, PARAPET_T * 0.5 + 0.03, h + 0.55 + MERLON_H, h + 0.65 + MERLON_H, STONE_LIGHT)


## Parapetti di un lato di mura, da a a b (normale n verso l'esterno): merli fuori, muretto basso dentro.
## ext_* = di quanto ogni linea va oltre (positivo) o resta prima (negativo) dell'estremità del lato:
## così negli angoli i parapetti si incontrano a squadra invece di incrociarsi.
func side_parapets(a: Vector3, b: Vector3, n: Vector3, thick: float, h: float,
		ext_out_a: float, ext_out_b: float, ext_in_a: float, ext_in_b: float, merlons_both := false) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var u := (b - a) / length
	var off := thick * 0.5 - PARAPET_T * 0.5
	# fuori: merli
	var t0 := -ext_out_a
	var t1 := length + ext_out_b
	if t1 - t0 > 0.3:
		battlements(a + u * ((t0 + t1) * 0.5) + n * off, u, t1 - t0, h, n)
	# dentro: muretto basso (o merli, per le cinte interne viste da tutte e due le parti)
	t0 = -ext_in_a
	t1 = length + ext_in_b
	if t1 - t0 > 0.3:
		var e := a + u * ((t0 + t1) * 0.5) - n * off
		if merlons_both:
			battlements(e, u, t1 - t0, h, -n)
		else:
			block(e, u, n, (t1 - t0) * 0.5, PARAPET_T * 0.4, h, h + 0.6, STONE_DARK)


# ---------------------------------------------------------------- torri

func tower(r: Rect2, h: float) -> void:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var s := minf(r.size.x, r.size.y)
	var half := s * 0.5
	var dirs := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	for n: Vector3 in dirs:
		var u := Vector3.UP.cross(n).normalized() * -1.0
		var face_o := c + n * half - u * half
		stone_face(face_o, u, s, 0.0, h, n)
		_plinth(face_o + n * 0.0, u, s, n)
		_string_course(face_o, u, s, h * 0.45, n)
		_slits(face_o, u, s, h * 0.25, n, s * 0.55)
		_slits(face_o, u, s, h * 0.62, n, s * 0.55)
		# cantonali più chiari
		for side: float in [0.0, 1.0]:
			var corner := face_o + u * (side * s)
			var y := 0.0
			var k := 0
			while y < h - 0.6:
				var lu := 0.9 if k % 2 == 0 else 0.5
				var p := corner + u * (lu * 0.5 * (1.0 if side == 0.0 else -1.0)) + n * 0.05
				block(p, u, n, lu * 0.5, 0.05, y + 0.05, y + BLOCK.y - 0.05, _shade(STONE_LIGHT, 0.05), false)
				y += BLOCK.y
				k += 1
	# ballatoio sporgente su mensole, con i merli
	var over := 0.45
	var top := h - 0.2
	for n: Vector3 in dirs:
		var u := Vector3.UP.cross(n).normalized() * -1.0
		var mid := c + n * (half + over * 0.5 - 0.1)
		block(mid, u, n, half + over, over * 0.5 + 0.1, top - 0.35, top + 0.25, STONE_LIGHT, false)
		var count := int(s / 1.4)
		for k in count:
			var p := c + n * (half + 0.15) - u * half + u * ((k + 0.5) * s / count)
			block(p, u, n, 0.18, 0.2, top - 1.0, top - 0.35, STONE_DARK, false)          # mensole
		battlements(c + n * (half + over - PARAPET_T * 0.5), u, s + over * 2.0, top + 0.25, n)
	quad(Vector3(c.x - half - over, top + 0.25, c.z - half - over), Vector3(c.x + half + over, top + 0.25, c.z - half - over),
			Vector3(c.x + half + over, top + 0.25, c.z + half + over), Vector3(c.x - half - over, top + 0.25, c.z + half + over),
			Vector3.UP, WALKWAY)
	quad(Vector3(c.x - half, h, c.z - half), Vector3(c.x + half, h, c.z - half), Vector3(c.x + half, h, c.z + half),
			Vector3(c.x - half, h, c.z + half), Vector3.UP, WALKWAY)
	# asta con lo stendardo
	block(c, Vector3.RIGHT, Vector3.BACK, 0.08, 0.08, top + 0.25, top + 5.0, WOOD_DARK)
	var f0 := Vector3(c.x + 0.08, top + 4.9, c.z)
	quad(f0, f0 + Vector3(2.2, -0.2, 0), f0 + Vector3(2.2, -1.1, 0), f0 + Vector3(0, -1.4, 0), Vector3.BACK, HERALD)
	quad(f0, f0 + Vector3(2.2, -0.2, 0), f0 + Vector3(2.2, -1.1, 0), f0 + Vector3(0, -1.4, 0), Vector3.FORWARD, HERALD)


# ---------------------------------------------------------------- porte

const DOOR_SPRING := 4.3   ## dove comincia l'arco
const DOOR_TOP := 5.6      ## punta dell'arco


## Cornice di pietra della porta (fissa): arco a sesto acuto, conci chiari, merli sopra.
func gate_frame(center: Vector3, along: Vector3, out: Vector3, width: float, thick: float, h: float, breakable: bool) -> void:
	var u := along.normalized()
	var n := out.normalized()
	var hw := width * 0.5
	for sgn: float in [-1.0, 1.0]:
		var f := center + n * (thick * 0.5 * sgn)
		var nn := n * sgn
		var p := func(x: float, y: float) -> Vector3: return Vector3(f.x, y, f.z) + u * x
		# muratura sopra l'arco (pentagono con la punta in basso)
		tri(p.call(-hw, DOOR_SPRING), p.call(0, DOOR_TOP), p.call(-hw, h), nn, STONE)
		tri(p.call(0, DOOR_TOP), p.call(hw, h), p.call(-hw, h), nn, STONE)
		tri(p.call(0, DOOR_TOP), p.call(hw, DOOR_SPRING), p.call(hw, h), nn, STONE)
		# ghiera di conci chiari lungo l'arco
		var lift := nn * 0.06
		for k in 4:
			for side: float in [-1.0, 1.0]:
				var t0 := k / 4.0
				var t1 := (k + 1) / 4.0
				var a0 := Vector2(side * hw * (1.0 - t0), lerpf(DOOR_SPRING, DOOR_TOP, t0))
				var a1 := Vector2(side * hw * (1.0 - t1), lerpf(DOOR_SPRING, DOOR_TOP, t1))
				var col := _shade(STONE_LIGHT, 0.05)
				quad(p.call(a0.x, a0.y) + lift, p.call(a1.x, a1.y) + lift, p.call(a1.x, a1.y + 0.5) + lift,
						p.call(a0.x, a0.y + 0.5) + lift, nn, col)
		# stipiti
		for side: float in [-1.0, 1.0]:
			var x := side * (hw - 0.0)
			var y := 0.0
			var k := 0
			while y < DOOR_SPRING - 0.1:
				var wv := 0.55 if k % 2 == 0 else 0.35
				var cc: Vector3 = p.call(x - side * wv * 0.5, 0) + lift
				block(cc, u, nn, wv * 0.5, 0.06, y + 0.04, minf(y + BLOCK.y, DOOR_SPRING) - 0.04, _shade(STONE_LIGHT, 0.05), false)
				y += BLOCK.y
				k += 1
		# stemma sopra la porta, dal lato esterno
		if sgn > 0.0 and breakable:
			var sc: Vector3 = p.call(0, h - 0.75) + nn * 0.08
			quad(sc - u * 0.45 + Vector3(0, 0.4, 0), sc + u * 0.45 + Vector3(0, 0.4, 0), sc + u * 0.45 + Vector3(0, -0.15, 0),
					sc - u * 0.45 + Vector3(0, -0.15, 0), nn, HERALD)
			tri(sc - u * 0.45 + Vector3(0, -0.15, 0), sc + u * 0.45 + Vector3(0, -0.15, 0), sc + Vector3(0, -0.6, 0), nn, HERALD)
			quad(sc - u * 0.08 + Vector3(0, 0.3, 0) + nn * 0.01, sc + u * 0.08 + Vector3(0, 0.3, 0) + nn * 0.01,
					sc + u * 0.08 + Vector3(0, -0.45, 0) + nn * 0.01, sc - u * 0.08 + Vector3(0, -0.45, 0) + nn * 0.01, nn, GOLD)
	# intradosso dell'arco
	for side: float in [-1.0, 1.0]:
		var a := Vector3(center.x, DOOR_SPRING, center.z) + u * side * hw
		var b := Vector3(center.x, DOOR_TOP, center.z)
		var down := (Vector3(0, -(DOOR_TOP - DOOR_SPRING), 0) + u * side * hw).cross(n).normalized()
		if down.y > 0.0:
			down = -down
		quad(a - n * thick * 0.5, a + n * thick * 0.5, b + n * thick * 0.5, b - n * thick * 0.5, down, STONE_DARK)
	# camminamento e merli sopra la porta
	var top := Vector3(center.x, h, center.z)
	quad(top - u * hw - n * thick * 0.5, top + u * hw - n * thick * 0.5, top + u * hw + n * thick * 0.5,
			top - u * hw + n * thick * 0.5, Vector3.UP, WALKWAY)


## I battenti (si nascondono quando la porta è abbattuta).
func gate_doors(center: Vector3, along: Vector3, out: Vector3, width: float, breakable: bool) -> void:
	var u := along.normalized()
	var n := out.normalized()
	var hw := width * 0.5 - 0.05
	var dark := 1.0 if breakable else 0.7
	var t := 0.18
	var plank := 0.42
	for sgn: float in [-1.0, 1.0]:
		var nn := n * sgn
		var f := Vector3(center.x, 0, center.z) + nn * t
		var x := -hw
		var k := 0
		while x < hw - 0.01:
			var x1 := minf(x + plank, hw)
			var col := _shade(WOOD, 0.12)
			col = Color(col.r * dark, col.g * dark, col.b * dark)
			var top0 := _arch_y(x, hw)
			var top1 := _arch_y(x1, hw)
			quad(f + u * x, f + u * x1, f + u * x1 + Vector3(0, top1, 0), f + u * x + Vector3(0, top0, 0), nn, col)
			x = x1
			k += 1
		# fasce di ferro con le borchie
		for y: float in [0.8, 2.3, 3.7]:
			var a := f + nn * 0.035 + Vector3(0, y - 0.12, 0)
			quad(a - u * hw, a + u * hw, a + u * hw + Vector3(0, 0.24, 0), a - u * hw + Vector3(0, 0.24, 0), nn, IRON)
			var studs := int(width / 0.9)
			for s in studs:
				var p := f + nn * 0.06 + u * (-hw + (s + 0.5) * (2.0 * hw) / studs) + Vector3(0, y, 0)
				block(p, u, nn, 0.06, 0.03, y - 0.06, y + 0.06, IRON, false)
		# fessura tra i battenti e anelli
		var mid := f + nn * 0.04
		quad(mid - u * 0.04, mid + u * 0.04, mid + u * 0.04 + Vector3(0, DOOR_TOP - 0.05, 0), mid - u * 0.04 + Vector3(0, DOOR_TOP - 0.05, 0), nn, WOOD_DARK)
		for side: float in [-1.0, 1.0]:
			block(mid + u * side * 0.45 + nn * 0.03, u, nn, 0.12, 0.03, 2.75, 2.95, IRON, false)
	# bordi dei battenti
	for side: float in [-1.0, 1.0]:
		var e := Vector3(center.x, 0, center.z) + u * side * hw
		quad(e - n * t, e + n * t, e + n * t + Vector3(0, DOOR_SPRING, 0), e - n * t + Vector3(0, DOOR_SPRING, 0), u * side, WOOD_DARK)


func _arch_y(x: float, hw: float) -> float:
	return lerpf(DOOR_TOP, DOOR_SPRING, absf(x) / maxf(hw, 0.01))


## Macerie di una porta abbattuta: tavole spezzate e pietre.
func rubble(center: Vector3, along: Vector3, out: Vector3, width: float, thick: float) -> void:
	var u := along.normalized()
	var n := out.normalized()
	for k in 14:
		var p := center + u * _rng.randf_range(-width * 0.45, width * 0.45) + n * _rng.randf_range(-thick, thick * 1.2)
		var su := _rng.randf_range(0.3, 0.7)
		var y := _rng.randf_range(0.0, 0.25)
		var rot := Basis(Vector3.UP, _rng.randf_range(0, TAU))
		block(p, rot * u, rot * n, su, su * 0.8, y, y + su * 0.8, _shade(STONE_DARK, 0.12))
	for k in 9:
		var p := center + u * _rng.randf_range(-width * 0.4, width * 0.4) + n * _rng.randf_range(-thick * 0.5, thick * 1.5)
		var rot := Basis(Vector3.UP, _rng.randf_range(0, TAU))
		var y := _rng.randf_range(0.0, 0.4)
		block(p, rot * u, rot * n, _rng.randf_range(0.8, 1.6), 0.2, y, y + 0.08, _shade(WOOD, 0.15), false)
