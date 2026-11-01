class_name ProjectileSystem
extends Node3D
## Frecce balistiche vere: colpiscono chiunque incontrino, anche gli alleati in mischia.
## Disegnate tutte con un solo MultiMesh.
## Artiglieria: massi (catapulta, a parabola) e palle (cannone, tiro teso) che esplodono
## all'impatto colpendo tutti nel raggio, alleati compresi, e danneggiano le porte.

const G := 9.8
const MAX_ARROWS := 4000
const SHIELD_BLOCK := 0.35

var battle: BattleManager
var a_pos := PackedVector3Array()
var a_vel := PackedVector3Array()
var a_origin := PackedVector3Array()
var a_owner := PackedInt32Array()
var a_team := PackedInt32Array()     ## squadra di chi ha tirato
var a_dmg := PackedFloat32Array()
var a_ap := PackedFloat32Array()
var _mm: MultiMesh

const MAX_SHELLS := 200
const MAX_BLASTS := 64
const BLAST_TIME := 0.7
## colpi d'artiglieria in volo: {"pos","vel","aim_y","team","owner","dmg","ap","splash","gate_dmg","big"}
var shells: Array[Dictionary] = []
var _blasts: Array[Dictionary] = []   ## {"pos", "t", "r"}
var _shell_mm: MultiMesh
var _blast_mm: MultiMesh


func setup(b: BattleManager) -> void:
	battle = b
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.18, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX_ARROWS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)
	var ball := SphereMesh.new()
	ball.radius = 0.45
	ball.height = 0.9
	ball.radial_segments = 8
	ball.rings = 4
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.18, 0.17, 0.16)
	ball.material = bmat
	_shell_mm = MultiMesh.new()
	_shell_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shell_mm.mesh = ball
	_shell_mm.instance_count = MAX_SHELLS
	_shell_mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _shell_mm
	add_child(smi)
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 12
	puff.rings = 6
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material = pmat
	_blast_mm = MultiMesh.new()
	_blast_mm.transform_format = MultiMesh.TRANSFORM_3D
	_blast_mm.use_colors = true
	_blast_mm.mesh = puff
	_blast_mm.instance_count = MAX_BLASTS
	_blast_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = _blast_mm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


func fire_tick(dt: float) -> void:
	for r in battle.regiments:
		if not r.stats.is_ranged or r.ammo <= 0 or not r.is_on_field() or r.in_melee:
			continue
		if r.state == Regiment.State.ROUTING or r.state == Regiment.State.MOVING:
			continue
		var gate: Fortress.Gate = null
		var t: Regiment = null
		if r.stats.is_artillery:
			if r.is_moving():
				continue   # le macchine tirano solo da ferme
			gate = r.bombarding_gate()
		if gate == null:
			t = r.missile_target()
			if t == null:
				continue
			var d := r.mid().distance_to(t.mid())
			if d > r.missile_range() or d < r.stats.min_range:
				continue
		var timers := r.timer   # copia locale: vedi nota in combat_system.gd
		var al := r.alive
		var kn := r.knock
		for i in r.count:
			if al[i] == 0 or kn[i] > 0.0:
				continue
			timers[i] -= dt
			if timers[i] <= 0.0:
				timers[i] = r.stats.reload_time * randf_range(0.85, 1.15)
				if r.stats.is_artillery:
					_fire_shell(r, i, t, gate)
				else:
					_fire(r, i, t)
				r.mark_action(i, UnitVisual.SHOOT)
				r.ammo -= 1
				if r.ammo <= 0:
					break
		r.timer = timers


func _fire(r: Regiment, i: int, t: Regiment) -> void:
	var from := r.pos[i] + Vector3(0.0, r.base_y() + 1.6, 0.0)
	_launch(from, from, t, r.stats.missile_damage, r.stats.missile_ap, r.reg_id, r.team)


