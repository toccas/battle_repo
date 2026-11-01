class_name AIGeneral
extends RefCounted
## IA a livello di esercito (doc: "IA di battaglia"). Ogni 2 s sceglie una postura
## e dà ordini ai reggimenti in base al loro ruolo. Il combattimento vero lo fanno i sistemi.

const THINK_EVERY := 2.0

var battle: BattleManager
var team := 1
var posture := "defensive"
var _acc := 1.0
var _waypoint := {}   ## reg_id -> {"pos": Vector3, "target": Regiment}
var _cycle_until := {} ## reg_id -> tempo di battaglia fino a cui la cavalleria si sgancia
var _fallback := {}    ## reg_id -> punto fisso di ripiegamento per le unità vacillanti


func _init(b: BattleManager, p_team: int) -> void:
	battle = b
	team = p_team


func update(dt: float) -> void:
	if battle.phase != BattleManager.Phase.BATTLE:
		return
	_acc += dt
	if _acc >= THINK_EVERY:
		_acc = 0.0
		think()


func think() -> void:
	var mine: Array[Regiment] = []
	var foes: Array[Regiment] = []
	for r in battle.regiments:
		if not r.is_on_field() or r.state == Regiment.State.ROUTING:
			continue
		if r.team == team:
			mine.append(r)
		else:
			foes.append(r)
	if mine.is_empty() or foes.is_empty():
		return
	var my_str := battle.team_strength(team)
	var en_str := battle.team_strength(1 - team)
	var my_c := _centroid(mine)
	var en_c := _centroid(foes)
	var fwd := Regiment._flat(en_c - my_c).normalized()
	var gap := my_c.distance_to(en_c)
	var has_archers := false
	for r in mine:
		if r.uses_missiles():
			has_archers = true
	if my_str > en_str * 1.15:
		posture = "offensive"
	elif has_archers and gap > 70.0 and battle.battle_time < 150.0:
		posture = "defensive"
	else:
		posture = "offensive"
	for r in mine:
		match r.stats.role:
			"ranged", "artillery":
				_ranged(r, foes, fwd)
			"cavalry", "general":
				_mobile(r, foes, fwd, my_c)
			_:
				_melee(r, foes, fwd, my_c)


func _melee(r: Regiment, foes: Array[Regiment], fwd: Vector3, my_c: Vector3) -> void:
	if r.state == Regiment.State.FIGHTING:
		return
	# vacillante: ripiega su un punto fisso dietro la linea; se il nemico è addosso, combatte
	# il punto viene scelto una volta sola: se seguisse il centro dell'esercito,
	# arretrerebbe insieme alle unità e la ritirata non finirebbe mai
	if r.morale >= 30.0:
		_fallback.erase(r.reg_id)
	if r.morale < 22.0 and not r.in_melee and not battle.enemy_within(r, 25.0):
		if not _fallback.has(r.reg_id):
			var fp := my_c - fwd * 20.0
			fp.z = clampf(fp.z, -BattleManager.EDGE + 25.0, BattleManager.EDGE - 25.0)
			_fallback[r.reg_id] = fp
		var fallback: Vector3 = _fallback[r.reg_id]
		if r.mid().distance_to(fallback) > 15.0:
			if r.state != Regiment.State.MOVING or r.move_target.distance_to(fallback) > 10.0:
				r.order_move(fallback, fwd)
			return
		if posture == "defensive" or r.state == Regiment.State.MOVING:
			return
	if posture == "defensive":
		var near := _nearest(r, foes, 45.0)
		if near != null:
			_attack(r, near, true)
		return
	var best: Regiment = null
	var best_s := -1e9
	for f in foes:
		var d := r.mid().distance_to(f.mid())
		var s := -d / 40.0
		if f.stats.is_ranged:
			s += 0.4
		if f.in_melee:
			s += 0.6
		if r.stats.role == "monster":
			s += -1.2 if f.stats.anti_large else 0.8
		if s > best_s:
			best_s = s
			best = f
	if best != null:
		_attack(r, best, r.mid().distance_to(best.mid()) < 45.0)


func _ranged(r: Regiment, foes: Array[Regiment], fwd: Vector3) -> void:
	if r.in_melee:
		return
	if not r.uses_missiles():
		if not r.stats.is_artillery:
			_melee(r, foes, fwd, _centroid_of_team())
		return
	# fanteria o cavalleria in arrivo: arretra (le macchine d'assedio sono troppo lente)
	for f in foes:
		if r.stats.is_artillery:
			break
		if not f.stats.is_ranged and not f.in_melee and f.mid().distance_to(r.mid()) < 32.0:
			var away := Regiment._flat(r.mid() - f.mid()).normalized()
			r.order_move(r.center + away * 30.0, -away, true)
			return
	var best: Regiment = null
	var best_s := -1e9
	for f in foes:
		var d := r.mid().distance_to(f.mid())
		if d > r.stats.missile_range * 1.05 or d < r.stats.min_range:
			continue
		var s := -d / 60.0 + arrow_value(r, f)
		s += -1.5 if f.in_melee else 0.8
		if s > best_s:
			best_s = s
			best = f
	if best != null:
		_attack(r, best, false)
	elif posture == "offensive":
		var near := _nearest(r, foes, 1e9)
		if near != null:
			_attack(r, near, false)


