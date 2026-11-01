# Battaglie – prototipo (Godot 4.3+)

Primo prototipo del sistema di battaglia descritto nel documento di design, milestone **M1 + M2** con un anticipo di M3/M4: due eserciti da circa 470 soldati ciascuno, formazioni a slot, mischia, cariche, tiro con frecce balistiche, morale con rotta a catena e un'IA nemica.

## Come avviarlo

1. Installa **Godot 4.3** o successivo (versione standard, non serve .NET).
2. Apri Godot → *Importa* → scegli il file `project.godot` in questa cartella.
3. Premi **F5**. Si apre la **scena di preparazione** (vedi sotto). Scegli tipo di battaglia ed esercito, poi *Inizia la battaglia*.
4. Parti in fase di **schieramento**: disponi le tue unità (blu) nella zona azzurra, poi premi **Invio**.

## Scena di preparazione

- **Tipo di battaglia:** campale, assedio in attacco o assedio in difesa.
- **Punti:** 3000, 5000, 7000 o 9000. In assedio chi attacca riceve il 30% di punti in più, perché i difensori hanno mura e torri.
- **Il tuo esercito:** aggiungi reggimenti dal catalogo (con statistiche e costo), al massimo 12 più il generale, che è sempre presente e gratuito.
- **Esercito nemico:** generato a caso con lo stesso budget (al massimo 2 pezzi d'artiglieria); *Genera un altro nemico* lo rifà.
- **Fortezza** (solo in assedio): scegli tra quelle del gioco e quelle create con l'editor; accanto vedi la pianta.
- **Editor fortezze…**: apre lo strumento per disegnarne di nuove (vedi sotto).

Le scelte restano memorizzate: tornando dal campo (tasto **M** a fine battaglia, **F10** in qualsiasi momento) ritrovi tutto com'era.

## Assedio

Nel gioco ci sono due fortezze: la *Classica* (un recinto di 120 × 80 m) e la *Rocca a due cinte* (cinta esterna e mastio interno con il punto di vittoria). Altre si creano con l'editor. Gli attaccanti arrivano sempre da sud.

- **Porte:** la resistenza dipende dalla larghezza (900 punti per metro: una porta da 10 m ne ha 9000). Le **postierle** le usano solo i difensori e non si possono abbattere. Le porte chiuse sono muro per gli attaccanti; i difensori ci passano.
- **Abbattere una porta:** con dei reggimenti selezionati, click destro sulla porta (cursore a spada, porta evidenziata in rosso). Il reparto si stringe alla larghezza della porta e i soldati delle prime file la colpiscono. I mostri sfondano molto più in fretta. Lo stato di ogni porta è scritto sopra di essa e in alto nello schermo.
- **Torri:** tirano frecce da sole sugli attaccanti entro 110 m.
- **Mura:** in difesa, fanteria e arcieri possono stare sul camminamento. In schieramento ci vanno subito con un click destro sulle mura. In battaglia salgono e scendono da sole: raggiungono i piedi delle mura, salgono in 3 secondi (scendono in 2) e per cambiare lato scendono e risalgono. Sulle mura la mischia non li raggiunge, i merli fermano il 40% delle frecce tirate dal basso e la gittata aumenta del 20%. Sulle mura i soldati non stanno in un blocco rettangolare: si mettono su due file lungo il camminamento attorno al punto scelto e, se il lato è corto, girano l'angolo sui lati vicini, saltando le torri; ognuno guarda fuori dal proprio lato. Per spostarsi su un altro lato della stessa cinta camminano lungo il camminamento senza scendere. Anche i **cannoni** possono salire: si mettono in un'unica fila lungo il camminamento, con la bocca tra i merli. Cavalleria, mostri, catapulte e generale restano a terra. L'IA difensiva mette arcieri e cannoni sulle mura.
- **Aspetto:** mura, torri e porte sono mesh generate da codice in `scripts/fortress_meshes.gd`: pietre squadrate con la malta, zoccolo a scarpa, cornici, feritoie, merli verso l'esterno e parapetto basso verso l'interno; torri con ballatoio su mensole, cantonali e stendardo; porte con arco a sesto acuto, battenti di tavole con fasce di ferro e stemma, e macerie quando vengono abbattute. Colori e misure (pietre, merli) sono in cima al file. Le dimensioni usate dalla simulazione non cambiano.
- **Resistenza delle porte:** scritta in piccolo sul battente, dal lato esterno. Si vede solo entro 90 m e le mura la coprono.
- **Punto di vittoria:** il cerchio al centro della fortezza. Se ci sono attaccanti e nessun difensore, si riempie in 45 secondi e gli attaccanti vincono. I difensori lo riportano a zero in 30 secondi; se ci sono entrambi resta fermo.
- **Altre condizioni:** vince chi mette in rotta l'altro esercito. Se passano 20 minuti, vincono i difensori.
- **Movimento:** i reggimenti trovano da soli la strada attraverso le porte aperte e si mettono in colonna per passarle; i soldati non attraversano le mura. I difensori in rotta escono dalla postierla.
- **IA che attacca:** individua le porte che le sbarrano la strada verso il punto di vittoria (con più cinte, prima quelle esterne e poi quelle interne). Manda un reparto a sfondarle, prima i mostri, e l'artiglieria a bombardarle. Tiene gli altri fuori portata, raduna le truppe davanti alla breccia e poi entra tutta insieme.
- **IA che difende:** presidia le porte e il punto, tira dalle mura scegliendo i bersagli più esposti (soprattutto chi sta sfondando una porta), affronta chi entra e poi torna in postazione. Non esce mai dalle mura.

## Comandi

| Input | Azione |
| --- | --- |
| Click sinistro / trascina | Seleziona un reggimento / rettangolo di selezione |
| Shift + click | Aggiungi o togli dalla selezione |
| Doppio click | Seleziona tutte le unità dello stesso tipo |
| Click sulla carta in basso | Seleziona (doppio click: centra la camera) |
| Ctrl+A / Esc | Seleziona tutto / deseleziona |
| Click destro sul terreno | Muovi (doppio click destro: corri) |
| Shift + click destro | Aggiunge una tappa al percorso: l'unità le percorre in ordine (funziona anche trascinando). Su un nemico, l'attacco va in coda: quando il nemico muore o fugge, l'unità prosegue con le tappe successive |
| Click destro sul nemico | Attacca (doppio click destro: carica di corsa) |
| Click destro trascinato | Disponi i selezionati in linea: la lunghezza decide la larghezza |
| Backspace | Ferma l'unità |
| Ctrl+1…9 / 1…9 | Crea gruppo / richiama gruppo |
| F | La camera segue l'unità selezionata |
| WASD o frecce, Q/E, rotella, tasto centrale | Camera |
| Spazio / Tab | Pausa attiva / velocità 1x-2x-3x |
| Invio | Inizia la battaglia |
| Click destro su una porta | Assedio: abbattila |
| Click destro sulle mura | Assedio in difesa: fanti, arcieri e cannoni salgono sul camminamento |
| H / F9 / R | Mostra-nascondi aiuto / ricomincia / ricomincia a fine battaglia |
| M (a fine battaglia) / F10 | Torna alla scena di preparazione |

**Risposta automatica:** un reparto fermo e senza ordini che viene attaccato reagisce da solo (sulla scheda compare *Risponde all'attacco*). Se lo attaccano in mischia si gira e affronta l'attaccante con tutto il reparto; se lo bersagliano, arcieri e cannoni rispondono al fuoco contro chi gli tira, se è a portata. Non insegue chi fugge né chi si allontana oltre 35 m da dove è partito, poi torna fermo. La fanteria sotto tiro non parte da sola all'inseguimento degli arcieri, l'artiglieria non si sposta e chi è sulle mura non scende. Qualsiasi ordine annulla la risposta. Si spegne o si regola con `AUTO_RETALIATE` e `AUTO_CHASE` in cima a `scripts/regiment.gd`; vale anche per l'IA.

### Segnali a terra e cursore

- **Freccia verde** dal reggimento al punto in cui andrà, con la **sagoma della formazione** all'arrivo: compare mentre scegli la destinazione (anteprima tenue) e resta finché l'unità non arriva. Azzurra se l'unità corre.
- **Cursore sul nemico** con unità selezionate: il nemico si illumina con un **contorno rosso**, il cursore diventa una **spada** e parte una **freccia rossa** da ogni unità selezionata. La freccia è **arancione** se degli arcieri dovranno avvicinarsi prima di poter tirare.
- **Arcieri selezionati:** **cerchio giallo** con la gittata attuale. Mentre scegli dove spostarli, un secondo cerchio tenue mostra la gittata che avranno nella nuova posizione.
- Passando sopra un tuo reggimento compare un contorno verde, per capire cosa selezioni.

Con un solo reggimento selezionato, in basso a destra vedi il morale con **tutti i modificatori attivi** (perdite, fianco, generale vicino…): è il modo più veloce per capire perché un'unità sta per scappare.

## Artiglieria

| Unità | Tiro | Gittata | Esplosione | Contro le porte | Costo |
| --- | --- | --- | --- | --- | --- |
| Catapulte (4 macchine) | A parabola, scavalca le mura | 60–300 m | 4,5 m | 260 per colpo | 900 |
| Cannoni (3 pezzi) | Teso, preciso | 30–260 m | 3 m | 400 per colpo | 1100 |

- Ogni colpo esplode all'impatto: colpisce **tutti** i soldati nel raggio, alleati compresi, e sbalza a terra quelli non grandi. Un'esplosione a terra non tocca chi è sulle mura, e viceversa.
- **Bombardare una porta:** seleziona l'artiglieria e fai click destro sulla porta. I pezzi si avvicinano finché la porta è a tiro, poi si fermano e tirano. Contro i reparti funziona come gli arcieri: click destro sul nemico.
- Le macchine tirano solo da ferme, sono lente e quasi indifese in mischia. I cannoni in difesa si possono mettere sulle mura (gittata +20%, ma sotto i 30 m non possono colpire chi è ai piedi del muro); le catapulte restano a terra. Quali unità salgono lo decide *Wall Mount* nella scheda dell'unità (gruppo Artiglieria).
- L'IA usa l'artiglieria contro le porte quando attacca, e contro le formazioni più fitte e gli arcieri in campo aperto o in difesa.

## Editor fortezze (strumento di sviluppo)

Dalla preparazione: **Editor fortezze…** (scena `fortress_editor.tscn`). A sinistra la pianta vista dall'alto, con il nord in alto e in basso la zona da cui arrivano gli attaccanti.

| Strumento (tasto) | Come si usa |
| --- | --- |
| Muro (1) | Trascina: il muro è sempre orizzontale o verticale, a passi di 2 m, e le estremità si agganciano a quelle vicine |
| Porta (2) | Click su un muro; la larghezza (6–12 m) si sceglie nel pannello e decide la resistenza |
| Postierla (3) | Click su un muro: porta da 6 m per i soli difensori |
| Torre (4) | Click; si aggancia agli angoli dei muri. Tira frecce da sola |
| Punto di vittoria (5) | Click; il cerchio diventa verde se è dentro le mura |
| Gomma (6) | Click su un elemento per toglierlo (l'elemento si evidenzia in rosso) |

- **Ctrl+Z** o *Annulla* torna indietro di una modifica. Il click destro interrompe il muro che stai tracciando.
- Il pannello verifica la pianta mentre lavori. Mostra cosa manca per giocarla: mura che non chiudono il punto di vittoria, nessuna porta abbattibile, interno troppo piccolo. L'interno chiuso dalle mura è colorato.
- **Salva** scrive un file JSON in `user://fortezze/`, che sul tuo computer è la cartella dei dati di Godot per questo progetto; il percorso esatto compare dopo il salvataggio. La fortezza salvata diventa quella scelta nella preparazione. *Carica* ed *Elimina* agiscono sulle fortezze salvate; quelle del gioco si possono caricare come base, ma non eliminare.
- **Prova: Difendi / Attacca** avvia subito un assedio sulla pianta corrente, anche se non è salvata, con gli eserciti della preparazione. A fine battaglia **M** (o **F10** in qualsiasi momento) ti riporta all'editor con il lavoro com'era.
- Le fortezze del gioco sono file JSON in `data/fortezze/`. Il formato è descritto in cima a `scripts/fortress_layout.gd`.

## Aspetto e animazioni delle unità

Apri un'unità in `data/units/` e guarda la sezione **Aspetto → Visual** nell'Inspector:

- **Modello:** la mesh di un soldato (quelle del prototipo stanno in `data/meshes/`), una texture dei colori facoltativa, quanto la tinge il colore della squadra, e scala, rotazione e spostamento per adattare un modello tuo. I soldati guardano verso -Z.
- **Animazioni:** una per stato: *Idle* (fermo), *Walk* (cammino), *Run* (corsa, anche in rotta), *Attack* (colpo in mischia), *Shoot* (tiro di arcieri e artiglieria), *Hit* (sbalzato da cariche ed esplosioni), *Death* (caduta; il corpo resta nella posa finale). Ognuna ha:
  - *Ritmo:* cicli al secondo; "una volta" e durata per le azioni.
  - *Movimento procedurale:* saltello, dondolio laterale, beccheggio, inclinazione del corpo (che può restare, come nella morte) e piegamento della parte alta sopra un'altezza scelta. Il piegamento è il fendente dei fanti o lo scatto del braccio della catapulta.
  - *Animazione cotta (VAT):* il primo fotogramma e il numero di fotogrammi nella texture VAT.
- Le preimpostazioni sono diverse per fanti, cavalieri, troll, catapulte e cannoni. Una scheda senza *Visual* usa la preimpostazione di *Mesh Kind*. `tools/generate_units.gd` le rigenera, sovrascrivendo le modifiche.

**Anteprima:** apri `tools/anteprima_unita.tscn` nell'editor e seleziona il nodo radice. Nell'Inspector scegli unità, stato, numero di soldati e velocità. Ogni modifica all'aspetto dell'unità si vede subito nella vista 3D, senza avviare il gioco. Avviata con F6: tasti 1-7 per lo stato, Q/E per l'unità, rotella per lo zoom.

**Perché nello shader:** i soldati sono disegnati in massa con un MultiMesh per reggimento (così si reggono migliaia di modelli), e il MultiMesh non supporta scheletri né AnimationPlayer. Le animazioni sono quindi calcolate dalla scheda video, nello shader `scripts/unit.gdshader`, condiviso con il contorno di selezione tramite `scripts/unit_anim.gdshaderinc`. Ogni soldato ha il proprio stato, l'istante in cui è iniziato e uno sfasamento casuale, così i passi non sono sincronizzati. Le animazioni si fermano con la pausa e accelerano con la velocità di gioco.

**Modelli veri con scheletro (VAT):** per usare un modello animato (.glb o .gltf, per esempio dai pacchetti low-poly o da Blender):
1. Mettilo nel progetto (per esempio `data/unithMesh/Enemies/Demon.gltf`).
2. Apri `tools/vat_baker.tscn` e seleziona il nodo `CotturaVAT`. Nell'Inspector:
   - **Source File:** il modello.
   - **Assign To:** la scheda dell'unità che lo userà (per esempio `data/units/troll.tres`).
3. Spunta **Bake Now**. Nel pannello *Output* leggi quali animazioni ha usato per ogni stato.

Le animazioni si riconoscono dal nome: *Idle*, *Walk*, *Run*, *Attack*/*Punch*/*Slash*, *HitRecieve*/*HitReact*, *Death*, *Shoot*/*Bow*/*Throw*. Se un nome non viene trovato, scrivilo a mano nel campo dello stato; scrivi `-` per lasciarlo procedurale.

Il modello viene scalato all'altezza dell'unità, appoggiato a terra e girato verso -Z, e nella scheda viene assegnato l'aspetto `data/visuals/<nome>/aspetto.tres`. Le normali si calcolano se il modello non le ha. Le texture piccole a tavolozza restano nitide grazie all'opzione *Pixel Texture*. Gli stati senza animazione nel modello usano quella procedurale del tipo di unità.

**Source Folder** al posto di *Source File* cuoce in una volta tutti i modelli di una cartella. Ognuno finisce nella sua sottocartella di `data/visuals/`, e poi lo trascini su *Aspetto → Visual* dell'unità che vuoi.

Da riga di comando: `godot --headless --path . --script res://tools/vat_bake_cli.gd -- --src=res://data/unithMesh/Enemies/Demon.gltf --unit=res://data/units/troll.tres`. Con `--src` puoi indicare anche una cartella.

**L'arciere low-poly** (`data/unithMesh/Units/Archer.gltf`, già cotto e assegnato agli Arcieri) è generato da codice: `python3 tools/modelli/genera_arciere.py`. Nel file si cambiano i colori (`PALETTE`), le forme (`build_mesh`) e le animazioni (una funzione per stato: `idle`, `walk`, `run`, `attack`, `shoot`, `hit`, `death`); poi si ricuoce come qualsiasi altro modello. Il .gltf si apre anche in Blender.

Allo stesso modo **il lanciere** (`Spearman.gltf`, assegnato ai Lancieri): `python3 tools/modelli/genera_lanciere.py`. I soldati nuovi usano i pezzi comuni di `tools/modelli/lowpoly.py` (forme, scheletro, mira con le braccia, scrittura del .gltf): per farne un altro conviene copiare `genera_lanciere.py` e cambiare equipaggiamento e animazioni.

**Lo spadaccino** (`Swordsman.gltf`, assegnato agli Spadaccini): `python3 tools/modelli/genera_spadaccino.py`, elmo chiuso, cotta di maglia con sopravveste, scudo a scudetto e spada; il fendente si regola nella tabella `SLASH` (tempi, posizione della mano e direzione della lama).

**Il troll** (`Troll.gltf`): `python3 tools/modelli/genera_troll.py`, con la clava; prende il posto del *Demon* (che resta in `data/visuals/demon/` e si può rimettere trascinandolo su *Aspetto → Visual*).

**Cavaliere e generale a cavallo** (`Knight.gltf`, `General.gltf`): `python3 tools/modelli/genera_cavaliere.py` li crea tutti e due (o uno solo: `knight`, `general`). Il cavallo ha uno scheletro suo, con passo a quattro tempi e galoppo; le andature si regolano nelle tabelle `WALK_PH` e `GALLOP_PH` (sfasamento di ogni zampa) e in `legs_horse`. Colori e arma di ciascuno sono in `VARIANTS`.

**La catapulta** (`Catapult.gltf`, assegnata alle Catapulte): `python3 tools/modelli/genera_catapulta.py`, un mangano su ruote con due serventi. Lo script stampa l'altezza naturale del modello: va cotto con quella (`--height=2.40`, o *Target Height* nel baker) per non ingrandire anche i serventi fino all'altezza della vecchia catapulta. `S` in cima al file è la grandezza della macchina rispetto ai serventi.

**Il cannone** (`Cannon.gltf`, assegnato ai Cannoni): `python3 tools/modelli/genera_cannone.py`, canna di bronzo su affusto con due serventi; al tiro lampo, fumo e rinculo, poi scovolano e lo riportano in batteria. Si cuoce con `--height=1.86`. Le ossa che iniziano con `Prop.` (attrezzi, fumo, lampo) non contano per l'altezza.

Il baker misura l'altezza solo sul corpo: le mesh o le ossa con nomi da arma o oggetto (lancia, spada, scudo, arco, stendardo, *spear*, *sword*, *shield*, *bow*, *weapon*...) non contano, così una lancia alzata non rimpicciolisce il soldato.

**Carte in basso:** ogni reparto ha una carta a stendardo nel colore della squadra con il ritratto e tre barre (verde salute, gialla morale, azzurra munizioni per chi tira). Selezionata diventa dorata, in rotta il ritratto si tinge di rosso, distrutta si spegne. Le carte si stringono per stare su una fila e, se sono troppe, vanno a capo. I ritratti si creano con `tools/genera_ritratti.tscn` (avvialo con F6, serve la finestra): fotografa il modello di ogni unità, salva `data/icons/<id>.res` e lo assegna a *Aspetto → Icon*. Rilancialo quando cambi un modello; le inquadrature per tipo sono in `FRAMING`.

Limiti: un solo materiale con una texture per unità. Le texture VAT crescono con vertici × fotogrammi (massimo 16384 righe): per modelli pesanti abbassa gli fps di cottura. In esportazione va inclusa la cartella `data/visuals/`.

## Cosa c'è (rispetto al documento di design)

| Sezione del documento | Nel prototipo |
| --- | --- |
| Flusso della battaglia | Schieramento → battaglia → schermata finale con esito (decisiva, normale, di Pirro). Rotta generale al 60% dei reggimenti in fuga. |
| Unità | 8 tipi come `Resource` modificabili: lancieri (anti-grande), spadaccini, arcieri, cavalieri, troll (paura, colpi ad area), catapulte, cannoni, generale. |
| Combattimento | Probabilità di colpire `35 + MA − MD`, danno base ridotto dalla corazza + perforante, fianchi e retro, carica (impatto con atterramento, bonus che decade in 12 s, muro di lance), frecce balistiche con fuoco amico e parata degli scudi, munizioni. |
| Morale e stanchezza | Leadership + modificatori, stati Ardito/Saldo/Esitante/Vacillante/In rotta, ritorno in battaglia dopo 15 s al sicuro (massimo 2 volte, poi "spezzato"), 6 livelli di stanchezza. |
| Formazioni e movimento | Formazione a slot, chi è dietro avanza a coprire i caduti, larghezza regolabile, separazione tra soldati con la massa. |
| Comandi | Tutti quelli della tabella sopra. |
| IA | Generale con posture (difensiva/offensiva), ruoli per tipo di unità, arcieri che arretrano, cavalleria che aggira, carica alle spalle e si sgancia (ciclo di carica). |
| Architettura | Soldati come array di dati (non nodi), un `MultiMesh` per reggimento, combattimento a 10 tick/s con griglia spaziale, morale a 2 tick/s, IA ogni 2 s. |

**Non ancora presenti:** LOD e impostori per le grandi distanze, terreno con colline e boschi (la mappa è piatta; i percorsi usano un piccolo grafo attorno alla fortezza invece di una navmesh), arieti e scale, magia, formazioni speciali, esperienza, modelli definitivi (i soldati sono forme semplici). Sono le milestone M3–M5 della roadmap.

## Struttura

```
army_select.tscn / scripts/army_select.gd   scena di preparazione (scena iniziale)
scripts/game_config.gd           autoload GameConfig: scelte della preparazione, budget, eserciti casuali
main.tscn / scripts/main.gd      costruisce mondo, fortezza, eserciti, camera, interfaccia
fortress_editor.tscn / scripts/fortress_editor.gd   editor delle fortezze
scripts/fortress_layout.gd       pianta della fortezza come dati: JSON, mura tagliate dalle porte, interno, controlli
scripts/fortress_map_view.gd     disegno della pianta vista dall'alto (editor e preparazione)
scripts/fortress.gd              la fortezza in battaglia: mura, porte, torri, punto di vittoria, percorsi
scripts/fortress_meshes.gd       mesh di mura, torri, porte e macerie (pietre, merli, archi) generate da codice
data/fortezze/*.json             le fortezze del gioco
scripts/siege_ai.gd              IA d'assedio (attacco e difesa)
scripts/battle_manager.gd        fasi, tempo, ciclo dei sistemi, fine battaglia
scripts/regiment.gd              reggimento: formazione, ordini, movimento, grafica
scripts/combat_system.gd         mischia, cariche, separazione (griglia spaziale)
scripts/projectile_system.gd     frecce
scripts/morale_system.gd         morale, rotta, raccolta
scripts/ai_general.gd            IA dell'esercito
scripts/player_controller.gd     selezione e ordini del giocatore
scripts/camera_rig.gd            camera RTS
scripts/battle_ui.gd             carte unità (disposizione), barra di potere, schermata finale
scripts/unit_card.gd             la carta a stendardo di un reparto: ritratto e barre
scripts/order_feedback.gd        frecce, sagome e cerchi di gittata disegnati a terra
scripts/outline.gdshader         contorno dei reggimenti sotto il cursore
scripts/unit_stats.gd            definizione delle statistiche (Resource)
scripts/unit_visual.gd           aspetto di un'unità: mesh, texture, animazioni, VAT (Resource)
scripts/unit_animation.gd        un'animazione: parametri procedurali e fotogrammi VAT (Resource)
scripts/unit_meshes.gd           le mesh semplici del prototipo
scripts/unit.gdshader            shader dei soldati; unit_anim.gdshaderinc = l'animazione condivisa
data/meshes/*.tres               le mesh del prototipo, sostituibili nell'Inspector
tools/anteprima_unita.tscn       anteprima di unità e animazioni nell'editor
tools/vat_baker.tscn             cottura delle animazioni di un modello con scheletro
data/units/*.tres                le statistiche di ogni unità
tools/                           generatore delle unità e test automatici
```

## Bilanciare e sperimentare

- **Statistiche:** apri un file in `data/units/` nell'Inspector e cambia i valori. `tools/generate_units.gd` ripristina quelli di default (sovrascrive le modifiche).
- **Eserciti e costi:** dalla scena di preparazione; i costi sono nel campo `cost` di ogni unità, budget e limiti in `scripts/game_config.gd`.
- **Fortezza:** forma e porte con l'editor. Resistenza delle porte per metro e area costruibile in cima a `scripts/fortress_layout.gd`; torri, copertura delle mura e tempi di conquista in cima a `scripts/fortress.gd`.
- **Artiglieria:** gittata, esplosione, danno e danno alle porte nei file `catapult.tres` e `cannon.tres` (sezione *Artiglieria* nell'Inspector).
- **Formule:** `_attack()` in `combat_system.gd`, `modifiers()` in `morale_system.gd`.
- **IA contro IA, senza grafica:** dalla cartella del progetto
  `godot --headless --path . --fixed-fps 60 res://main.tscn -- --autotest` (campale)
  `godot --headless --path . --fixed-fps 60 res://main.tscn -- --autotest-siege` (assedio; aggiungi `--defend` per far difendere i blu)
  aggiungi `--artillery` per dare catapulte e cannoni a entrambi, e `--fortress=res://data/fortezze/rocca_due_cinte.json` per scegliere la fortezza
  stampa ogni 20 s lo stato dei reggimenti e alla fine un riepilogo con perdite, uccisioni, danni subiti in mischia e dal tiro, e chi ha ucciso chi. È il modo più rapido per vedere l'effetto di un cambio di numeri.
- **Test dei comandi:** `godot --path . res://tools/input_test.tscn` simula click e tasti e verifica 20 comandi e feedback.
- **Test di mura e tappe:** `godot --path . res://tools/wall_test.tscn` mette dei lancieri sulle mura in schieramento, sposta gli arcieri dalle mura sud alle mura est, verifica che la mischia non li raggiunga e prova le tappe con Shift, anche con un attacco in coda.
- **Test dell'editor:** `godot --path . res://tools/editor_test.tscn` disegna col mouse un forte quadrato (muri, porta, postierla, torri, punto di vittoria). Prova gomma, annulla e una porta sovrapposta, salva, ritrova la fortezza nella preparazione e ci combatte un assedio.
- **Test delle animazioni:** `godot --path . res://tools/anim_test.tscn` controlla che ogni unità abbia mesh e 7 animazioni, che in battaglia i soldati passino per fermo, cammino, corsa, attacco, tiro e morte, e che l'anteprima si aggiorni subito dopo una modifica.
- **Test del percorso completo:** `godot --path . res://tools/flow_test.tscn` sceglie l'assedio nella preparazione, aggiunge un troll, avvia la battaglia, prova hover e click sulla porta e salva degli screenshot nella cartella `user://`.

## Note di prestazioni

In GDScript il tick di combattimento costa 4–9 ms con circa 900 soldati in mischia (misurato su una CPU cloud, a velocità 3x). Il valore è mostrato in alto a destra. Se scende il frame rate quando aumenti gli eserciti, il primo passo è spostare `combat_system.gd` in C# o GDExtension, come previsto dal documento.

Trucco importante già applicato nel codice: in GDScript scrivere `altro_oggetto.array[i] = x` dentro un ciclo copia l'intero array a ogni scrittura. Per questo i sistemi lavorano su copie locali e le riassegnano una volta per reggimento.

Documento di Design
https://docs.google.com/document/d/1T4Ri2I7LD9N7R9Offo3c_yTaeax3ISnwbhYYRh7eK3w/edit?usp=sharing
