extends SceneTree
## Rigenera i file .tres delle unità con i valori di default, e le mesh in data/meshes/.
## Uso (da riga di comando, nella cartella del progetto):
##   godot --headless --script res://tools/generate_units.gd
## Attenzione: sovrascrive le modifiche fatte nell'Inspector.

const UnitStatsScript := preload("res://scripts/unit_stats.gd")


func _init() -> void:
	var units := {
		"spearmen": {
			"cost": 450, "description": "Fanteria difensiva con scudi e lance: ferma la cavalleria e i mostri.",
			"display_name": "Lancieri", "role": "infantry", "mesh_kind": "spear",
			"models": 80, "hp": 30.0, "default_cols": 20, "armor": 35.0,
			"melee_attack": 22.0, "melee_defense": 36.0, "damage_base": 20.0, "damage_ap": 5.0,
			"charge_bonus": 8.0, "has_shield": true, "anti_large": true, "bonus_vs_large": 16.0,
			"speed": 4.0, "leadership": 55.0, "tint": Color(1.0, 1.0, 1.0),
		},
		"swordsmen": {
			"cost": 600, "description": "Fanteria d'assalto corazzata: vince gli scontri contro altra fanteria.",
			"display_name": "Spadaccini", "role": "infantry", "mesh_kind": "infantry",
			"models": 70, "hp": 33.0, "default_cols": 17, "armor": 45.0,
			"melee_attack": 34.0, "melee_defense": 26.0, "damage_base": 24.0, "damage_ap": 8.0,
			"charge_bonus": 14.0, "has_shield": true, "speed": 4.2, "leadership": 60.0,
			"tint": Color(0.72, 0.72, 0.8),
		},
		"archers": {
			"cost": 550, "description": "Tiratori a distanza: logorano il nemico da 140 m, fragili in mischia.",
			"display_name": "Arcieri", "role": "ranged", "mesh_kind": "archer",
			"models": 60, "hp": 24.0, "default_cols": 20, "spacing": 1.5, "armor": 10.0,
			"melee_attack": 14.0, "melee_defense": 10.0, "damage_base": 14.0, "damage_ap": 3.0,
			"speed": 4.4, "leadership": 50.0, "is_ranged": true, "missile_range": 140.0,
			"ammo": 15, "reload_time": 7.0, "missile_damage": 9.0, "missile_ap": 4.0,
			"tint": Color(1.25, 1.25, 1.1),
		},
		"knights": {
			"cost": 900, "description": "Cavalleria pesante: cariche devastanti ai fianchi e alle spalle.",
			"display_name": "Cavalieri", "role": "cavalry", "mesh_kind": "cavalry",
			"models": 30, "hp": 48.0, "default_cols": 10, "spacing": 2.4, "row_spacing": 3.4,
			"radius": 0.9, "model_height": 2.6, "armor": 60.0,
			"melee_attack": 32.0, "melee_defense": 22.0, "damage_base": 24.0, "damage_ap": 10.0,
			"charge_bonus": 45.0, "is_large": true, "speed": 9.0, "turn_rate": 1.2,
			"mass": 500.0, "leadership": 65.0, "tint": Color(0.9, 0.9, 1.0),
		},
		"troll": {
			"cost": 1200, "description": "Mostri enormi che causano paura e travolgono più nemici a ogni colpo.",
			"display_name": "Troll", "role": "monster", "mesh_kind": "monster",
			"models": 6, "hp": 1100.0, "default_cols": 3, "spacing": 4.0, "row_spacing": 4.0,
			"radius": 1.3, "model_height": 4.2, "armor": 20.0,
			"melee_attack": 36.0, "melee_defense": 20.0, "damage_base": 55.0, "damage_ap": 25.0,
			"attack_interval": 2.2, "charge_bonus": 30.0, "splash": 3, "is_large": true,
			"causes_fear": true, "speed": 6.0, "turn_rate": 1.4, "mass": 1500.0,
			"leadership": 55.0, "tint": Color(0.75, 1.3, 0.6),
		},
		"catapult": {
			"cost": 900, "description": "Lancia massi a parabola oltre le mura: colpisce aree larghe e sfonda le porte. Lenta e indifesa da vicino.",
			"display_name": "Catapulte", "role": "artillery", "mesh_kind": "catapult",
			"models": 4, "hp": 260.0, "default_cols": 4, "spacing": 7.0, "row_spacing": 7.0,
			"radius": 1.8, "model_height": 4.0, "armor": 0.0,
			"melee_attack": 8.0, "melee_defense": 5.0, "damage_base": 10.0, "damage_ap": 2.0,
			"speed": 2.2, "turn_rate": 0.6, "mass": 3000.0, "leadership": 58.0,
			"is_ranged": true, "missile_range": 300.0, "ammo": 25, "reload_time": 16.0,
			"missile_damage": 40.0, "missile_ap": 10.0,
			"is_artillery": true, "splash_radius": 4.5, "gate_damage": 260.0, "high_arc": true, "min_range": 60.0,
			"tint": Color(1.0, 1.0, 1.0),
		},
		"cannon": {
			"cost": 1100, "description": "Tiro teso e potentissimo: perfetto contro porte e formazioni compatte. Esplosione stretta, pochi pezzi.",
			"display_name": "Cannoni", "role": "artillery", "mesh_kind": "cannon",
			"models": 3, "hp": 300.0, "default_cols": 3, "spacing": 8.0, "row_spacing": 8.0,
			"radius": 1.6, "model_height": 2.2, "armor": 10.0,
			"melee_attack": 8.0, "melee_defense": 5.0, "damage_base": 10.0, "damage_ap": 2.0,
			"speed": 2.0, "turn_rate": 0.6, "mass": 3000.0, "leadership": 58.0,
			"is_ranged": true, "missile_range": 260.0, "ammo": 30, "reload_time": 15.0,
			"missile_damage": 50.0, "missile_ap": 20.0,
			"is_artillery": true, "splash_radius": 3.0, "gate_damage": 400.0, "high_arc": false, "min_range": 30.0,
				"wall_mount": true,
			"tint": Color(1.0, 1.0, 1.0),
		},
		"general": {
			"cost": 0, "description": "Il comandante: dà morale ai reggimenti vicini. Sempre presente.",
			"display_name": "Generale", "role": "general", "mesh_kind": "general",
			"models": 1, "hp": 2400.0, "default_cols": 1, "spacing": 2.4, "radius": 0.9,
			"model_height": 2.8, "armor": 70.0, "melee_attack": 60.0, "melee_defense": 45.0,
			"damage_base": 60.0, "damage_ap": 40.0, "attack_interval": 1.4, "charge_bonus": 40.0,
			"splash": 2, "is_large": true, "is_general": true, "speed": 8.0, "turn_rate": 2.0,
			"mass": 600.0, "leadership": 80.0, "tint": Color(1.3, 1.15, 0.55),
		},
	}
	DirAccess.make_dir_recursive_absolute("res://data/units")
	# le mesh del prototipo, come file a sé: nell'Inspector si sostituiscono con un modello vero
	DirAccess.make_dir_recursive_absolute("res://data/meshes")
	var mesh_script: GDScript = load("res://scripts/unit_meshes.gd")
	var visual_script: GDScript = load("res://scripts/unit_visual.gd")
	for kind: String in mesh_script.KINDS:
		var mpath := "res://data/meshes/%s.tres" % kind
		print("%s -> %s" % [mpath, error_string(ResourceSaver.save(mesh_script.build(kind), mpath))])
	for id in units:
		var s: Resource = UnitStatsScript.new()
		s.set("id", id)
		var values: Dictionary = units[id]
		for key in values:
			s.set(key, values[key])
		# aspetto: la mesh salvata sopra e le animazioni preimpostate per quel tipo di modello
		var kind: String = values["mesh_kind"]
		var mesh: Mesh = ResourceLoader.load("res://data/meshes/%s.tres" % kind, "", ResourceLoader.CACHE_MODE_REPLACE)
		s.set("visual", visual_script.preset(kind, mesh))
		var path := "res://data/units/%s.tres" % id
		var err := ResourceSaver.save(s, path)
		print("%s -> %s" % [path, error_string(err)])
	quit()
