extends Node3D
## Costruisce la scena di battaglia: ambiente, terreno, eventuale fortezza, eserciti,
## camera, comandi e interfaccia. Gli eserciti e il tipo di battaglia arrivano da GameConfig
## (scelti nella scena di preparazione, army_select.tscn).
##
## Il giocatore è sempre la squadra 0 (blu); l'IA è la squadra 1 (rossa).
##
## Avvio automatico IA contro IA, senza grafica:
##   godot --headless --path . --fixed-fps 60 res://main.tscn -- --autotest          (campale)
##   godot --headless --path . --fixed-fps 60 res://main.tscn -- --autotest-siege    (assedio)

const PLAYER_COLOR := Color(0.25, 0.45, 0.95)
const ENEMY_COLOR := Color(0.85, 0.22, 0.18)
const ROMAN := ["", " I", " II", " III", " IV", " V", " VI", " VII", " VIII"]
const FIELD_ZONE := Rect2(-110.0, 35.0, 220.0, 95.0)
const SIEGE_ATTACK_ZONE := Rect2(-110.0, 8.0, 220.0, 112.0)

var battle: BattleManager
var rig: CameraRig
var controller: PlayerController
var ui: BattleUI
var autotest := false
var _deploy_zone: MeshInstance3D
var _report_acc := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest") or args.has("--autotest-siege")
	if args.has("--autotest-siege"):
		GameConfig.mode = "siege"
		GameConfig.player_attacks = not args.has("--defend")
	elif args.has("--autotest"):
		GameConfig.mode = "field"
	if autotest and args.has("--artillery"):
		GameConfig.player_army.append_array(["catapult", "cannon"])
		GameConfig.enemy_army.append_array(["catapult", "cannon"])
	for a in args:
		if a.begins_with("--fortress="):
			GameConfig.fortress_path = a.substr(11)

	_build_world()
	battle = BattleManager.new()
	battle.name = "Battle"
	add_child(battle)

	var zone := FIELD_ZONE
	var focus := Vector3(0, 0, 55)
	if GameConfig.is_siege():
		var defender := 1 if GameConfig.player_attacks else 0
		var fort := battle.setup_siege(defender, GameConfig.fortress_layout())
		var att_ids := GameConfig.player_army if GameConfig.player_attacks else GameConfig.enemy_army
		var def_ids := GameConfig.enemy_army if GameConfig.player_attacks else GameConfig.player_army
		var att_team := 1 - defender
		_deploy_army(att_team, att_ids, 50.0, Vector3(0, 0, -1), _color(att_team))
		_deploy_defenders(defender, def_ids, _color(defender), fort)
		zone = SIEGE_ATTACK_ZONE if GameConfig.player_attacks else fort.interior_rect(4.0)
		focus = Vector3(0, 0, 40) if GameConfig.player_attacks else Vector3(0, 0, -55)
	else:
		_deploy_army(0, GameConfig.player_army, 70.0, Vector3(0, 0, -1), PLAYER_COLOR)
		_deploy_army(1, GameConfig.enemy_army, -70.0, Vector3(0, 0, 1), ENEMY_COLOR)
	battle.add_ai(1)
	_build_deploy_zone(zone)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.focus_on(focus)

	ui = BattleUI.new()
	controller = PlayerController.new()
	controller.name = "PlayerController"
	controller.deploy_zone = zone
	add_child(controller)
	add_child(ui)
	controller.setup(battle, rig, ui)
	ui.setup(battle, controller)
	battle.battle_started.connect(func() -> void: _deploy_zone.visible = false)

	if autotest:
		battle.add_ai(0)
		battle.time_scale = 3.0
		battle.start_battle()
		battle.battle_ended.connect(_on_autotest_end)
		print("AUTOTEST %s: %d reggimenti, %d soldati" % [
			"ASSEDIO" if GameConfig.is_siege() else "CAMPALE", battle.regiments.size(), battle.soldier_count()])


func _color(team: int) -> Color:
	return PLAYER_COLOR if team == 0 else ENEMY_COLOR


func _process(delta: float) -> void:
	if not autotest:
		return
	_report_acc += delta * battle.time_scale
	if _report_acc >= 20.0:
		_report_acc = 0.0
		var a := battle.team_summary(0)
		var b := battle.team_summary(1)
		var extra := ""
		if battle.fortress != null:
			var f := battle.fortress
			var gs := PackedStringArray()
			for g in f.gates:
				if g.breakable:
					gs.append("%s %d" % [g.name, int(g.hp)])
			extra = "  conquista %d%% (%d vs %d)  porte: %s" % [int(f.capture_progress * 100), f.capture_counts.x, f.capture_counts.y, ", ".join(gs)]
		var states := PackedStringArray()
		for r in battle.regiments:
			states.append("%s:%s:%d" % [r.display_name, Regiment.STATE_NAMES[r.state], int(r.morale)])
		print("t=%4ds  blu %d/%d  rossi %d/%d  tick %.2f ms%s" % [
			int(battle.battle_time), a["alive"], a["start"], b["alive"], b["start"],
			battle.perf_tick_usec / 1000.0, extra])
		print("    " + ", ".join(states))
	if battle.battle_time > 1500.0:
		print("AUTOTEST: tempo massimo raggiunto")
		get_tree().quit(2)


