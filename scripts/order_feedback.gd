class_name OrderFeedback
extends Node3D
## Segnali disegnati a terra: frecce degli ordini, sagome della destinazione,
## cerchi di gittata. Tutto viene ridisegnato a ogni frame in un'unica ImmediateMesh.

const Y := 0.12
const MOVE_COL := Color(0.35, 1.0, 0.45, 0.8)
const RUN_COL := Color(0.35, 0.85, 1.0, 0.85)
const ATTACK_COL := Color(1.0, 0.28, 0.18, 0.9)
const OUT_OF_RANGE_COL := Color(1.0, 0.65, 0.15, 0.9)
const RANGE_COL := Color(1.0, 0.85, 0.3, 0.75)

var _im: ImmediateMesh
var _open := false
## Moltiplicatore degli spessori: il controller lo aggiorna con lo zoom della camera,
## così frecce e cerchi restano leggibili sia da vicino sia dalla vista d'insieme.
var thickness_scale := 1.0
## Quota a cui disegnare (0 a terra; l'altezza del camminamento per le mura).
var height := 0.0


func _ready() -> void:
	_im = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 5
	mi.material_override = mat
	add_child(mi)


func begin() -> void:
	_im.clear_surfaces()
	_open = false


func finish() -> void:
	if _open:
		_im.surface_end()
		_open = false


# ---------------------------------------------------------------- primitive

func _v(p: Vector3, col: Color) -> void:
	if not _open:
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_open = true
	_im.surface_set_color(col)
	_im.surface_add_vertex(Vector3(p.x, Y + height, p.z))


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color) -> void:
	# a,b con colore ca; c,d con colore cb (permette le sfumature)
	_v(a, ca)
	_v(b, ca)
	_v(c, cb)
	_v(a, ca)
	_v(c, cb)
	_v(d, cb)


## Freccia piatta da `from` a `to`: parte trasparente e diventa piena verso la punta.
func arrow(from: Vector3, to: Vector3, col: Color, width := 0.9) -> void:
	var d := Regiment._flat(to - from)
	var length := d.length()
	if length < 2.0:
		return
	width *= thickness_scale
	var dir := d / length
	var side := Vector3(-dir.z, 0.0, dir.x)
	var head := minf(4.5 * thickness_scale, length * 0.45)
	var head_w := width * 3.0
	var shaft_end := to - dir * head
	var faded := Color(col, col.a * 0.15)
	var hw := width * 0.5
	_quad(from - side * hw, from + side * hw, shaft_end + side * hw, shaft_end - side * hw, faded, col)
	_v(shaft_end - side * head_w * 0.5, col)
	_v(shaft_end + side * head_w * 0.5, col)
	_v(to, col)


## Cerchio a terra (es. gittata). `fill` > 0 colora anche l'interno.
func ring(center: Vector3, radius: float, col: Color, thickness := 0.6, fill := 0.0) -> void:
	thickness *= thickness_scale
	var seg := clampi(int(radius * 0.8), 32, 128)
	var inner := radius - thickness * 0.5
	var outer := radius + thickness * 0.5
	var fill_col := Color(col, fill)
	var edge_fill := Color(col, fill * 2.5)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		_quad(center + d0 * inner, center + d1 * inner, center + d1 * outer, center + d0 * outer, col, col)
		if fill > 0.0:
			# riempimento più intenso vicino al bordo: si legge meglio dove finisce la gittata
			_v(center, fill_col)
			_v(center + d0 * inner, edge_fill)
			_v(center + d1 * inner, edge_fill)


## Sagoma della formazione nella posizione di arrivo, con il lato del fronte più marcato.
func footprint(front_center: Vector3, face: Vector3, cols: int, alive: int, spacing: float,
		row_spacing: float, col: Color) -> void:
	var f := Regiment._flat(face).normalized()
	var rv := Vector3(-f.z, 0.0, f.x)
	var n := clampi(cols, 1, maxi(alive, 1))
	var hw := (n - 1) * spacing * 0.5 + 0.6
	var depth := (ceili(float(alive) / n) - 1) * row_spacing + 0.6
	var fl := front_center - rv * hw + f * 0.3
	var fr := front_center + rv * hw + f * 0.3
	var bl := fl - f * depth
	var br := fr - f * depth
	var soft := Color(col, col.a * 0.18)
	_quad(fl, fr, br, bl, soft, soft)            # interno tenue
	_line(fl, fr, col, 0.55)                       # fronte
	_line(fr, br, col, 0.25)
	_line(br, bl, col, 0.25)
	_line(bl, fl, col, 0.25)


func _line(a: Vector3, b: Vector3, col: Color, w: float) -> void:
	var d := Regiment._flat(b - a)
	if d.length_squared() < 0.0001:
		return
	var side := Vector3(-d.z, 0.0, d.x).normalized() * w * 0.5 * thickness_scale
	_quad(a - side, a + side, b + side, b - side, col, col)
