class_name SiegeAI
extends AIGeneral
## IA per l'assedio.
## Attaccante: un reggimento per porta la abbatte, gli altri aspettano fuori; appena una porta
## cade, tutti entrano: combattono i difensori che incontrano e occupano il punto di vittoria.
## Difensore: ogni reggimento ha una postazione (quella di schieramento). Finché le porte
## reggono resta lì e gli arcieri tirano oltre le mura; quando entra qualcuno, la fanteria
## lo affronta e poi torna in postazione. I difensori non escono dalle mura.

var _station := {}   ## reg_id -> {"pos": Vector3, "face": Vector3}
var _breach_time := -1.0   ## quando è caduta la prima porta
var _assault_go := false   ## gli attaccanti radunati entrano tutti insieme
const RALLY_TIMEOUT := 30.0


func think() -> void:
	var f := battle.fortress
	var mine: Array[Regiment] = []
	var foes: Array[Regiment] = []
	for r in battle.regiments:
		if not r.is_on_field() or r.state == Regiment.State.ROUTING:
			continue
		if r.team == team:
			mine.append(r)
		else:
			foes.append(r)
	if mine.is_empty():
		return
	if team == f.attacker_team:
		_attack_plan(mine, foes, f)
	else:
		_defend_plan(mine, foes, f)


# ---------------------------------------------------------------- attacco

func _attack_plan(mine: Array[Regiment], foes: Array[Regiment], f: Fortress) -> void:
	var open := f.open_gates()
	var closed := f.closed_breakable_gates()
	var c := _army_center(mine)
	# si arriva già al punto di vittoria? altrimenti si abbattono le porte chiuse che si
	# raggiungono: con più cinte di mura, prima quelle esterne e poi quelle interne
	var reach := f.can_reach(c, f.capture_center, team)
	var targets: Array[Fortress.Gate] = []
	if not reach:
		for g in closed:
			if f.can_reach(c, g.outside_point(5.0), team):
				targets.append(g)
	# 1. una squadra d'assalto per ogni porta da abbattere (prima i mostri, poi la fanteria)
	var busy := {}
	for g in closed:
		var holder: Regiment = null
		for r in mine:
			if r.attack_gate == g and not r.stats.is_artillery \
					and (r.state == Regiment.State.BREACHING or r.state == Regiment.State.FIGHTING):
				holder = r
		if holder == null and targets.has(g):
			holder = _best_breacher(mine, g, busy)
			if holder != null:
				holder.order_breach(g)
		if holder != null:
			busy[holder] = true
	# 2. porta abbattuta: prima ci si raduna davanti alla breccia, poi si entra insieme
	var rally := Vector3.ZERO
	var breach: Fortress.Gate = null
	if not open.is_empty():
		breach = _nearest_gate(open, c)
		rally = breach.outside_point(26.0)
		if _breach_time < 0.0:
			_breach_time = battle.battle_time
		if not _assault_go:
			var melee := 0
			var ready := 0
			for r in mine:
				if busy.has(r) or r.stats.is_ranged:
					continue
				melee += 1
				if r.mid().distance_to(rally) < 35.0:
					ready += 1
			_assault_go = ready >= int(ceil(melee * 0.6)) or battle.battle_time - _breach_time > RALLY_TIMEOUT
	# 3. tutti gli altri
	var k := 0
	for r in mine:
		if busy.has(r) or r.state == Regiment.State.FIGHTING:
			continue
		if r.stats.is_artillery:
			_siege_artillery(r, foes, f, targets)
			continue
		if r.stats.role == "ranged" and r.uses_missiles():
			_siege_archer(r, foes, f, open, closed)
			continue
		if r.stats.is_general and r.hp_total < r.start_hp_total * 0.5:
			continue
		var near := _nearest_reachable(r, foes, 30.0, f)
		if near != null:
			_attack(r, near, true)
			continue
		if breach != null and not _assault_go:
			var side := Vector3(-breach.normal.z, 0, breach.normal.x) * ((k % 5) - 2) * 12.0
			k += 1
			var spot := rally + side + breach.normal * float(int(k / 5)) * 12.0
			if r.mid().distance_to(spot) > 10.0 and (r.state != Regiment.State.MOVING or r.move_target.distance_to(spot) > 10.0):
				r.order_move(spot, -breach.normal, true)
			continue
		if reach:
			# la strada è aperta: dentro, verso il nemico più vicino o il punto di vittoria
			var t := _nearest_reachable(r, foes, 70.0, f)
			if t != null:
				_attack(r, t, true)
			else:
				var spot := f.capture_center + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				if r.state != Regiment.State.MOVING or r.move_target.distance_to(f.capture_center) > 12.0:
					r.order_move(spot, Vector3(0, 0, -1), r.mid().distance_to(f.capture_center) < 70.0)
		elif not targets.is_empty():
			# in attesa davanti alle porte da abbattere, in fila e un po' scostati, pronti a entrare
			var g: Fortress.Gate = targets[k % targets.size()]
			var side := Vector3(-g.normal.z, 0, g.normal.x) * (((k / targets.size()) % 3) - 1) * 18.0
			var back := 30.0 if r.stats.role != "cavalry" else 50.0
			var wait := g.outside_point(back) + side
			k += 1
			if r.mid().distance_to(wait) > 10.0 and r.state != Regiment.State.MOVING:
				r.order_move(wait, -g.normal)