func _on_autotest_end(winner: int) -> void:
	var a := battle.team_summary(0)
	var b := battle.team_summary(1)
	print("AUTOTEST FINE: vince %s dopo %d s — %s" % ["blu" if winner == 0 else "rosso", int(battle.battle_time), battle.end_reason])
	print("  blu:   %s" % a)
	print("  rossi: %s" % b)
	for r in battle.regiments:
		print("  [%s] %-14s vivi %3d/%3d uccisioni %3d stato %-16s rotte %d  danni subiti: mischia %5d tiro %5d" % [
			"B" if r.team == 0 else "R", r.display_name, r.alive_count, r.count, r.kills,
			Regiment.STATE_NAMES[r.state], r.rout_count, int(r.taken_melee), int(r.taken_missile)])
	get_tree().quit(0)


# ---------------------------------------------------------------- mondo

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.4, 0.72)
	sky_mat.sky_horizon_color = Color(0.62, 0.7, 0.78)
	sky_mat.ground_horizon_color = Color(0.35, 0.4, 0.32)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.18)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.68, 0.75)
	env.fog_density = 0.0006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)

	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.13, 0.2, 0.08))
	ramp.set_color(1, Color(0.24, 0.32, 0.13))
	tex.color_ramp = ramp
	var gmat := StandardMaterial3D.new()
	gmat.albedo_texture = tex
	gmat.uv1_scale = Vector3(14, 14, 1)
	gmat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(440, 440)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = gmat
	add_child(ground)


func _build_deploy_zone(z: Rect2) -> void:
	var zone_mesh := PlaneMesh.new()
	zone_mesh.size = z.size
	var zmat := StandardMaterial3D.new()
	zmat.albedo_color = Color(0.3, 0.5, 1.0, 0.18)
	zmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_deploy_zone = MeshInstance3D.new()
	_deploy_zone.mesh = zone_mesh
	_deploy_zone.material_override = zmat
	_deploy_zone.position = Vector3(z.get_center().x, 0.05, z.get_center().y)
	add_child(_deploy_zone)


# ---------------------------------------------------------------- eserciti

func _namer(ids: Array[String]) -> Callable:
	var totals := {}
	for id in ids:
		totals[id] = int(totals.get(id, 0)) + 1
	var seen := {}
	return func(s: UnitStats) -> String:
		seen[s.id] = int(seen.get(s.id, 0)) + 1
		if int(totals[s.id]) > 1:
			return s.display_name + ROMAN[mini(int(seen[s.id]), ROMAN.size() - 1)]
		return s.display_name


## Schieramento in campo aperto: fanteria in prima linea, tiratori dietro,
## cavalleria sui fianchi, generale in fondo.
func _deploy_army(team: int, ids: Array[String], base_z: float, face: Vector3, color: Color) -> void:
	var front: Array[UnitStats] = []
	var ranged: Array[UnitStats] = []
	var flank: Array[UnitStats] = []
	var general: Array[UnitStats] = []
	var artillery: Array[UnitStats] = []
	for id in ids:
		var s := GameConfig.stats(id)
		match s.role:
			"ranged":
				ranged.append(s)
			"artillery":
				artillery.append(s)
			"cavalry":
				flank.append(s)
			"general":
				general.append(s)
			_:
				front.append(s)
	var namer := _namer(ids)
	var rv := Vector3(-face.z, 0.0, face.x)
	var base := Vector3(0.0, 0.0, base_z)
	var gap := 6.0
	# linee troppo lunghe vanno su due file
	var rows: Array = [front] if _line_width(front, gap) < 190.0 else [front.slice(0, ceili(front.size() / 2.0)), front.slice(ceili(front.size() / 2.0))]
	var line_w := 0.0
	for row_i in rows.size():
		var row: Array[UnitStats] = []
		row.assign(rows[row_i])
		var w_row := _line_width(row, gap)
		line_w = maxf(line_w, w_row)
		var x := -w_row * 0.5
		for s in row:
			var w := (s.default_cols - 1) * s.spacing
			battle.add_regiment(s, team, namer.call(s), base - face * (row_i * 14.0) + rv * (x + w * 0.5), face, color)
			x += w + gap
	var back := 16.0 + (rows.size() - 1) * 14.0
	var rw := _line_width(ranged, gap * 2.0)
	var x2 := -rw * 0.5
	for s in ranged:
		var w := (s.default_cols - 1) * s.spacing
		battle.add_regiment(s, team, namer.call(s), base - face * back + rv * (x2 + w * 0.5), face, color)
		x2 += w + gap * 2.0
	for k in flank.size():
		var s := flank[k]
		var w := (s.default_cols - 1) * s.spacing
		var sgn := -1.0 if k % 2 == 0 else 1.0
		var off := line_w * 0.5 + 12.0 + w * 0.5 + int(k / 2) * (w + gap)
		off = minf(off, 140.0)
		battle.add_regiment(s, team, namer.call(s), base - face * (4.0 + int(k / 2) * 8.0) + rv * sgn * off, face, color)
	var aw := _line_width(artillery, gap * 3.0)
	var x3 := -aw * 0.5
	for s in artillery:
		var w := (s.default_cols - 1) * s.spacing
		battle.add_regiment(s, team, namer.call(s), base - face * (back + 18.0) + rv * (x3 + w * 0.5), face, color)
		x3 += w + gap * 3.0
	var gback := back + (34.0 if not artillery.is_empty() else 16.0)
	for s in general:
		battle.add_regiment(s, team, namer.call(s), base - face * gback, face, color)


