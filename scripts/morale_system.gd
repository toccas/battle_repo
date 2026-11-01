class_name MoraleSystem
extends RefCounted
## Morale = leadership + somma dei modificatori (tabella nel documento di design).
## Il valore reale insegue quello "obiettivo": scende in fretta, risale piano.
## Sotto zero il reggimento va in rotta; dopo 15 s lontano dai nemici si può riprendere.

const RALLY_TIME := 15.0
const RALLY_SAFE_DIST := 35.0

var battle: BattleManager


func _init(b: BattleManager) -> void:
	battle = b


func tick(dt: float) -> void:
	for r in battle.regiments:
		if not r.is_on_field():
			continue
		r.recent_dealt *= 0.93
		r.recent_taken *= 0.93
		var mods := modifiers(r)
		var total := 0.0
		for v: float in mods.values():
			total += v
		r.morale_target = r.stats.leadership + total
		if r.state != Regiment.State.ROUTING:
			if r.stats.immune_psychology:
				r.morale = maxf(r.morale_target, 1.0)
				continue
			r.morale += clampf(r.morale_target - r.morale, -4.0 * dt * 2.0, 1.5 * dt * 2.0)
			if r.morale <= 0.0:
				r.start_rout()
		else:
			if battle.enemy_within(r, RALLY_SAFE_DIST):
				r.calm_timer = 0.0
			else:
				r.calm_timer += dt
			if r.calm_timer >= RALLY_TIME and not r.shattered and battle.phase == BattleManager.Phase.BATTLE:
				r.rally()


## Restituisce i modificatori attivi (nome -> valore): usato anche dall'interfaccia.
func modifiers(r: Regiment) -> Dictionary:
	var m := {}
	var exchanged := r.recent_dealt + r.recent_taken
	if exchanged > 5.0:
		var ratio := (r.recent_dealt - r.recent_taken) / exchanged
		if ratio > 0.15:
			m["Vince lo scontro"] = 8.0
		elif ratio < -0.15:
			m["Perde lo scontro"] = -lerpf(4.0, 25.0, clampf((-ratio - 0.15) / 0.7, 0.0, 1.0))
	var lost := 1.0 - r.hp_total / r.start_hp_total
	if lost > 0.02:
		m["Perdite"] = -minf(35.0, lost * 50.0)
	if r.flank_timer > 0.0:
		m["Attaccato al fianco"] = -8.0
	if r.rear_timer > 0.0:
		m["Attaccato alle spalle"] = -15.0
	var g := battle.general_of(r.team)
	if g == null or not g.is_on_field():
		m["Generale caduto"] = -15.0
	elif g != r and g.state != Regiment.State.ROUTING and g.mid().distance_to(r.mid()) < 40.0:
		m["Generale vicino"] = 10.0
	var routers := 0
	for o in battle.regiments:
		if o != r and o.team == r.team and o.state == Regiment.State.ROUTING:
			if o.mid().distance_to(r.mid()) < 30.0:
				routers += 1
	if routers > 0:
		m["Alleati in fuga"] = -4.0 * mini(routers, 4)
	if r.under_fire_timer > 0.0:
		m["Sotto tiro"] = -4.0
	if r.fear_timer > 0.0 and not r.stats.immune_psychology and not r.stats.causes_fear:
		m["Paura"] = -8.0
	var fl := r.fatigue_level()
	if fl > 2:
		m["Stanchezza"] = -2.5 * (fl - 2)
	return m
