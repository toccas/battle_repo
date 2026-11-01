class_name UnitCard
extends Control
## Carta di un reparto in basso, a forma di stendardo nel colore della squadra:
## ritratto con cornice dorata e tre barre (salute, morale, munizioni per chi tira).
## Selezionata diventa dorata; in rotta il ritratto si tinge di rosso; distrutta o fuggita si spegne.

const GOLD := Color(0.89, 0.76, 0.35)
const GOLD_DARK := Color(0.6, 0.48, 0.18)
const HP := Color(0.32, 0.82, 0.42)
const MORALE := Color(0.95, 0.79, 0.29)
const AMMO := Color(0.5, 0.7, 0.94)
const TRACK := Color(0.07, 0.1, 0.2)
const POINT := 0.14          ## altezza della punta, in frazione della carta

var regiment: Regiment
var icon: Texture2D
var banner := Color(0.18, 0.34, 0.72)
var hp := 1.0
var morale := 1.0
var ammo := -1.0             ## < 0: niente barra delle munizioni
var selected := false
var routing := false
var gone := false
var hovered := false


func setup(r: Regiment) -> void:
	regiment = r
	icon = r.stats.icon
	if icon == null and ResourceLoader.exists("res://data/icons/%s.res" % r.stats.id):
		icon = load("res://data/icons/%s.res" % r.stats.id)
	banner = r.team_color.darkened(0.25)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())


## Legge lo stato del reparto; ridisegna solo se qualcosa è cambiato.
func refresh() -> void:
	var r := regiment
	var n_hp := clampf(r.hp_total / maxf(r.start_hp_total, 0.001), 0.0, 1.0)
	var n_mo := clampf(r.morale / 100.0, 0.0, 1.0)
	var n_am := -1.0
	if r.stats.is_ranged:
		n_am = clampf(float(r.ammo) / maxf(float(r.start_ammo), 1.0), 0.0, 1.0)
	var n_gone := not r.is_on_field()
	var n_rout := r.state == Regiment.State.ROUTING
	if absf(n_hp - hp) > 0.002 or absf(n_mo - morale) > 0.002 or absf(n_am - ammo) > 0.002 \
			or r.selected != selected or n_gone != gone or n_rout != routing:
		hp = n_hp
		morale = n_mo
		ammo = n_am
		selected = r.selected
		gone = n_gone
		routing = n_rout
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var tip := h * POINT
	var fill := GOLD if selected else banner
	if gone:
		fill = Color(0.25, 0.22, 0.22)
	elif hovered and not selected:
		fill = banner.lightened(0.18)
	# stendardo con la punta in basso, con un filo scuro attorno
	var outer := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h - tip), Vector2(w * 0.5, h), Vector2(0, h - tip)])
	draw_colored_polygon(outer, Color(0.03, 0.04, 0.08, 0.9))
	var m := 1.5
	var inner := PackedVector2Array([Vector2(m, m), Vector2(w - m, m), Vector2(w - m, h - tip - m * 0.5),
			Vector2(w * 0.5, h - m * 1.8), Vector2(m, h - tip - m * 0.5)])
	draw_colored_polygon(inner, fill)
	# finestra del ritratto con cornice dorata
	var pad := 4.0
	var pic := Rect2(pad, pad, w - pad * 2.0, (w - pad * 2.0) * 1.15)
	draw_rect(pic.grow(1.0), GOLD_DARK if not selected else Color(0.35, 0.27, 0.08))
	draw_rect(pic, Color(0.1, 0.16, 0.34))
	draw_rect(Rect2(pic.position, Vector2(pic.size.x, pic.size.y * 0.55)), Color(0.16, 0.24, 0.46))   # luce in alto
	if icon != null:
		var tint := Color.WHITE
		if gone:
			tint = Color(0.35, 0.35, 0.35)
		elif routing:
			tint = Color(1.0, 0.35, 0.25)
		draw_texture_rect(icon, pic, false, tint)
	draw_rect(pic.grow(1.0), GOLD if not selected else Color(0.4, 0.3, 0.08), false, 1.0)
	# barre
	var y := pic.end.y + 4.0
	var bh := 5.0
	for pair in [[hp, HP], [morale, MORALE], [ammo, AMMO]]:
		var v: float = pair[0]
		if v < 0.0:
			break
		var bar := Rect2(pad, y, w - pad * 2.0, bh)
		draw_rect(bar.grow(1.0), Color(0.03, 0.05, 0.12))
		draw_rect(bar, TRACK)
		if v > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * v, bh)), pair[1] if not gone else Color(0.4, 0.4, 0.4))
		y += bh + 3.0