## Artiglieria che attacca: bombarda la porta da abbattere più vicina; se non ce ne sono,
## tira sui reparti nemici a tiro (soprattutto quelli sulle mura e gli arcieri).
func _siege_artillery(r: Regiment, foes: Array[Regiment], f: Fortress, targets: Array[Fortress.Gate]) -> void:
	if not r.uses_missiles():
		return
	if not targets.is_empty():
		var g := _nearest_gate(targets, r.mid())
		if r.attack_gate != g:
			r.order_breach(g)
		return
	var best: Regiment = null
	var best_s := -1e9
	for t in foes:
		var d := r.mid().distance_to(t.mid())
		if d > r.missile_range() * 1.05 or d < r.stats.min_range:
			continue
		var s := -d / 80.0 + arrow_value(r, t) + (-2.0 if t.in_melee else 0.5)
		if t.on_wall or t.stats.is_ranged:
			s += 0.8
		if s > best_s:
			best_s = s
			best = t
	if best != null:
		_attack(r, best, false)


func _army_center(list: Array[Regiment]) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for r in list:
		if r.stats.is_ranged or r.stats.is_general:
			continue
		c += r.mid()
		n += 1
	return c / n if n > 0 else _centroid(list)


func _nearest_gate(list: Array[Fortress.Gate], p: Vector3) -> Fortress.Gate:
	var best: Fortress.Gate = null
	var bd := 1e20
	for g in list:
		var d := p.distance_to(g.center)
		if d < bd:
			bd = d
			best = g
	return best


func _best_breacher(mine: Array[Regiment], g: Fortress.Gate, busy: Dictionary) -> Regiment:
	var best: Regiment = null
	var best_s := -1e9
	for r in mine:
		if busy.has(r) or r.stats.is_general or r.stats.is_ranged or r.stats.role == "cavalry":
			continue
		if r.attack_gate != null and not r.attack_gate.destroyed and r.attack_gate != g:
			continue
		var s := r.hp_total / 100.0 - r.mid().distance_to(g.center) / 20.0
		if r.stats.role == "monster":
			s += 30.0
		if r.morale < 30.0:
			s -= 50.0
		if s > best_s:
			best_s = s
			best = r
	return best


func _siege_archer(r: Regiment, foes: Array[Regiment], f: Fortress, open: Array[Fortress.Gate], closed: Array[Fortress.Gate]) -> void:
	var best: Regiment = null
	var best_s := -1e9
	for t in foes:
		var d := r.mid().distance_to(t.mid())
		if d > r.stats.missile_range * 1.05:
			continue
		var s := -d / 60.0 + arrow_value(r, t) + (-1.5 if t.in_melee else 0.8)
		if s > best_s:
			best_s = s
			best = t
	if best != null:
		_attack(r, best, false)
		return
	# niente a tiro: avvicinati alla fortezza (davanti alla porta più utile)
	var g: Fortress.Gate = open[0] if not open.is_empty() else (closed[0] if not closed.is_empty() else null)
	if g != null:
		var spot := g.outside_point(45.0) + Vector3(randf_range(-20, 20), 0, 0)
		if r.state != Regiment.State.MOVING and r.mid().distance_to(spot) > 20.0:
			r.order_move(spot, -g.normal)


