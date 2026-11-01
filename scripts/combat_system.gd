class_name CombatSystem
extends RefCounted
## Mischia, cariche e separazione tra soldati. Gira a tick fissi (10/s), non a ogni frame.
## Usa una griglia spaziale: ogni soldato guarda solo le celle vicine invece di tutti gli altri.
## Solo i reggimenti "caldi" (vicini a un altro reggimento) entrano nella griglia.
##
## Nota di performance: i dati dei soldati vengono copiati in array "piatti" (g_*) all'inizio
## del tick, e i risultati riscritti una volta per reggimento. In GDScript scrivere
## `altro_oggetto.array[i] = x` dentro un ciclo copia l'intero array ogni volta: va evitato.

const CELL := 2.0
const SEEK_RANGE := 3.5
const HOT_MARGIN := 4.0

var battle: BattleManager
var grid := {}
var g_pos := PackedVector3Array()
var g_reg := PackedInt32Array()
var g_idx := PackedInt32Array()
var _rad := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _team := PackedInt32Array()
var _layer := PackedInt32Array()   ## 0 a terra, 1 sulle mura: livelli diversi non si toccano
var _start := PackedInt32Array()
var _end := PackedInt32Array()


func _init(b: BattleManager) -> void:
	battle = b


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func tick(dt: float) -> void:
	var regs := battle.regiments
	var nreg := regs.size()
	_rad.resize(nreg)
	_mass.resize(nreg)
	_team.resize(nreg)
	_layer.resize(nreg)
	_start.resize(nreg)
	_end.resize(nreg)
	# 1. quali reggimenti sono abbastanza vicini da poter interagire?
	for r in regs:
		r.hot = false
		r.contact_this_tick = false
		_rad[r.reg_id] = r.stats.radius
		_mass[r.reg_id] = r.stats.mass
		_team[r.reg_id] = r.team
		_layer[r.reg_id] = 1 if r.on_wall else 0
	for a in nreg:
		var r := regs[a]
		if not r.is_on_field():
			continue
		var rm := r.mid()
		var rb := r.bound_radius()
		for b in range(a + 1, nreg):
			var o := regs[b]
			if not o.is_on_field():
				continue
			if rm.distance_to(o.mid()) < rb + o.bound_radius() + HOT_MARGIN:
				r.hot = true
				o.hot = true
	# 2. array piatti + griglia spaziale con i soldati dei reggimenti caldi
	grid.clear()
	g_pos.resize(0)
	g_reg.resize(0)
	g_idx.resize(0)
	for r in regs:
		_start[r.reg_id] = g_pos.size()
		if r.hot and r.is_on_field():
			var rp := r.pos
			var al := r.alive
			for i in r.count:
				if al[i] == 1:
					var k := g_pos.size()
					var p := rp[i]
					g_pos.append(p)
					g_reg.append(r.reg_id)
					g_idx.append(i)
					var c := cell_of(p)
					if grid.has(c):
						(grid[c] as Array).append(k)
					else:
						grid[c] = [k]
		_end[r.reg_id] = g_pos.size()
	# 3. ogni soldato: separazione, bersaglio, attacco
	for r in regs:
		if not r.is_on_field():
			continue
		if r.hot:
			_process_regiment(r, dt)
		else:
			r.seek_target.fill(-1)
			r.push.fill(Vector3.ZERO)
	# 4. stato di mischia dei reggimenti
	for r in regs:
		_update_melee_state(r, dt)
	# 5. assedio: chi è a ridosso di una porta la colpisce
	if battle.fortress != null:
		for r in regs:
			if r.state == Regiment.State.BREACHING and r.is_on_field() and not r.stats.is_artillery:
				_breach(r, dt)