func _fire_shell(r: Regiment, i: int, t: Regiment, gate: Fortress.Gate) -> void:
	if shells.size() >= MAX_SHELLS:
		return
	var high := r.stats.high_arc
	var start := r.pos[i] + Vector3(0.0, r.base_y() + (4.0 if high else 1.3), 0.0) + r.facing * 1.5
	var tp: Vector3
	var aim_y := 0.0
	if gate != null:
		tp = gate.center + Vector3(-gate.normal.z, 0, gate.normal.x) * randf_range(-0.4, 0.4) * gate.width
		aim_y = 2.5
	else:
		var j := t.random_alive()
		if j < 0:
			return
		tp = t.pos[j]
		aim_y = t.base_y() + 0.3
	var flat := Vector2(tp.x - start.x, tp.z - start.z).length()
	var spread := (2.0 + flat * 0.03) if high else (1.0 + flat * 0.015)
	if gate != null:
		spread *= 0.6
	var ang := randf() * TAU
	var rad := sqrt(randf()) * spread
	tp += Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
	tp.y = aim_y
	var tf := (2.6 + flat / 110.0) if high else (0.45 + flat / 170.0)
	var v := (tp - start) / tf
	v.y += 0.5 * G * tf
	shells.append({"pos": start, "vel": v, "aim_y": aim_y, "team": r.team, "owner": r.reg_id,
			"dmg": r.stats.missile_damage, "ap": r.stats.missile_ap, "splash": r.stats.splash_radius,
			"gate_dmg": r.stats.gate_damage, "big": high})


## Freccia da un punto qualsiasi (es. una torre). owner_id = -1: nessun reggimento la rivendica.
func fire_from(origin: Vector3, t: Regiment, dmg: float, ap: float, owner_id: int, team: int) -> void:
	_launch(origin, origin, t, dmg, ap, owner_id, team)


func _launch(start: Vector3, origin: Vector3, t: Regiment, dmg: float, ap: float, owner_id: int, team: int) -> void:
	if a_pos.size() >= MAX_ARROWS:
		return
	var j := t.random_alive()
	if j < 0:
		return
	var tp := t.pos[j]
	var flat := Vector2(tp.x - start.x, tp.z - start.z).length()
	# la precisione cala con la distanza; i bersagli grandi sono più facili
	var spread := (0.4 + flat * 0.03) / (0.6 + t.stats.radius)
	var ang := randf() * TAU
	var rad := sqrt(randf()) * spread
	tp += Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
	tp.y = t.base_y() + 0.9
	var tf := 0.9 + flat / 40.0
	var v := (tp - start) / tf
	v.y += 0.5 * G * tf
	a_pos.append(start)
	a_vel.append(v)
	a_origin.append(origin)
	a_owner.append(owner_id)
	a_team.append(team)
	a_dmg.append(dmg)
	a_ap.append(ap)


func update(dt: float) -> void:
	var k := 0
	while k < a_pos.size():
		var v := a_vel[k]
		v.y -= G * dt
		var p := a_pos[k] + v * dt
		a_vel[k] = v
		a_pos[k] = p
		var done := false
		if v.y < 0.0 and p.y < Fortress.WALK_Y + 4.5:
			done = _check_hit(k, p)
		if not done and p.y <= 0.0:
			done = true
		if done:
			_remove(k)
		else:
			k += 1
	_update_shells(dt)


func _update_shells(dt: float) -> void:
	var k := 0
	while k < shells.size():
		var sh: Dictionary = shells[k]
		var v: Vector3 = sh["vel"]
		v.y -= G * dt
		var p: Vector3 = sh["pos"] + v * dt
		sh["vel"] = v
		sh["pos"] = p
		if (v.y < 0.0 and p.y <= float(sh["aim_y"])) or p.y <= 0.0:
			_explode(sh, p)
			shells.remove_at(k)
		else:
			k += 1
	for b in _blasts:
		b["t"] = float(b["t"]) + dt
	while not _blasts.is_empty() and float(_blasts[0]["t"]) >= BLAST_TIME:
		_blasts.pop_front()


func _explode(sh: Dictionary, p: Vector3) -> void:
	var splash := float(sh["splash"])
	var team := int(sh["team"])
	var owner_id := int(sh["owner"])
	var owner: Regiment = battle.regiments[owner_id] if owner_id >= 0 else null
	var fp := Vector3(p.x, 0.0, p.z)
	var s2 := splash * splash
	for o in battle.regiments:
		if not o.is_on_field():
			continue
		if absf(o.base_y() - p.y) > 3.5:
			continue   # un'esplosione a terra non tocca chi sta sulle mura, e viceversa
		if o.mid().distance_to(fp) > o.bound_radius() + splash:
			continue
		var opos := o.pos
		var oal := o.alive
		for j in o.count:
			if oal[j] == 0:
				continue
			var op := opos[j]
			var dx := op.x - p.x
			var dz := op.z - p.z
			var d2 := dx * dx + dz * dz
			if d2 > s2:
				continue
			var f := 1.0 - 0.6 * sqrt(d2) / splash
			var dmg := float(sh["dmg"]) * f * (1.0 - o.stats.armor * randf_range(0.5, 1.0) / 100.0) + float(sh["ap"]) * f
			o.take_damage(j, dmg, owner if owner != null and owner.team != o.team else null, false)
			if not o.stats.is_large or randf() < 0.25:
				var away := Vector3(dx, 0.0, dz).normalized() if d2 > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
				o.apply_knock(j, away * 6.0 * f, 1.2)
	if battle.fortress != null:
		var f := battle.fortress
		for g in f.gates:
			if g.breakable and not g.destroyed and f.dist_to_gate(g, fp) <= splash * 0.6 + 1.0:
				f.damage_gate(g, float(sh["gate_dmg"]))
				break
	if _blasts.size() >= MAX_BLASTS:
		_blasts.pop_front()
	_blasts.append({"pos": p, "t": 0.0, "r": splash})


