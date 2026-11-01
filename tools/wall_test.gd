extends Node
## Solo per test: mura (schieramento, salita, cambio di lato, immunità alla mischia)
## e tappe multiple con Shift + click destro. Salva screenshot in user://.
## Uso: godot --path . res://tools/wall_test.tscn
var fails := 0
var main: Node
var b: BattleManager
var c: PlayerController
var cam: Camera3D


func _ready() -> void:
	GameConfig.mode = "siege"
	GameConfig.player_attacks = false
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(0.3).timeout
	main.ui.toggle_help()
	b = main.battle
	c = main.controller
	cam = main.rig.cam
	var f := b.fortress
	_view(Vector3(-15, 0, -45), 75.0)
	# 1. schieramento: fanti a terra -> click destro sulle mura sud
	var inf := _find(0, "infantry", false)
	c.set_selection(_arr(inf))
	await _frames()
	_click_right(_wall_screen(0, -15.0))
	_check(inf.on_wall and inf.wall_side == 0, "schieramento: %s sulle mura sud" % inf.display_name)
	_check(absf(inf.pos[0].z - (-30.0)) < 2.0, "i soldati stanno sul camminamento (z=%.1f)" % inf.pos[0].z)
	await _shot("wall_deploy")
	# 2. in battaglia: arcieri dalle mura sud alle mura est (scendono, camminano, risalgono)
	b.start_battle()
	var arc := _find(0, "ranged", true)
	c.set_selection(_arr(arc))
	_view(Vector3(30, 0, -50), 95.0)
	await _frames()
	_move_mouse(_wall_screen(3, -60.0))
	await _frames()
	await _shot("wall_hover_east")
	_click_right(_wall_screen(3, -60.0))
	_check(arc.state == Regiment.State.MOVING and arc.move_wall_side == 3, "ordine verso le mura est")
	var t0 := b.battle_time
	while b.battle_time < t0 + 90.0 and not (arc.on_wall and arc.wall_side == 3 and arc.state == Regiment.State.IDLE):
		b._sim_step(0.03)
	_check(arc.on_wall and arc.wall_side == 3, "arrivati sulle mura est in %.0f s" % (b.battle_time - t0))
	# 3. la mischia non arriva sulle mura
	var enemy_inf := _find(1, "infantry", false)
	enemy_inf.order_attack(arc)
	_check(enemy_inf.attack_target != arc, "la fanteria nemica non può attaccare chi è sulle mura")
	# 4. tappe con Shift + click destro
	var cav := _find(0, "cavalry", false)
	c.set_selection(_arr(cav))
	_view(Vector3(0, 0, -75), 90.0)
	await _frames()
	var pa := Vector3(-35, 0, -60)
	var pb := Vector3(-35, 0, -95)
	var pc := Vector3(30, 0, -95)
	_click_right(cam.unproject_position(pa))
	_click_right(cam.unproject_position(pb), true)
	_click_right(cam.unproject_position(pc), true)
	_check(cav.state == Regiment.State.MOVING and cav.waypoints.size() == 2, "due tappe in coda (%d)" % cav.waypoints.size())
	await _frames()
	await _shot("waypoints")
	var passed_b := false
	t0 = b.battle_time
	while b.battle_time < t0 + 80.0 and cav.state != Regiment.State.IDLE:
		b._sim_step(0.03)
		if cav.center.distance_to(pb) < 6.0:
			passed_b = true
	_check(passed_b, "è passata dalla tappa intermedia")
	_check(cav.center.distance_to(pc) < 4.0, "arrivata all'ultima tappa (%.1f m)" % cav.center.distance_to(pc))
	# 5. un click destro normale cancella le tappe
	_click_right(cam.unproject_position(pa))
	_click_right(cam.unproject_position(pb), true)
	_click_right(cam.unproject_position(pc))
	_check(cav.waypoints.is_empty(), "click senza Shift cancella le tappe")
	# 6. attacco in coda: tappa, Shift+tappa, Shift+attacco, Shift+tappa
	var foe: Regiment = null
	for r in b.regiments:
		if r.team == 1 and r.is_on_field() and r.state != Regiment.State.ROUTING and not r.on_wall:
			foe = r
			break
	var p1 := Vector3(-30, 0, -95)
	var p2 := Vector3(30, 0, -95)
	var p3 := Vector3(0, 0, -100)
	_view(Vector3(0, 0, -80), 110.0)
	foe.teleport(Vector3(0, 0, -62), Vector3(0, 0, 1))   # bersaglio dentro le mura, in vista
	await _frames()
	_click_right(cam.unproject_position(p1))
	_click_right(cam.unproject_position(p2), true)
	_click_right(cam.unproject_position(foe.mid()), true)
	_click_right(cam.unproject_position(p3), true)
	var kinds := []
	for w in cav.waypoints:
		kinds.append("attacco" if w.has("attack") else "tappa")
	_check(cav.state == Regiment.State.MOVING and kinds == ["tappa", "attacco", "tappa"],
			"Shift sul nemico mette l'attacco in coda senza perdere le tappe (%s)" % [kinds])
	_move_mouse(cam.unproject_position(Vector3(-40, 0, -45)))
	await _frames()
	await _shot("queued_attack")
	# percorre le prime due tappe, poi attacca il bersaglio
	t0 = b.battle_time
	while b.battle_time < t0 + 90.0 and cav.attack_target != foe:
		b._sim_step(0.03)
		foe.morale = 100.0   # il bersaglio non deve fuggire prima che la cavalleria arrivi
	_check(cav.attack_target == foe and cav.waypoints.size() == 1, "dopo le tappe parte l'attacco, l'ultima tappa resta in coda")
	# il bersaglio viene eliminato: si prosegue verso l'ultima tappa
	for i in foe.count:
		foe.take_damage(i, 1e6, null)
	# (se nel frattempo è in mischia con un altro reparto, prima finisce quello scontro)
	t0 = b.battle_time
	while b.battle_time < t0 + 25.0 and cav.state != Regiment.State.MOVING:
		b._sim_step(0.03)
	_check(cav.state == Regiment.State.MOVING and cav.move_target.distance_to(p3) < 1.0, "bersaglio eliminato: riparte verso l'ultima tappa")
	# un attacco senza Shift sostituisce tutto, come prima
	var foe2: Regiment = null
	for r in b.regiments:
		if r.team == 1 and r.is_on_field() and r.state != Regiment.State.ROUTING and not r.on_wall:
			foe2 = r
			break
	cav.queue_move(p1, Vector3(0, 0, 1))
	foe2.teleport(Vector3(0, 0, -55), Vector3(0, 0, 1))
	await _frames()
	_click_right(cam.unproject_position(foe2.mid()))
	_check(cav.attack_target == foe2 and cav.waypoints.is_empty(), "attacco senza Shift: sostituisce il percorso")
	print("WALL TEST: %s" % ("OK" if fails == 0 else "%d FALLITI" % fails))
	get_tree().quit(fails)


func _find(team: int, role: String, wall: bool) -> Regiment:
	for r in b.regiments:
		if r.team == team and r.stats.role == role and r.on_wall == wall:
			return r
	return null


func _arr(r: Regiment) -> Array[Regiment]:
	var a: Array[Regiment] = [r]
	return a


func _wall_screen(side: int, along: float) -> Vector2:
	var p: Vector3
	if side == 0:
		p = Vector3(along, Fortress.WALK_Y, -30.0)
	else:
		p = Vector3(60.0, Fortress.WALK_Y, along)
	return cam.unproject_position(p)


func _view(at: Vector3, dist: float) -> void:
	main.rig.focus_on(at)
	main.rig._target_dist = dist
	main.rig.dist = dist
	main.rig._apply()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _move_mouse(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	Input.parse_input_event(mv)
	Input.flush_buffered_events()


func _click_right(p: Vector2, shift := false) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = p
		e.shift_pressed = shift
		Input.parse_input_event(e)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _shot(label: String) -> void:
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % label)