func _breach(r: Regiment, dt: float) -> void:
	var f := battle.fortress
	var g := r.attack_gate
	if g == null or g.destroyed or r.mid().distance_to(g.center) > r.bound_radius() + 12.0:
		return
	var timers := r.timer
	var al := r.alive
	var rp := r.pos
	var seek := r.seek_target
	var kn := r.knock
	var reach := r.stats.radius + 1.8
	# i mostri sfondano molto meglio: le porte si abbattono con la forza, non con la perforazione
	var dmg := (r.stats.damage_base * 0.5 + r.stats.damage_ap + (30.0 if r.stats.is_large else 0.0)) \
			* r.fatigue_mult() * maxf(1.0, r.stats.splash)
	var total := 0.0
	for i in r.count:
		if al[i] == 0 or kn[i] > 0.0 or seek[i] >= 0:
			continue
		if f.dist_to_gate(g, rp[i]) > reach:
			continue
		timers[i] -= dt
		if timers[i] <= 0.0:
			timers[i] = r.stats.attack_interval * randf_range(0.8, 1.2)
			total += dmg
	r.timer = timers
	if total > 0.0:
		f.damage_gate(g, total)


func _process_regiment(r: Regiment, dt: float) -> void:
	var regs := battle.regiments
	var rid := r.reg_id
	var my_team := r.team
	var my_layer := _layer[rid]
	var routing := r.state == Regiment.State.ROUTING
	var can_seek := r.state == Regiment.State.FIGHTING \
			or (r.state == Regiment.State.ATTACKING and not r.uses_missiles())
	var rc := 2 if r.stats.radius > 0.8 else 1
	var my_r := r.stats.radius
	var my_mass := r.stats.mass
	# copie locali: si scrivono qui e si riassegnano una volta sola alla fine
	var push := r.push
	var seek := r.seek_target
	var timers := r.timer
	var impact := r.impact_done
	var knock := r.knock
	for k in range(_start[rid], _end[rid]):
		var i := g_idx[k]
		var p := g_pos[k]
		var c := cell_of(p)
		var best := -1
		var best_d := 1e9
		var sx := 0.0
		var sz := 0.0
		for dx in range(-rc, rc + 1):
			for dz in range(-rc, rc + 1):
				var cell: Variant = grid.get(Vector2i(c.x + dx, c.y + dz))
				if cell == null:
					continue
				for kk: int in cell:
					if kk == k:
						continue
					var op := g_pos[kk]
					var dxv := op.x - p.x
					var dzv := op.z - p.z
					var dsq := dxv * dxv + dzv * dzv
					var orid := g_reg[kk]
					if _layer[orid] != my_layer:
						continue
					var rs := my_r + _rad[orid]
					if dsq < rs * rs:
						if dsq > 0.0001:
							var dl := sqrt(dsq)
							var om := _mass[orid]
							var f := (rs - dl) / dl * (om / (om + my_mass)) * 5.0
							sx -= dxv * f
							sz -= dzv * f
						else:
							sx += randf_range(-1.0, 1.0)
					if _team[orid] != my_team and dsq < best_d:
						best_d = dsq
						best = kk
		push[i] = Vector3(sx, 0.0, sz)
		seek[i] = -1
		if best < 0 or routing or knock[i] > 0.0:
			continue
		var orid2 := g_reg[best]
		var o := regs[orid2]
		var j := g_idx[best]
		var reach := 1.0 + my_r + o.stats.radius
		var dist := sqrt(best_d)
		if dist <= reach:
			r.contact_this_tick = true
			o.contact_this_tick = true
			if o.stats.causes_fear:
				r.fear_timer = 1.0
			if r.stats.causes_fear:
				o.fear_timer = 1.0
			seek[i] = (orid2 << 12) | j
			if r.charge_timer <= 0.0 and r.charge_dist >= 20.0:
				r.charge_timer = 12.0
				r.impact_window = 0.6
				r.charge_dist = 0.0
				impact.fill(0)
			if r.impact_window > 0.0 and impact[i] == 0:
				impact[i] = 1
				_impact(r, i, p, o, j)
			timers[i] -= dt
			if timers[i] <= 0.0:
				timers[i] = r.stats.attack_interval * randf_range(0.8, 1.2)
				_attack(r, p, o, j)
				r.mark_action(i, UnitVisual.ATTACK)
		elif can_seek and dist < SEEK_RANGE + o.stats.radius:
			seek[i] = (orid2 << 12) | j
	r.push = push
	r.seek_target = seek
	r.timer = timers
	r.impact_done = impact


