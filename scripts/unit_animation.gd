@tool
class_name UnitAnimation
extends Resource
## Un'animazione di un soldato (fermo, cammino, attacco...). Due modi, combinabili:
## - procedurale: oscillazioni e piegamenti calcolati nello shader, regolabili qui sotto;
## - cotta (VAT): fotogrammi presi dalla texture VAT della UnitVisual (da un modello con scheletro).
## I soldati sono disegnati in massa con MultiMesh, che non supporta gli scheletri: per questo
## le animazioni vivono nello shader e non in un AnimationPlayer.

@export_group("Ritmo")
## Cicli al secondo (passi, galoppo, respiro). Ignorato se "Una volta" è attivo.
@export_range(0.0, 5.0, 0.05) var speed := 1.0:
	set(v): speed = v; emit_changed()
## Animazione che si esegue una volta (attacco, tiro, colpito, morte) invece di ripetersi.
@export var one_shot := false:
	set(v): one_shot = v; emit_changed()
## Durata in secondi di un'animazione "Una volta".
@export_range(0.05, 5.0, 0.05) var duration := 0.6:
	set(v): duration = v; emit_changed()

@export_group("Movimento procedurale")
## Saltello verticale a ogni passo (m).
@export_range(0.0, 1.0, 0.01) var bob := 0.0:
	set(v): bob = v; emit_changed()
## Dondolio laterale (gradi).
@export_range(0.0, 30.0, 0.5) var sway_deg := 0.0:
	set(v): sway_deg = v; emit_changed()
## Beccheggio avanti-indietro, come un cavallo al galoppo (gradi).
@export_range(0.0, 30.0, 0.5) var rock_deg := 0.0:
	set(v): rock_deg = v; emit_changed()
## Inclinazione di tutto il corpo in avanti (negativa = indietro), in gradi.
## Nelle animazioni "Una volta" va e torna, oppure resta se "Mantieni inclinazione" è attivo.
@export_range(-90.0, 90.0, 0.5) var lean_deg := 0.0:
	set(v): lean_deg = v; emit_changed()
## Resta inclinato alla fine (cadere a terra, nella morte).
@export var hold_lean := false:
	set(v): hold_lean = v; emit_changed()
## Piegamento della parte alta (busto e arma, o il braccio della catapulta), in gradi:
## positivo = in avanti. È il colpo d'arma negli attacchi.
@export_range(-120.0, 120.0, 0.5) var bend_deg := 0.0:
	set(v): bend_deg = v; emit_changed()
## Altezza (m) sopra cui il modello si piega.
@export_range(0.0, 6.0, 0.05) var bend_pivot := 1.0:
	set(v): bend_pivot = v; emit_changed()

@export_group("Animazione cotta (VAT)")
## Primo fotogramma nella texture VAT della UnitVisual.
@export var vat_first_frame := 0:
	set(v): vat_first_frame = v; emit_changed()
## Numero di fotogrammi (0 = nessuna animazione cotta, solo procedurale).
@export var vat_frame_count := 0:
	set(v): vat_frame_count = v; emit_changed()
## Fotogrammi al secondo per le animazioni che si ripetono.
@export var vat_fps := 30.0:
	set(v): vat_fps = v; emit_changed()


static func make(p: Dictionary) -> UnitAnimation:
	var a := UnitAnimation.new()
	for k in p:
		a.set(k, p[k])
	return a


## I parametri impacchettati come li legge lo shader (4 vec4 per stato).
func packed() -> Array[Vector4]:
	return [
		Vector4(speed, bob, sway_deg, rock_deg),
		Vector4(lean_deg, bend_deg, bend_pivot, 1.0 if one_shot else 0.0),
		Vector4(duration, 1.0 if hold_lean else 0.0, float(vat_first_frame), float(vat_frame_count)),
		Vector4(vat_fps, 0.0, 0.0, 0.0),
	]
