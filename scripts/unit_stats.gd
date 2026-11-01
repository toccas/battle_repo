class_name UnitStats
extends Resource
## Statistiche di un tipo di unità. Ogni file in res://data/units/ è una di queste:
## aprilo nell'Inspector di Godot per bilanciare il gioco senza toccare il codice.

@export var id := "spearmen"
@export var display_name := "Lancieri"
@export_enum("infantry", "ranged", "cavalry", "monster", "general", "artillery") var role: String = "infantry"
@export var cost := 500                 ## punti nella scena di preparazione
@export_multiline var description := ""

@export_group("Modelli e formazione")
@export var models := 80
@export var hp := 10.0
@export var default_cols := 16
@export var spacing := 1.3            ## distanza tra soldati affiancati (m)
@export var row_spacing := 1.3        ## distanza tra le file (m)
@export var radius := 0.35            ## ingombro del singolo soldato (m)
@export var model_height := 1.8
@export_enum("infantry", "spear", "archer", "cavalry", "monster", "general", "catapult", "cannon") var mesh_kind: String = "infantry"
@export var tint := Color(1, 1, 1)

@export_group("Aspetto")
## Mesh e animazioni (fermo, cammino, corsa, attacco, tiro, colpito, morte).
## Vuoto = modello semplice del prototipo scelto da "Mesh Kind".
@export var visual: UnitVisual
## Ritratto per la carta in basso (creato da tools/genera_ritratti.tscn).
@export var icon: Texture2D

@export_group("Mischia")
@export var armor := 30.0
@export var melee_attack := 25.0
@export var melee_defense := 30.0
@export var damage_base := 20.0
@export var damage_ap := 5.0           ## danno perforante: ignora la corazza
@export var attack_interval := 1.6     ## secondi tra un attacco e l'altro
@export var charge_bonus := 10.0
@export var splash := 1                ## bersagli colpiti per attacco (mostri, eroi)
@export var has_shield := false
@export var anti_large := false
@export var bonus_vs_large := 0.0
@export var is_large := false

@export_group("Movimento")
@export var speed := 4.0               ## velocità di corsa (m/s)
@export var turn_rate := 1.6           ## rad/s
@export var mass := 60.0

@export_group("Morale")
@export var leadership := 50.0
@export var causes_fear := false
@export var immune_psychology := false
@export var is_general := false

@export_group("Tiro")
@export var is_ranged := false
@export var missile_range := 140.0
@export var ammo := 15
@export var reload_time := 7.0
@export var missile_damage := 12.0
@export var missile_ap := 4.0

@export_group("Artiglieria")
@export var is_artillery := false
@export var splash_radius := 0.0     ## raggio dell'esplosione (m): colpisce tutti, anche gli alleati
@export var gate_damage := 0.0       ## danno a una porta per colpo
@export var high_arc := true         ## true = tiro a parabola (catapulta), false = tiro teso (cannone)
@export var min_range := 0.0         ## sotto questa distanza non può tirare
@export var wall_mount := false      ## si può schierare sulle mura (cannoni), su una sola fila