func _mobile(r: Regiment, foes: Array[Regiment], fwd: Vector3, my_c: Vector3) -> void:
	var id := r.reg_id
	# il generale ferito si ritira dietro le linee
	if r.stats.is_general and r.hp_total < r.start_hp_total * 0.5:
		if r.state != Regiment.State.MOVING:
			r.order_move(my_c - fwd * 35.0, fwd, true)
		return
	if r.state == Regiment.State.FIGHTING:
		# ciclo di carica: dopo un po' in mischia (o se sta perdendo) la cavalleria si sgancia
		var losing := r.melee_duration > 1.0 and r.recent_taken > r.recent_dealt
		if r.stats.role == "cavalry" and (r.melee_duration > 5.0 or losing):
			var side := Vector3(-fwd.z, 0.0, fwd.x) * (1.0 if randf() < 0.5 else -1.0)
			r.order_move(r.center - fwd * 30.0 + side * 15.0, fwd, true)
			_cycle_until[id] = battle.battle_time + 7.0
		return
	if _cycle_until.has(id) and battle.battle_time < float(_cycle_until[id]):
		return
	if _waypoint.has(id):
		var wp: Dictionary = _waypoint[id]
		var t: Regiment = wp["target"]
		if not t.is_on_field() or t.state == Regiment.State.ROUTING:
			_waypoint.erase(id)
		elif r.mid().distance_to(wp["pos"]) < 10.0 or r.state == Regiment.State.IDLE:
			_waypoint.erase(id)
			_attack(r, t, true)
			return
		else:
			return
	var best: Regiment = null
	var best_s := -1e9
	for f in foes:
		var d := r.mid().distance_to(f.mid())
		var s := -d / 60.0
		if f.stats.is_ranged:
			s += 1.5
		if f.in_melee:
			s += 1.2
		if f.stats.anti_large:
			s -= 1.2 if f.in_melee else 2.5
		if s > best_s:
			best_s = s
			best = f
	if best == null or best_s < -2.5 or (r.stats.is_general and best_s < -0.5):
		# niente di buono da caricare: resta dietro la linea (il generale dà +morale)
		var hold := my_c - fwd * 18.0
		if r.state == Regiment.State.IDLE and r.mid().distance_to(hold) > 25.0:
			r.order_move(hold, fwd)
		return
	# la strada passa in mezzo ad altri nemici? aggira dal lato più vicino
	if r.attack_target != best:
		var blocker := _blocking(r, best, foes)
		if blocker != null:
			var bside := Vector3(-fwd.z, 0.0, fwd.x)
			var sgn := 1.0 if (r.mid() - blocker.mid()).dot(bside) >= 0.0 else -1.0
			var around := blocker.mid() + bside * sgn * (blocker.bound_radius() + 25.0)
			r.order_move(around, fwd, true)
			_waypoint[id] = {"pos": around, "target": best}
			return
	# bersaglio impegnato di fronte: aggiralo e caricalo alle spalle
	if best.in_melee and best.side_of(r.mid()) == 0 and r.attack_target != best:
		var behind := best.mid() - best.facing * (best.depth() * 0.5 + 25.0)
		r.order_move(behind, best.facing, true)
		_waypoint[id] = {"pos": behind, "target": best}
		return
	_attack(r, best, true)


## Quanto rende una freccia contro questo bersaglio: frazione di soldato uccisa per colpo,
## scalata (0 = inutile, come contro un troll; ~1 = arcieri senza corazza).
static func arrow_value(r: Regiment, t: Regiment) -> float:
	var dmg := r.stats.missile_damage * (1.0 - t.stats.armor * 0.75 / 100.0) + r.stats.missile_ap
	if not r.stats.is_artillery:
		if t.stats.has_shield:
			dmg *= 0.8
		if t.on_wall:
			dmg *= 1.0 - Fortress.WALL_COVER
	var v := clampf(dmg / t.stats.hp, 0.0, 1.0) * 2.0
	if r.stats.is_artillery:
		v += minf(t.alive_count, 80) / 80.0   # un'esplosione rende di più su una formazione fitta
	# chi ci sta tirando addosso va zittito per primo
	if t.uses_missiles() and t.attack_target == r:
		v += 1.0
	return v


func _attack(r: Regiment, t: Regiment, run: bool) -> void:
	if r.attack_target == t and r.running == run \
			and (r.state == Regiment.State.ATTACKING or r.state == Regiment.State.FIGHTING):
		return
	r.order_attack(t, run)


## Un nemico (diverso dal bersaglio) si trova sulla linea retta verso il bersaglio?
func _blocking(r: Regiment, target: Regiment, foes: Array[Regiment]) -> Regiment:
	var a := r.mid()
	var b := target.mid()
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.001)
	for f in foes:
		if f == target or f.stats.is_ranged:
			continue
		var m := f.mid()
		var t := clampf((m - a).dot(ab) / len2, 0.0, 1.0)
		if t <= 0.05 or t >= 0.95:
			continue
		if m.distance_to(a + ab * t) < f.bound_radius() + r.bound_radius() + 3.0:
			return f
	return null


func _nearest(r: Regiment, foes: Array[Regiment], max_d: float) -> Regiment:
	var best: Regiment = null
	var best_d := max_d
	for f in foes:
		var d := r.mid().distance_to(f.mid())
		if d < best_d:
			best_d = d
			best = f
	return best


func _centroid_of_team() -> Vector3:
	var list: Array[Regiment] = []
	for r in battle.regiments:
		if r.team == team and r.is_on_field():
			list.append(r)
	return _centroid(list) if not list.is_empty() else Vector3.ZERO


func _centroid(list: Array[Regiment]) -> Vector3:
	var c := Vector3.ZERO
	for r in list:
		c += r.mid()
	return c / list.size()
