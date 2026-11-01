class_name FortressMapView
extends Control
## Pianta di una fortezza vista dall'alto. La usa l'editor (con anteprime e strumenti)
## e la schermata di preparazione (solo per mostrarla).
## Nord in alto: gli attaccanti arrivano dal basso (sud, z positivo).

const GROUND := Color(0.2, 0.27, 0.15)
const BUILD := Color(0.26, 0.33, 0.19)
const INTERIOR := Color(0.55, 0.48, 0.33, 0.55)
const STONE := Color(0.62, 0.6, 0.56)
const TOWER := Color(0.45, 0.43, 0.4)
const GATE := Color(0.62, 0.38, 0.18)
const POSTERN := Color(0.33, 0.22, 0.13)
const CAPTURE := Color(1.0, 0.85, 0.35)
const ATTACK_ZONE := Color(0.3, 0.5, 1.0, 0.16)
const OK_COL := Color(0.45, 1.0, 0.5, 0.85)
const BAD_COL := Color(1.0, 0.35, 0.3, 0.85)

var layout: FortressLayout
var view := Rect2(-140.0, -180.0, 280.0, 250.0)   ## porzione di mondo mostrata (x, z)
var show_labels := true
var show_attack_zone := true
var editing := false

# anteprime impostate dall'editor
var preview_line := []          ## [Vector2 a, Vector2 b, valido]
var preview_rect := []          ## [Rect2, valido]
var preview_point := []         ## [Vector2, raggio, valido]
var highlight := []             ## [Rect2] oppure [Vector2 centro, raggio]

var _interior_runs: Array[Rect2] = []


func set_layout(l: FortressLayout) -> void:
	layout = l
	_interior_runs.clear()
	if l != null:
		# l'interno come strisce orizzontali (una per riga di celle), calcolate una volta
		var n := l.grid_n
		var c := FortressLayout.CELL
		for z in n:
			var start := -1
			for x in n + 1:
				var inside := x < n and l.grid[z * n + x] == 1
				if inside and start < 0:
					start = x
				elif not inside and start >= 0:
					_interior_runs.append(Rect2(start * c - FortressLayout.MAP_HALF, z * c - FortressLayout.MAP_HALF, (x - start) * c, c))
					start = -1
	queue_redraw()


# ---------------------------------------------------------------- coordinate

func _scale() -> float:
	return minf(size.x / view.size.x, size.y / view.size.y)


func _origin() -> Vector2:
	var s := _scale()
	return (size - view.size * s) * 0.5 - view.position * s


func to_screen(w: Vector2) -> Vector2:
	return _origin() + w * _scale()


func to_world(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func _rect_screen(r: Rect2) -> Rect2:
	return Rect2(to_screen(r.position), r.size * _scale())


# ---------------------------------------------------------------- disegno

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	draw_rect(_rect_screen(FortressLayout.BUILD_AREA), BUILD)
	var font := get_theme_default_font()
	if show_attack_zone:
		var zone := Rect2(-110.0, 8.0, 220.0, 112.0)
		draw_rect(_rect_screen(zone), ATTACK_ZONE)
		if show_labels:
			var p := to_screen(Vector2(-105.0, 22.0))
			draw_string(font, p, "Schieramento degli attaccanti (arrivano da sud)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 1.0))
	# griglia: 10 m, più marcata ogni 50 m
	if editing:
		var x := floorf(view.position.x / 10.0) * 10.0
		while x <= view.end.x:
			var strong := is_zero_approx(fmod(absf(x), 50.0))
			draw_line(to_screen(Vector2(x, view.position.y)), to_screen(Vector2(x, view.end.y)), Color(1, 1, 1, 0.1 if strong else 0.04))
			x += 10.0
		var z := floorf(view.position.y / 10.0) * 10.0
		while z <= view.end.y:
			var strong := is_zero_approx(fmod(absf(z), 50.0))
			draw_line(to_screen(Vector2(view.position.x, z)), to_screen(Vector2(view.end.x, z)), Color(1, 1, 1, 0.1 if strong else 0.04))
			z += 10.0
	if layout == null:
		return
	for r in _interior_runs:
		draw_rect(_rect_screen(r), INTERIOR)
	for r in layout.wall_rects:
		draw_rect(_rect_screen(r), STONE)
	for t in layout.towers:
		draw_rect(_rect_screen(t["rect"]), TOWER)
		draw_rect(_rect_screen(t["rect"]), Color(0, 0, 0, 0.4), false, 1.0)
	for g in layout.gates:
		draw_rect(_rect_screen(g["rect"]), GATE if g["breakable"] else POSTERN)
		if show_labels:
			var c: Vector3 = g["center"]
			var n: Vector3 = g["normal"]
			var lp := to_screen(Vector2(c.x, c.z) + Vector2(n.x, n.z) * 7.0)
			var txt: String = g["name"]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, lp + Vector2(-w * 0.5, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.92, 0.8))
	if layout.has_capture:
		var cp := to_screen(Vector2(layout.capture.x, layout.capture.z))
		var rad := 14.0 * _scale()
		draw_circle(cp, rad, Color(CAPTURE, 0.18))
		draw_arc(cp, rad, 0, TAU, 48, CAPTURE, 2.0)
		draw_line(cp + Vector2(0, 2), cp + Vector2(0, -rad * 0.8), CAPTURE, 2.0)
		if show_labels:
			draw_string(font, cp + Vector2(-48, rad + 14), "Punto di vittoria", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CAPTURE)
	# anteprime dell'editor
	if not highlight.is_empty():
		if highlight[0] is Rect2:
			draw_rect(_rect_screen(highlight[0]).grow(2), BAD_COL, false, 2.0)
		else:
			draw_arc(to_screen(highlight[0]), float(highlight[1]) * _scale() + 3.0, 0, TAU, 40, BAD_COL, 2.0)
	if not preview_line.is_empty():
		var col := OK_COL if preview_line[2] else BAD_COL
		draw_line(to_screen(preview_line[0]), to_screen(preview_line[1]), col, maxf(3.0, FortressLayout.WALL_T * _scale()))
		var length := (preview_line[1] as Vector2).distance_to(preview_line[0])
		draw_string(font, to_screen(preview_line[1]) + Vector2(10, -8), "%d m" % int(round(length)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	if not preview_rect.is_empty():
		draw_rect(_rect_screen(preview_rect[0]), OK_COL if preview_rect[1] else BAD_COL)
	if not preview_point.is_empty():
		var col := OK_COL if preview_point[2] else BAD_COL
		draw_arc(to_screen(preview_point[0]), float(preview_point[1]) * _scale(), 0, TAU, 40, col, 2.0)