## Impatto fisico della carica: chi ha più slancio atterra il nemico.
func _impact(r: Regiment, i: int, p: Vector3, o: Regiment, j: int) -> void:
	var braced := o.stats.anti_large and r.stats.is_large \
			and o.state != Regiment.State.MOVING and o.state != Regiment.State.ROUTING \
			and o.side_of(p) == 0
	if braced:
		# carica contro un muro di lance: è il caricante a subire l'impatto
		r.take_damage(i, 10.0 + o.stats.bonus_vs_large * 0.5, o, true)
		r.apply_knock(i, -r.facing * 3.0, 1.0)
		return
	var mom_a := r.stats.mass * r.stats.speed
	var mom_d := o.stats.mass * 3.0
	if mom_a > mom_d * randf_range(0.8, 1.6):
		o.apply_knock(j, r.facing * 4.0, 1.5)
		o.take_damage(j, r.stats.charge_bonus * 0.4 * (1.0 - o.stats.armor / 200.0), r, true)


## Un colpo di mischia (formule del documento di design).
func _attack(r: Regiment, p: Vector3, o: Regiment, j: int) -> void:
	var ma := r.eff_ma()
	var md := o.eff_md()
	var mult := 1.0
	if o.state == Regiment.State.ROUTING:
		md = 0.0
		mult = 2.0
	else:
		var side := o.side_of(p)
		if side == 2:
			md *= 0.4
			o.rear_timer = 1.5
		elif side == 1:
			ma += 10.0
			o.flank_timer = 1.5
	var frac := r.charge_timer / 12.0
	ma += r.stats.charge_bonus * frac * 0.5
	var dmg_base := r.stats.damage_base + r.stats.charge_bonus * frac * 0.5
	if r.stats.anti_large and o.stats.is_large:
		ma += r.stats.bonus_vs_large
		dmg_base += r.stats.bonus_vs_large
	var chance := clampf(35.0 + ma - md, 8.0, 90.0)
	_hit(r, o, j, dmg_base * mult, r.stats.damage_ap * mult, chance)
	# mostri ed eroi colpiscono più nemici vicini
	if r.stats.splash > 1:
		var extra := r.stats.splash - 1
		var opos := o.pos
		var oal := o.alive
		var center := opos[j]
		for k in o.count:
			if extra <= 0:
				break
			if k == j or oal[k] == 0:
				continue
			if opos[k].distance_squared_to(center) < 4.8:
				_hit(r, o, k, dmg_base * mult, r.stats.damage_ap * mult, chance)
				extra -= 1


func _hit(r: Regiment, o: Regiment, j: int, dmg_base: float, ap: float, chance: float) -> void:
	if randf() * 100.0 >= chance:
		return
	var dmg := dmg_base * (1.0 - o.stats.armor * randf_range(0.5, 1.0) / 100.0) + ap
	o.take_damage(j, dmg, r, true)


func _update_melee_state(r: Regiment, dt: float) -> void:
	r.impact_window = maxf(0.0, r.impact_window - dt)
	if not r.is_on_field():
		r.in_melee = false
		return
	if r.contact_this_tick:
		r.in_melee = true
		r.melee_timer = 0.0
		r.melee_duration += dt
		if r.state == Regiment.State.IDLE or r.state == Regiment.State.ATTACKING:
			r.state = Regiment.State.FIGHTING
	else:
		r.melee_timer += dt
		if r.in_melee and r.melee_timer > 1.5:
			r.in_melee = false
			r.melee_duration = 0.0
			if r.state == Regiment.State.FIGHTING:
				r.resume_after_fight()