## Schieramento dei difensori dentro una fortezza qualsiasi:
## - fanteria e mostri dietro ogni porta abbattibile (prima quelle più a sud), poi attorno al punto;
## - arcieri sulle mura, prima sui lati rivolti a sud, poi a terra vicino al punto;
## - cavalleria di riserva dietro il punto, artiglieria accanto al punto, generale al centro.
func _deploy_defenders(team: int, ids: Array[String], color: Color, fort: Fortress) -> void:
	var lay := fort.layout
	var cap := fort.capture_center
	var south := Vector3(0, 0, 1)
	var gates: Array[Fortress.Gate] = []
	for g in fort.gates:
		if g.breakable:
			gates.append(g)
	gates.sort_custom(func(a: Fortress.Gate, b: Fortress.Gate) -> bool: return a.center.z > b.center.z)
	var inf_spots: Array = []
	for g in gates:
		inf_spots.append([g.inside_point(12.0), g.normal])
	for k in 8:
		var a := PI * 0.5 + TAU * k / 8.0
		inf_spots.append([cap + Vector3(cos(a), 0, sin(a)) * 22.0, south])
	# lati di mura: prima quelli rivolti a sud, poi i più lunghi; i lati lunghi ospitano due reparti
	var wall_spots: Array = []
	var order_sides: Array[int] = []
	for i in fort.sides.size():
		if fort.side_length(i) >= 24.0:
			order_sides.append(i)
	order_sides.sort_custom(func(a: int, b: int) -> bool:
		var za := fort.wall_normal(a).z
		var zb := fort.wall_normal(b).z
		if absf(za - zb) > 0.1:
			return za > zb
		return fort.side_length(a) > fort.side_length(b))
	for i in order_sides:
		var sd: Dictionary = fort.sides[i]
		var length := float(sd["len"])
		var ts: Array = [length * 0.25, length * 0.75] if length >= 90.0 else [length * 0.5]
		for t in ts:
			wall_spots.append([i, sd["a"] + sd["dir"] * t])
	var namer := _namer(ids)
	var order: Array[String] = []
	order.assign(ids)
	order.sort_custom(func(a: String, b: String) -> bool:
		return GameConfig.stats(a).role == "monster" and GameConfig.stats(b).role != "monster")
	var used := {"inf": 0, "wall": 0, "ground": 0, "cav": 0, "art": 0}
	for id in order:
		var s := GameConfig.stats(id)
		var at := cap
		var face := south
		var wall_spot: Array = []
		match s.role:
			"ranged":
				if used["wall"] < wall_spots.size():
					wall_spot = wall_spots[used["wall"]]
					used["wall"] += 1
					at = wall_spot[1]
				else:
					at = cap + Vector3(-30.0 + used["ground"] * 20.0, 0, 8.0)
					used["ground"] += 1
			"cavalry":
				at = cap + Vector3(-26.0 + used["cav"] * 26.0, 0, -18.0)
				used["cav"] += 1
			"artillery":
				if s.wall_mount and used["wall"] < wall_spots.size():
					# i cannoni sulle mura: tirano lontano dall'alto, al riparo dei merli
					wall_spot = wall_spots[used["wall"]]
					used["wall"] += 1
					at = wall_spot[1]
				else:
					at = cap + Vector3(-18.0 + used["art"] * 36.0, 0, 6.0)
					used["art"] += 1
			"general":
				at = cap + Vector3(0, 0, -6.0)
			_:
				var k: int = used["inf"]
				used["inf"] += 1
				if k < inf_spots.size():
					at = inf_spots[k][0]
					face = inf_spots[k][1]
				else:
					at = cap + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
		if wall_spot.is_empty():
			at = lay.nearest_inside(at, 4.0)
		var reg := battle.add_regiment(s, team, namer.call(s), at, face, color)
		if not wall_spot.is_empty():
			reg.teleport_to_wall(wall_spot[0], wall_spot[1])


func _line_width(list: Array[UnitStats], gap: float) -> float:
	var w := 0.0
	for s in list:
		w += (s.default_cols - 1) * s.spacing
	return w + gap * maxi(list.size() - 1, 0)