## Il nemico più vicino che si può raggiungere: stesso lato delle mura, o c'è una porta aperta.
func _nearest_reachable(r: Regiment, foes: Array[Regiment], max_d: float, f: Fortress) -> Regiment:
	var any_open := not f.open_gates().is_empty()
	var me_in := f.inside(r.mid())
	var best: Regiment = null
	var bd := max_d
	for t in foes:
		if t.on_wall and not r.stats.is_ranged:
			continue   # sulle mura non si arriva in mischia
		if f.inside(t.mid()) != me_in and not any_open:
			continue
		var d := r.mid().distance_to(t.mid())
		if d < bd:
			bd = d
			best = t
	return best


# ---------------------------------------------------------------- difesa

func _defend_plan(mine: Array[Regiment], foes: Array[Regiment], f: Fortress) -> void:
	if _station.is_empty():
		for r in battle.regiments:
			if r.team == team:
				_station[r.reg_id] = {"pos": r.center, "face": r.facing}
	# intrusi: attaccanti dentro le mura o sulla soglia di una porta abbattuta
	var intruders: Array[Regiment] = []
	for t in foes:
		var m := t.mid()
		if f.inside(m):
			intruders.append(t)
			continue
		for g in f.open_gates():
			if m.distance_to(g.center) < 14.0 + t.bound_radius():
				intruders.append(t)
				break
	for r in mine:
		if r.state == Regiment.State.FIGHTING:
			continue
		var st: Dictionary = _station.get(r.reg_id, {"pos": r.center, "face": r.facing})
		if r.on_wall:
			# sulle mura nessuno li raggiunge in mischia: tirano al bersaglio migliore e restano lì
			if r.uses_missiles():
				var bw := _best_in_range(r, foes)
				if bw != null:
					_attack(r, bw, false)
				elif r.state == Regiment.State.ATTACKING:
					r.order_halt()
			continue
		if r.stats.is_ranged and r.uses_missiles():
			var threat := _closest(r, intruders, 30.0)
			if threat != null:
				var away := Regiment._flat(r.mid() - threat.mid()).normalized()
				var spot := f.interior_rect(8.0)
				var dest := r.center + away * 25.0
				dest.x = clampf(dest.x, spot.position.x, spot.end.x)
				dest.z = clampf(dest.z, spot.position.y, spot.end.y)
				r.order_move(dest, -away, true)
			elif r.state == Regiment.State.IDLE and r.center.distance_to(st["pos"]) > 8.0:
				r.order_move(st["pos"], st["face"])
			else:
				# dalla postazione: il bersaglio migliore a tiro, mai inseguito fuori dalle mura
				var best := _best_in_range(r, foes)
				if best != null:
					_attack(r, best, false)
				elif r.state == Regiment.State.ATTACKING:
					r.order_halt()
			continue
		var reach := 30.0 if r.stats.is_general else 90.0
		var t := _closest(r, intruders, reach)
		if t != null:
			_attack(r, t, r.mid().distance_to(t.mid()) < 40.0)
			continue
		# nessun intruso: se stava inseguendo qualcuno ormai fuori, torna in postazione
		var chasing_outside := r.state == Regiment.State.ATTACKING and r.attack_target != null \
				and not intruders.has(r.attack_target)
		if chasing_outside or (r.state == Regiment.State.IDLE and r.center.distance_to(st["pos"]) > 6.0):
			r.order_move(st["pos"], st["face"])


func _best_in_range(r: Regiment, foes: Array[Regiment]) -> Regiment:
	var best: Regiment = null
	var best_s := -1e9
	for t in foes:
		var d := r.mid().distance_to(t.mid())
		if d > r.missile_range() * 0.88 or d < r.stats.min_range:
			continue
		var s := -d / 60.0 + arrow_value(r, t) + (-1.5 if t.in_melee else 0.8)
		if t.state == Regiment.State.BREACHING:
			s += 0.4   # chi sta sfondando una porta è un bersaglio urgente
		if s > best_s:
			best_s = s
			best = t
	return best


func _closest(r: Regiment, list: Array[Regiment], max_d: float) -> Regiment:
	var best: Regiment = null
	var bd := max_d
	for t in list:
		var d := r.mid().distance_to(t.mid())
		if d < bd:
			bd = d
			best = t
	return best