func _check_hit(k: int, p: Vector3) -> bool:
	var fp := Vector3(p.x, 0.0, p.z)
	for o in battle.regiments:
		if not o.is_on_field():
			continue
		# fuoco amico solo su chi è in mischia: gli altri alleati non vengono colpiti
		if o.team == a_team[k] and not o.in_melee:
			continue
		var oy := o.base_y()
		if p.y > oy + o.stats.model_height or p.y < oy - 0.3:
			continue
		if o.mid().distance_to(fp) > o.bound_radius() + 2.0:
			continue
		var rr := o.stats.radius + 0.15
		var rr2 := rr * rr
		var opos := o.pos
		var oal := o.alive
		for j in o.count:
			if oal[j] == 0:
				continue
			var op := opos[j]
			var dx := op.x - p.x
			var dz := op.z - p.z
			if dx * dx + dz * dz < rr2:
				var owner: Regiment = battle.regiments[a_owner[k]] if a_owner[k] >= 0 else null
				if o.stats.has_shield and o.side_of(a_origin[k]) == 0 and randf() < SHIELD_BLOCK:
					return true
				# sulle mura i merli coprono da chi tira dal basso
				if o.on_wall and a_origin[k].y < oy and randf() < Fortress.WALL_COVER:
					return true
				var dmg := a_dmg[k] * (1.0 - o.stats.armor * randf_range(0.5, 1.0) / 100.0) + a_ap[k]
				o.take_damage(j, dmg, owner if owner != null and owner.team != o.team else null, false)
				return true
	return false


func _remove(k: int) -> void:
	var last := a_pos.size() - 1
	if k != last:
		a_pos[k] = a_pos[last]
		a_vel[k] = a_vel[last]
		a_origin[k] = a_origin[last]
		a_owner[k] = a_owner[last]
		a_team[k] = a_team[last]
		a_dmg[k] = a_dmg[last]
		a_ap[k] = a_ap[last]
	a_pos.resize(last)
	a_vel.resize(last)
	a_origin.resize(last)
	a_owner.resize(last)
	a_team.resize(last)
	a_dmg.resize(last)
	a_ap.resize(last)


func update_visuals() -> void:
	var n := mini(a_pos.size(), MAX_ARROWS)
	for k in n:
		var v := a_vel[k]
		var b := Basis.looking_at(v.normalized(), Vector3.UP) if absf(v.normalized().y) < 0.99 else Basis()
		_mm.set_instance_transform(k, Transform3D(b, a_pos[k]))
	_mm.visible_instance_count = n
	var ns := mini(shells.size(), MAX_SHELLS)
	for k in ns:
		var sh: Dictionary = shells[k]
		var sc := 1.0 if sh["big"] else 0.6
		_shell_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * sc), sh["pos"]))
	_shell_mm.visible_instance_count = ns
	var nb := mini(_blasts.size(), MAX_BLASTS)
	for k in nb:
		var bl: Dictionary = _blasts[k]
		var u := float(bl["t"]) / BLAST_TIME
		var rad := float(bl["r"]) * lerpf(0.35, 1.0, sqrt(u))
		var basis := Basis().scaled(Vector3(rad, rad * 0.6, rad))
		_blast_mm.set_instance_transform(k, Transform3D(basis, bl["pos"] + Vector3(0, rad * 0.3, 0)))
		var col := Color(1.0, 0.6, 0.2).lerp(Color(0.45, 0.4, 0.35), minf(1.0, u * 2.0))
		col.a = 0.85 * (1.0 - u)
		_blast_mm.set_instance_color(k, col)
	_blast_mm.visible_instance_count = nb
