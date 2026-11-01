class_name PlayerController
extends Node
## Selezione e ordini in stile Total War (doc: "Comandi e controlli").

var deploy_zone := Rect2(-110.0, 35.0, 220.0, 95.0)   ## x, z, larghezza, profondità
const DOUBLE_CLICK := 0.35

var battle: BattleManager
var rig: CameraRig
var ui: BattleUI
var team := 0
var selected: Array[Regiment] = []
var groups := {}

var _l_down := false
var _l_start := Vector2.ZERO
var _last_l_time := -10.0
var _last_l_reg: Regiment = null
var _r_down := false
var _r_start_screen := Vector2.ZERO
var _r_start_world := Vector3.ZERO
var _last_r_time := -10.0
var _last_r_pos := Vector2.ZERO
var feedback: OrderFeedback

# stato del cursore (aggiornato a ogni frame)
var hover_enemy: Regiment = null
var hover_own: Regiment = null
var hover_gate: Fortress.Gate = null
var _mouse := Vector2(-1, -1)
var _hover_point := Vector3.ZERO
var _hover_valid := false
var _drag_end := Vector3.ZERO

const SWORD_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
<g stroke="#15161a" stroke-width="1.3" stroke-linejoin="round">
<polygon points="1.5,1.5 7,2.5 21.5,17 17,21.5 2.5,7" fill="#eef1f6"/>
<polygon points="14.5,24.5 24.5,14.5 26.5,16.5 16.5,26.5" fill="#d4a944"/>
<polygon points="20,23.5 23.5,20 28,24.5 24.5,28" fill="#6e4a2a"/>
<circle cx="27.6" cy="27.6" r="2.6" fill="#d4a944"/>
</g></svg>"""


func setup(b: BattleManager, r: CameraRig, u: BattleUI) -> void:
	battle = b
	rig = r
	ui = u
	feedback = OrderFeedback.new()
	feedback.name = "OrderFeedback"
	battle.add_child(feedback)
	_setup_cursor()


## Il cursore a spada è registrato sulla forma "CROSS": basta cambiare forma per mostrarlo.
func _setup_cursor() -> void:
	var img := Image.new()
	if img.load_svg_from_string(SWORD_SVG, 1.0) == OK:
		Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), Input.CURSOR_CROSS, Vector2(2, 2))


func my_regiments() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in battle.regiments:
		if r.team == team:
			out.append(r)
	return out


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_l_down = true
				_l_start = mb.position
			elif _l_down:
				_l_down = false
				ui.hide_box()
				_finish_left(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_r_down = true
				_r_start_screen = mb.position
				_r_start_world = ground_point(mb.position)
			elif _r_down:
				_r_down = false
				_finish_right(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _l_down and mm.position.distance_to(_l_start) > 6.0:
			ui.show_box(Rect2(_l_start, mm.position - _l_start).abs())
		if _r_down:
			_drag_end = ground_point(mm.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_key(k)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CROSS)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Riceve tutti i movimenti del mouse, anche sopra l'interfaccia, per sapere dov'è il cursore.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		_mouse = (event as InputEventMouseButton).position


func _process(_delta: float) -> void:
	_update_hover()
	_draw_feedback()


func _key(k: InputEventKey) -> void:
	var ctrl := k.ctrl_pressed or k.meta_pressed
	match k.keycode:
		KEY_SPACE:
			if battle.phase != BattleManager.Phase.DEPLOY:
				battle.paused = not battle.paused
		KEY_TAB:
			battle.time_scale = 1.0 if battle.time_scale >= 3.0 else battle.time_scale + 1.0
		KEY_BACKSPACE:
			for r in selected:
				r.order_halt()
		KEY_ENTER, KEY_KP_ENTER:
			battle.start_battle()
		KEY_ESCAPE:
			set_selection([])
		KEY_A:
			if ctrl:
				set_selection(my_regiments())
		KEY_F:
			if not selected.is_empty():
				rig.follow = null if rig.follow == selected[0] else selected[0]
		KEY_H:
			ui.toggle_help()
		KEY_R:
			if battle.phase == BattleManager.Phase.ENDED:
				get_tree().reload_current_scene()
		KEY_F9:
			get_tree().reload_current_scene()
		KEY_M, KEY_F10:
			if k.keycode == KEY_F10 or battle.phase == BattleManager.Phase.ENDED:
				# dopo una prova dall'editor si torna all'editor, con le modifiche ancora aperte
				var back := "res://fortress_editor.tscn" if GameConfig.return_to_editor else "res://army_select.tscn"
				get_tree().change_scene_to_file(back)
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var n := int(k.keycode - KEY_0)
				if ctrl:
					var copy: Array[Regiment] = []
					copy.append_array(selected)
					groups[n] = copy
				elif groups.has(n):
					var g: Array[Regiment] = []
					g.assign(groups[n])
					set_selection(g)
					if not g.is_empty():
						rig.focus_on(g[0].mid())


# ---------------------------------------------------------------- selezione

func set_selection(list: Array[Regiment]) -> void:
	for r in selected:
		r.selected = false
	selected.clear()
	for r in list:
		if r.team == team and r.is_on_field() and not selected.has(r):
			selected.append(r)
			r.selected = true


func toggle(r: Regiment) -> void:
	var list: Array[Regiment] = []
	list.append_array(selected)
	if list.has(r):
		list.erase(r)
	else:
		list.append(r)
	set_selection(list)


func on_card_clicked(r: Regiment, shift: bool, double: bool) -> void:
	if shift:
		toggle(r)
	else:
		set_selection([r])
	if double:
		rig.focus_on(r.mid())


func _finish_left(screen: Vector2, shift: bool) -> void:
	if screen.distance_to(_l_start) < 6.0:
		var r := pick(screen, team)
		var now := Time.get_ticks_msec() / 1000.0
		if r == null:
			if not shift:
				set_selection([])
			return
		if r == _last_l_reg and now - _last_l_time < DOUBLE_CLICK:
			# doppio click: tutte le unità dello stesso tipo
			var same: Array[Regiment] = []
			for o in my_regiments():
				if o.stats.id == r.stats.id:
					same.append(o)
			set_selection(same)
		elif shift:
			toggle(r)
		else:
			set_selection([r])
		_last_l_reg = r
		_last_l_time = now
		return
	var rect := Rect2(_l_start, screen - _l_start).abs()
	var list: Array[Regiment] = []
	if shift:
		list.append_array(selected)
	for r in my_regiments():
		var p := r.mid() + Vector3(0, r.base_y(), 0)
		if rig.cam.is_position_behind(p):
			continue
		if rect.has_point(rig.cam.unproject_position(p)):
			list.append(r)
	set_selection(list)


# ---------------------------------------------------------------- ordini

func _finish_right(screen: Vector2, shift := false) -> void:
	if selected.is_empty():
		return
	var end := ground_point(screen)
	var drag := Regiment._flat(end - _r_start_world).length()
	var now := Time.get_ticks_msec() / 1000.0
	var dbl := now - _last_r_time < DOUBLE_CLICK and screen.distance_to(_last_r_pos) < 15.0
	_last_r_time = now
	_last_r_pos = screen
	var deploying := battle.phase == BattleManager.Phase.DEPLOY
	if drag >= 3.0:
		for plan: Dictionary in plan_line(_r_start_world, end):
			var r: Regiment = plan["reg"]
			if deploying:
				r.teleport(clamp_to_zone(plan["pos"]), plan["face"], plan["cols"])
			elif shift:
				r.queue_move(plan["pos"], plan["face"], false, plan["cols"])
			else:
				r.order_move(plan["pos"], plan["face"], false, plan["cols"])
		return
	var enemy := pick(screen, 1 - team)
	if enemy != null and not deploying:
		for r in selected:
			if shift:
				r.queue_attack(enemy, dbl)
			else:
				r.order_attack(enemy, dbl)
		return
	var gate := _pick_gate(end)
	if gate != null and not deploying:
		for r in selected:
			r.order_breach(gate)
		return
	var side := wall_side_under(screen)
	if side >= 0:
		for plan: Dictionary in wall_plan(side, wall_point(screen)):
			var r: Regiment = plan["reg"]
			if deploying:
				r.teleport_to_wall(side, plan["pos"])
			elif shift:
				r.queue_move(plan["pos"], battle.fortress.wall_normal(side), dbl, -1, side)
			else:
				r.order_move(plan["pos"], battle.fortress.wall_normal(side), dbl, -1, side)
		return
	for plan: Dictionary in group_move_plan(end, shift):
		var r: Regiment = plan["reg"]
		if deploying:
			r.teleport(clamp_to_zone(plan["pos"]), plan["face"])
		elif shift:
			r.queue_move(plan["pos"], plan["face"], dbl)
		else:
			r.order_move(plan["pos"], plan["face"], dbl)


## Spostamento di gruppo: ognuno mantiene la sua posizione rispetto agli altri.
## Con Shift si parte dall'ultima tappa già ordinata e ci si gira nella direzione di marcia.
func group_move_plan(end: Vector3, shift: bool) -> Array:
	var regs: Array[Regiment] = []
	for r in selected:
		if r.can_take_orders():
			regs.append(r)
	if regs.is_empty():
		return []
	var c := Vector3.ZERO
	for r in regs:
		c += r.planned_end() if shift else r.center
	c /= regs.size()
	var out := []
	for r in regs:
		var from := r.planned_end() if shift else r.center
		var tgt := end + (from - c)
		var face := r.facing
		if shift and Regiment._flat(tgt - from).length() > 1.0:
			face = Regiment._flat(tgt - from).normalized()
		out.append({"reg": r, "from": from, "pos": tgt, "face": face})
	return out


## Sulle mura: i reparti che possono salirci si mettono in fila lungo il camminamento,
## centrati sul punto indicato.
func wall_plan(side: int, p: Vector3) -> Array:
	var f := battle.fortress
	var regs: Array[Regiment] = []
	for r in selected:
		if r.can_take_orders() and Fortress.can_man_walls(r):
			regs.append(r)
	if regs.is_empty():
		return []
	var dir: Vector3 = f.sides[side]["dir"]
	var widths: Array[float] = []
	var total := 0.0
	for r in regs:
		var w := (f.wall_cols_for(r, side) - 1) * r.stats.spacing
		widths.append(w)
		total += w
	total += 3.0 * (regs.size() - 1)
	var cursor := -total * 0.5
	var out := []
	for k in regs.size():
		var r := regs[k]
		var pt := Regiment._flat(p) + dir * (cursor + widths[k] * 0.5)
		cursor += widths[k] + 3.0
		out.append({"reg": r, "pos": f.wall_center_for(side, pt, widths[k]),
				"cols": f.wall_cols_for(r, side)})
	return out


## Trascinamento col destro: dispone i selezionati lungo la linea, da sinistra a destra.
func plan_line(a: Vector3, b: Vector3) -> Array:
	var line := Regiment._flat(b - a)
	var length := line.length()
	var dir := line / maxf(length, 0.001)
	var face := Vector3(-dir.z, 0.0, dir.x)
	var camf := Regiment._flat(-rig.cam.global_transform.basis.z)
	if face.dot(camf) < 0.0:
		face = -face
	var rv := Vector3(-face.z, 0.0, face.x)
	var left := a if a.dot(rv) < b.dot(rv) else b
	var regs: Array[Regiment] = []
	for r in selected:
		if r.can_take_orders():
			regs.append(r)
	if regs.is_empty():
		return []
	regs.sort_custom(func(x: Regiment, y: Regiment) -> bool: return x.mid().dot(rv) < y.mid().dot(rv))
	var gap := 3.0
	var total_w := 0.0
	for r in regs:
		total_w += r.alive_count * r.stats.spacing
	var avail := maxf(length - gap * (regs.size() - 1), regs.size() * 1.0)
	var cursor := 0.0
	var out := []
	for r in regs:
		var seg := avail * (r.alive_count * r.stats.spacing) / total_w
		var n := clampi(int(round(seg / r.stats.spacing)) + 1, 1, r.alive_count)
		out.append({"reg": r, "pos": left + rv * (cursor + seg * 0.5), "face": face, "cols": n})
		cursor += seg + gap
	return out


# ---------------------------------------------------------------- feedback

func _update_hover() -> void:
	var enemy: Regiment = null
	var own: Regiment = null
	_hover_valid = _mouse.x >= 0.0 and not ui.is_over_ui(_mouse)
	if _hover_valid:
		_hover_point = ground_point(_mouse)
		if not selected.is_empty() and battle.phase != BattleManager.Phase.DEPLOY:
			enemy = pick(_mouse, 1 - team)
		if enemy == null:
			own = pick(_mouse, team)
	var gate: Fortress.Gate = null
	if _hover_valid and enemy == null and own == null and not selected.is_empty() \
			and battle.phase != BattleManager.Phase.DEPLOY:
		gate = _pick_gate(_hover_point)
	if gate != hover_gate:
		if battle.fortress != null:
			battle.fortress.set_gate_hover(hover_gate, false)
			battle.fortress.set_gate_hover(gate, true)
		hover_gate = gate
	if enemy != hover_enemy:
		if hover_enemy != null:
			hover_enemy.set_outline(false)
		if enemy != null:
			enemy.set_outline(true, Regiment.OUTLINE_ENEMY)
		hover_enemy = enemy
	if own != hover_own:
		if hover_own != null and hover_own != hover_enemy:
			hover_own.set_outline(false)
		if own != null:
			own.set_outline(true, Regiment.OUTLINE_OWN)
		hover_own = own
	var shape := Input.CURSOR_CROSS if (hover_enemy != null or hover_gate != null) else Input.CURSOR_ARROW
	if Input.get_current_cursor_shape() != shape:
		Input.set_default_cursor_shape(shape)


func _draw_feedback() -> void:
	feedback.thickness_scale = clampf(rig.dist / 60.0, 0.6, 2.4)
	feedback.begin()
	var deploying := battle.phase == BattleManager.Phase.DEPLOY
	var shift := Input.is_key_pressed(KEY_SHIFT)
	# 1. ordini già dati ai reggimenti selezionati + gittata degli arcieri
	for r in selected:
		if not r.is_on_field():
			continue
		if r.uses_missiles():
			feedback.height = r.base_y()
			feedback.ring(r.mid(), r.missile_range(), OrderFeedback.RANGE_COL, 0.7, 0.05)
			feedback.height = 0.0
		_draw_route(r)
	# 2. anteprima di quello che succederà cliccando
	if _r_down and Regiment._flat(_drag_end - _r_start_world).length() >= 3.0:
		for plan: Dictionary in plan_line(_r_start_world, _drag_end):
			var r: Regiment = plan["reg"]
			var p: Vector3 = clamp_to_zone(plan["pos"]) if deploying else plan["pos"]
			if not deploying:
				feedback.arrow(r.planned_end() if shift else r.center, p, Color(OrderFeedback.MOVE_COL, 0.5), 0.7)
			feedback.footprint(p, plan["face"], plan["cols"], r.alive_count, r.stats.spacing,
					r.stats.row_spacing, OrderFeedback.MOVE_COL)
			_range_preview(r, p, plan["face"], plan["cols"])
	elif _hover_valid and not selected.is_empty() and not _l_down and not _r_down and hover_own == null:
		var side := wall_side_under(_mouse)
		if hover_gate != null:
			for r in selected:
				if r.can_take_orders():
					feedback.arrow(r.center, hover_gate.outside_point(Fortress.WALL_T), OrderFeedback.ATTACK_COL)
		elif hover_enemy != null:
			for r in selected:
				if not r.can_take_orders():
					continue
				if hover_enemy.on_wall and not r.stats.is_ranged:
					continue   # in mischia non si arriva sulle mura
				# con Shift l'attacco parte dalla fine del percorso già ordinato
				var from := r.planned_end() if shift and r.has_plan() else r.center
				var tp := hover_enemy.nearest_point_to(from)
				var col := OrderFeedback.ATTACK_COL
				if r.uses_missiles() and Regiment._flat(from - hover_enemy.mid()).length() > r.missile_range():
					col = OrderFeedback.OUT_OF_RANGE_COL   # dovrà avvicinarsi prima di tirare
				feedback.arrow(from, tp, col)
		elif side >= 0:
			var nrm := battle.fortress.wall_normal(side)
			for plan: Dictionary in wall_plan(side, wall_point(_mouse)):
				var r: Regiment = plan["reg"]
				var p: Vector3 = plan["pos"]
				if not deploying:
					feedback.arrow(r.planned_end() if shift else r.center, battle.fortress.wall_foot(side, p),
							Color(OrderFeedback.MOVE_COL, 0.45), 0.7)
				feedback.height = Fortress.WALK_Y
				feedback.footprint(p, nrm, plan["cols"], r.alive_count, r.stats.spacing,
						r.stats.row_spacing, Color(OrderFeedback.MOVE_COL, 0.8))
				if r.uses_missiles():
					feedback.ring(p, r.stats.missile_range * Fortress.WALL_RANGE_BONUS, Color(OrderFeedback.RANGE_COL, 0.35), 0.5)
				feedback.height = 0.0
		else:
			for plan: Dictionary in group_move_plan(_hover_point, shift):
				var r: Regiment = plan["reg"]
				var tgt: Vector3 = plan["pos"]
				if deploying:
					tgt = clamp_to_zone(tgt)
				else:
					feedback.arrow(plan["from"], tgt, Color(OrderFeedback.MOVE_COL, 0.45), 0.7)
				feedback.footprint(tgt, plan["face"], r.cols, r.alive_count, r.stats.spacing,
						r.stats.row_spacing, Color(OrderFeedback.MOVE_COL, 0.55))
				_range_preview(r, tgt, plan["face"], r.cols)
	feedback.finish()


## Ordini già dati, in sequenza: l'ordine in corso e poi le tappe in coda.
## Movimento = freccia verde e sagoma (piena all'ultima tappa, tenue alle intermedie);
## attacco = freccia rossa verso il nemico, da cui riparte la tappa successiva.
func _draw_route(r: Regiment) -> void:
	var stops: Array[Dictionary] = []
	match r.state:
		Regiment.State.MOVING:
			stops.append({"pos": r.move_target, "face": r.move_facing, "run": r.running, "wall": r.move_wall_side, "cols": -1})
		Regiment.State.ATTACKING, Regiment.State.FIGHTING:
			if r.attack_target != null:
				stops.append({"attack": r.attack_target, "run": r.running})
		Regiment.State.BREACHING:
			if r.attack_gate != null:
				stops.append({"gate": r.attack_gate})
	if stops.is_empty():
		return
	stops.append_array(r.waypoints)
	var last_move := -1
	for k in stops.size():
		if not stops[k].has("attack") and not stops[k].has("gate"):
			last_move = k
	var from := r.center
	for k in stops.size():
		var w: Dictionary = stops[k]
		if w.has("gate"):
			var g: Fortress.Gate = w["gate"]
			var gp := g.outside_point(Fortress.WALL_T)
			feedback.arrow(from, gp, OrderFeedback.ATTACK_COL)
			from = gp
			continue
		if w.has("attack"):
			var t: Regiment = w["attack"]
			if not t.is_on_field():
				continue
			var tp := t.nearest_point_to(from)
			var col := OrderFeedback.ATTACK_COL
			if r.uses_missiles() and Regiment._flat(from - t.mid()).length() > r.missile_range():
				col = OrderFeedback.OUT_OF_RANGE_COL
			if Regiment._flat(tp - from).length() > 2.0:
				feedback.arrow(from, tp, col)
			from = t.mid()
			continue
		var col := OrderFeedback.RUN_COL if bool(w["run"]) else OrderFeedback.MOVE_COL
		var to: Vector3 = w["pos"]
		var side: int = w["wall"]
		var cols: int = w["cols"] if int(w["cols"]) > 0 else r.cols
		var face: Vector3 = w["face"]
		if side >= 0 and battle.fortress != null:
			var f := battle.fortress
			cols = f.wall_cols_for(r, side)
			face = f.wall_normal(side)
			to = f.wall_center_for(side, to, (cols - 1) * r.stats.spacing)
			if not (r.on_wall and k == 0):
				feedback.arrow(from, f.wall_foot(side, to), col)
			feedback.height = Fortress.WALK_Y
		else:
			feedback.arrow(from, to, col)
		feedback.footprint(to, face, cols, r.alive_count, r.stats.spacing, r.stats.row_spacing,
				Color(OrderFeedback.MOVE_COL, 0.45 if k == last_move else 0.22))
		feedback.height = 0.0
		from = to


## Per gli arcieri: cerchio di gittata tenue attorno alla posizione di arrivo.
func _range_preview(r: Regiment, front: Vector3, face: Vector3, cols: int) -> void:
	if not r.uses_missiles():
		return
	var n := clampi(cols, 1, maxi(r.alive_count, 1))
	var depth := (ceili(float(r.alive_count) / n) - 1) * r.stats.row_spacing
	feedback.ring(front - Regiment._flat(face).normalized() * depth * 0.5, r.stats.missile_range,
			Color(OrderFeedback.RANGE_COL, 0.35), 0.5)


# ---------------------------------------------------------------- utilità

func ground_point(screen: Vector2) -> Vector3:
	var o := rig.cam.project_ray_origin(screen)
	var d := rig.cam.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	if hit == null:
		return Vector3(o.x, 0.0, o.z)
	return hit


## Il reggimento sotto il cursore. Per chi sta sulle mura si usa il punto alla quota del camminamento.
func pick(screen: Vector2, which_team: int) -> Regiment:
	var gp := ground_point(screen)
	var wp := wall_point(screen) if battle.fortress != null else gp
	var best: Regiment = null
	var best_d := 2.5
	for r in battle.regiments:
		if r.team != which_team or not r.is_on_field():
			continue
		var p := wp if r.on_wall else gp
		if r.contains_point(p, 1.5):
			return r
		for i in r.count:
			if r.alive[i] == 1:
				var d := Regiment._flat(r.pos[i] - p).length()
				if d < best_d:
					best_d = d
					best = r
	return best


## Punto sotto il cursore alla quota del camminamento delle mura.
func wall_point(screen: Vector2) -> Vector3:
	var o := rig.cam.project_ray_origin(screen)
	var d := rig.cam.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, Fortress.WALK_Y).intersects_ray(o, d)
	if hit == null:
		return Vector3(o.x, Fortress.WALK_Y, o.z)
	return hit


## Il lato di mura sotto il cursore, se il giocatore difende e ha reparti che possono salirci.
func wall_side_under(screen: Vector2) -> int:
	var f := battle.fortress
	if f == null or f.defender_team != team:
		return -1
	var any := false
	for r in selected:
		if Fortress.can_man_walls(r):
			any = true
	if not any:
		return -1
	return f.wall_side_at(wall_point(screen))


func _pick_gate(p: Vector3) -> Fortress.Gate:
	if battle.fortress == null or battle.fortress.defender_team == team:
		return null
	return battle.fortress.gate_at(p, 4.0)


func clamp_to_zone(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, deploy_zone.position.x, deploy_zone.end.x),
		0.0,
		clampf(p.z, deploy_zone.position.y, deploy_zone.end.y))
