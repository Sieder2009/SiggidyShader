# Aurora Nights

Ein realistischer, aber bewusst "minecraftiger" Shader für **Minecraft Java Edition 26.3**, gebaut für **Iris** (empfohlen) oder **OptiFine**.

Fokus:
- weiche Richtungsschatten (Sonne/Mond) über eine echte Shadow Map, jetzt mit **Hardware-PCF** (`sampler2DShadow`/`shadow2D`) statt manueller Tiefenvergleiche - günstiger *und* weicher
- ein selbst gemalter, dynamischer Himmel mit sanftem Tag/Nacht/Sonnenuntergangs-Verlauf
- eine **einfache, animierte Wolkenebene** (prozedural, kein Texture-Asset nötig)
- ein **funkelndes, prozedurales Sternenfeld** bei Nacht
- Wasser mit animierten Wellen, Spiegel-Highlight und Fresnel-Reflexion
- warmes Fackellicht, kühles Himmelslicht
- **HDR-Bloom** über den Mip-Chain-Trick (siehe unten) statt eines teuren manuellen Weichzeichners, Filmic-Tonemapping (ACES), dezente Vignette
- eine leichte **Kantenglättung** (FXAA-artig) und ein feines Dithering gegen Banding im Himmel
- ein echtes **Performance-Profil-System** (Potato/Low/Medium/High) direkt im Shader-Options-Menü
- wehende Gräser, Blumen, Getreide und Blätter (auch ihre Schatten wehen mit), weiches Pflanzenlicht, leuchtende Blöcke (Lava, Glowstone, Fackelflammen, Laternen, ...), Licht aus der Hand, kein Sonnenlicht mehr in Höhlen, echte Himmelsspiegelung im Wasser, **Polarlichter** am Nachthimmel, Nebel in der Farbe des Himmels sowie eigene Looks für **Nether** und **End** (Details im Abschnitt "Zweite Überarbeitung" unten)
- **neu (sechste Überarbeitung):** ein **Himmel wie in Minecraft**: Minecrafts eigene Himmels- und Nebelfarben (je Biom), eine **eckige, pixelige Sonne**, ein **eckiger Mond mit Phasen**, eckige Sterne und **blockige Wolken** aus 12×12-Feldern; der realistische Himmel bleibt per Option wählbar (Details im Abschnitt "Sechste Überarbeitung" unten)
- **fünfte Überarbeitung:** **TAA** (zeitliche Kantenglättung: ruhige Kanten und Blätter, rauschfreie Schatten, Wolken und Spiegelungen) und **spiegelnde Blöcke** (polierter Stein, Quarz, Eis, Obsidian, glasierte Keramik, Edelstein- und Metallblöcke, dazu Pfützen) (Details im Abschnitt "Fünfte Überarbeitung" unten)
- **vierte Überarbeitung:** **Umgebungsverdeckung (SSAO)**, Wasser mit **Spiegelungen der Landschaft** und **Tiefenfärbung** (klar im Flachen, dunkel blaugrün in der Tiefe), **3D-Wolken**, überarbeitetes Licht (wärmere Sonne, eigene Flächenschattierung) und **Dunst in der Ferne** (Details im Abschnitt "Vierte Überarbeitung" unten)
- **Lichtstrahlen** durch Blätter und an Hügeln vorbei, **Wolkenschatten**, **nasser Boden und Pfützen** nach Regen, ein **Regenbogen**, **Mondphasen**, eine geneigte Sonnenbahn, Kaustiken und Wabern unter Wasser, beleuchtete Partikel und beleuchteter Regen, hell aufleuchtende Blitze und optional **leuchtende Erze** (Details im Abschnitt "Dritte Überarbeitung" unten)

## Installation

1. Diesen gesamten Ordner (bzw. ein ZIP davon) nach `.minecraft/shaderpacks/` kopieren, z. B. als `AuroraNights` bzw. `AuroraNights.zip`.
   - Wichtig ist, dass `pack.mcmeta` und der `shaders/`-Ordner direkt in diesem kopierten Ordner liegen (nicht in einem Unterordner).
2. [Iris](https://irisshaders.net/) installieren (empfohlen) oder OptiFine verwenden.
3. Im Spiel: Video-Einstellungen → Shader Pack → **AuroraNights** auswählen.
4. Bei schwacher/alter GPU: als Erstes oben im Options-Menü das **Profile**-Dropdown auf `POTATO` oder `LOW` stellen (siehe unten). Feintuning danach wie gewohnt über *Shader Options*: Sterndichte/-helligkeit, Wellenhöhe, Schattenweichheit, Belichtung, Sättigung, Bloom, Vignette, Wolken, Polarlicht-Helligkeit, Wind-Stärke/-Tempo, Leuchtstärke der Blöcke, Licht aus der Hand, Neigung der Sonnenbahn, Stärke/Qualität der Lichtstrahlen, Einfluss der Mondphase, Regenbogen, Effekte unter Wasser, leuchtende Erze, Sonnenstärke, Dunst, Stärke der Umgebungsverdeckung, Wassertiefen-Färbung, TAA-Stärke und -Nachschärfung, Himmels-Stil (Minecraft/realistisch), Wolken-Stil (blockig/weich), Minecraft-Himmelsfarben.

## Performance-Profile

Ganz oben in den Shader Options gibt es ein **Profile**-Dropdown mit vier Stufen. Es schaltet nur die tatsächlich performance-relevanten Optionen um; rein optische Regler (Farben, Wellenhöhe, Sternhelligkeit, Belichtung, Leuchtstärke, ...) bleiben davon unberührt und lassen sich weiterhin unabhängig einstellen:

| | **POTATO** | **LOW** | **MEDIUM** *(Standard)* | **HIGH** |
|---|---|---|---|---|
| Schatten | **komplett aus** (Shadow-Pass wird übersprungen, auch im End - der größte Performance-Hebel) | an, 1 Tap (billigste Stufe) | an, 5 Taps | an, 9 Taps |
| Schattenreichweite/-auflösung | - | 96 Blöcke / 1024px | 160 Blöcke / 2048px | 200 Blöcke / 3072px |
| Wolken | aus | blockig (Minecraft) | blockig (Minecraft) | blockig (Minecraft) |
| ...mit `CLOUD_STYLE` = weich | aus | flach | **3D** | **3D** |
| Wolkenschatten | aus | aus | an | an |
| Polarlicht | aus | aus | an | an |
| Wehende Pflanzen | aus | an | an | an |
| Himmelsspiegelung (Wasser/Pfützen) | nur Himmelsverlauf | an | an | an |
| Wasser: Tiefenfärbung | aus | an | an | an |
| Spiegelung der Landschaft (Wasser, Blöcke, Pfützen) | aus | aus | an | an |
| Spiegelnde Blöcke | aus | an (nur Himmel) | an | an |
| Nasser Boden/Pfützen | aus | an | an | an |
| Umgebungsverdeckung (SSAO) | aus | aus | an | an |
| Lichtstrahlen | aus | aus | an, 8 Schritte | an, 12 Schritte |
| Bloom | aus | aus | an | an |
| Kantenglättung | aus | aus | **TAA** | **TAA** |

Wichtig: `POTATO` deaktiviert die Schatten nicht nur optisch, sondern über `program.shadow.enabled=SHADOW_ENABLED` (und `program.world1/shadow.enabled=...` fürs End) in `shaders.properties` den **kompletten Shadow-Map-Renderdurchlauf** - das ist mit Abstand der größte Performance-Hebel für schwache/alte GPUs (integrierte Grafik, alte Notebooks, ...), nicht nur ein optisches Weglassen des Effekts.

## Struktur

```
pack.mcmeta
shaders/
  shaders.properties
  block.properties        # NEU: Block-IDs (Pflanzen, Blätter, leuchtende Blöcke, Wasser)
  lib/common.glsl         # gemeinsame Uniforms, Beleuchtungsmodell, Wind, Nebel, Rausch-/Stern-Helfer
  lib/sky.glsl            # NEU: kompletter Himmel (Verlauf, Sonne/Mond, Sterne, Polarlicht, Wolken, End-Himmel)
  program/                # NEU: der eigentliche Code jeder Stufe (eine Datei pro .vsh/.fsh)
    shadow_*.glsl           # Shadow Map (Hardware-PCF, wehende Pflanzen)
    gbuffers_terrain_*.glsl # Blöcke/Terrain (Wind, Pflanzenlicht, Leuchten)
    gbuffers_water_*.glsl   # Wasser (Wellen, Himmelsspiegelung) + Glas/Eis/...
    gbuffers_entities_*.glsl# Mobs/Spieler (inkl. rotem Treffer-Aufblitzen)
    gbuffers_hand_*.glsl    # Item/Block in der Hand
    gbuffers_textured_lit_* # NEU: Partikel und Regen/Schnee, beleuchtet
    gbuffers_lightning_*    # NEU: Blitze, hell leuchtend
    gbuffers_basic_* / gbuffers_textured_*  # unbeleuchtete Fallbacks (Auswahlbox, Himmel-Grundgeometrie, Leuchtfeuerstrahl, Spinnenaugen, Verzauberungsglanz)
    deferred_*.glsl         # NEU: Umgebungsverdeckung (SSAO), roh
    deferred1_*.glsl        # NEU: malt den Himmel samt 3D-Wolken, glättet und wendet die SSAO an (vor Wasser/Glas)
    composite_*.glsl        # Wasser-Tiefenfärbung, Spiegelungen (Wasser, glänzende Blöcke, Pfützen), Lichtstrahlen (in HDR, ungetonemapped)
    composite1_*.glsl       # Wabern unter Wasser, Bloom (Mip-Chain-Trick) + Belichtung/ACES-Tonemapping/Sättigung
    composite2_*.glsl       # NEU: TAA (zeitliche Kantenglättung)
    final_*.glsl            # Nachschärfen nach TAA (oder FXAA), Vignette, Dithering
  *.vsh / *.fsh           # Overworld: 5-zeilige Wrapper (#version, AURORA_WORLD 0, #include program/...)
  world-1/*.vsh / *.fsh   # Nether: dieselben Wrapper mit AURORA_WORLD -1 (ohne Shadow-Pass)
  world1/*.vsh / *.fsh    # End: dieselben Wrapper mit AURORA_WORLD 1
```

**Wichtig beim Weiterbearbeiten:** Code immer in `program/` bzw. `lib/` ändern, nicht in den Wrapper-Dateien. Die Wrapper gibt es, weil Iris/OptiFine einen Dimensions-Ordner (`world-1/`, `world1/`) als **komplett eigenständiges** Programm-Set laden - fehlende Dateien werden dort *nicht* aus `shaders/` nachgeladen (dieselbe Erfahrung wie bei `highperf-shader`). So gibt es den Code trotzdem nur einmal.

Nicht enthaltene Programme (z. B. `gbuffers_skybasic`, `gbuffers_weather`) fallen automatisch auf `gbuffers_basic`/`gbuffers_textured` zurück (Iris/OptiFine-Standardverhalten) - der Himmel wird davon unabhängig komplett von `deferred1.fsh` neu gezeichnet. Vanillas eigene Wolken werden über `clouds=off` in `shaders.properties` ausgeblendet, damit sie sich nicht mit der neuen, selbst gemalten Wolkenebene überlagern.

## Was sich mit Blick auf ComplementaryReimagined geändert hat

Auf Wunsch wurde `ComplementaryReimagined_r5.9.3/` (ein sehr großer, deferred-gerenderter Shader mit eigener Voxel-Global-Illumination, SSR, TAA, vollem PBR-Materialsystem, ...) als Referenz für Ideen herangezogen. Wichtig dabei: **es wurde kein Code von dort kopiert.** Complementary steht unter einer eigenen Lizenz (`ComplementaryReimagined_r5.9.3/License.txt`), die eine Weiterverbreitung/Bearbeitung ihres Codes nur unter engen Bedingungen erlaubt (u. a. sichtbare Namensnennung, unveränderte Lizenzdatei, deutlich abweichender Look) - und selbst ohne diese Lizenz wäre ihr Code (deferred, mit einem Dutzend zusätzlicher Buffer, SSBOs zur Voxelisierung, ...) technisch gar nicht in Aurora Nights' viel simplerem Forward-Renderer lauffähig gewesen. Stattdessen wurden nur allgemeine, in der Shader-Community verbreitete **Techniken** studiert und für Aurora Nights komplett neu, im eigenen Stil und in der eigenen Architektur implementiert:

- **Performance-Profile** (`profile.POTATO/LOW/MEDIUM/HIGH` in `shaders.properties`) - dasselbe Grundprinzip wie Complementarys eigenes Profil-System, aber mit eigenen, viel kleineren Werten passend zu Aurora Nights' simplerem Feature-Set.
- **Hardware-gefilterte Schatten** (`sampler2DShadow` + `shadow2D()` + `shadowHardwareFiltering`) statt manueller `texture2D`-Tiefenvergleiche - eine Standard-Iris/OptiFine-API, kein Complementary-Code, aber der gleiche Kerntrick: jeder Sample-Tap bekommt "gratis" eine bilineare 2×2-Filterung von der GPU.
- **Mip-basiertes Bloom**: `colortex0` ist jetzt als HDR-Puffer deklariert (`R11F_G11F_B10F`, gleich viele Bits wie vorher, nur anders verteilt) und `composite1.fsh` liest zwei Mip-Stufen davon (`texture2D(colortex0, uv, bias)`, der GLSL-1.20-fragmentshader-sichere Weg für einen expliziten LOD-Bias) statt eines manuellen 5×5-Weichzeichners mit 25 Texturzugriffen. Günstiger *und* mit weicherem Ergebnis.
- **Eine einfache 2D-Wolkenebene** (prozedurales Value-Noise/FBM, komplett selbst geschrieben, keine Textur nötig) statt echter, teurer volumetrischer Wolken.
- **Eine leichte, selbst geschriebene Kantenglättung** nach dem öffentlich dokumentierten FXAA-Prinzip (Timothy Lottes/NVIDIA-Whitepaper) - bewusst vereinfacht (keine iterative Kantenende-Suche) für Performance auf schwacher Hardware.
- **Dithering** über die weit verbreitete "Interleaved Gradient Noise"-Formel (Jimenez 2014) gegen Banding im Himmel/Bloom.

**Bewusst nicht übernommen** (zu teuer und/oder zu riskant für eine "auch auf schwacher GPU"-Anforderung, und architektonisch nicht ohne einen kompletten Umbau auf Deferred Rendering möglich):
- ~~Echtes SSAO~~ (bräuchte einen eigenen Normalen-Buffer) - seit der vierten Überarbeitung umgesetzt, mit dem neuen Puffer `colortex2`.
- ~~TAA~~ (bräuchte History-Buffer + Reprojection) - seit der fünften Überarbeitung umgesetzt; auf `LOW`/`POTATO` bleibt sie aus.
- Voxel-basierte Global Illumination / farbige Lichtausbreitung. ~~Screen-Space-Reflections~~ - seit der vierten Überarbeitung fürs Wasser umgesetzt.
- Echte volumetrische Wolken. ~~Godrays/Lichtschächte~~ - Bildschirm-Godrays wurden wegen des Risikos einer fehlerhaften Sonnen-Bildschirmprojektion (die Kamera kann hinter der Sonne stehen, was die Perspektivteilung entarten lässt) bewusst weggelassen; in der dritten Überarbeitung (unten) gibt es Lichtstrahlen jetzt über die Shadow Map, die ohne diese Projektion auskommen.
- ~~Farbige Block-Emission~~ - in der zweiten Überarbeitung (unten) teilweise umgesetzt: leuchtende Blöcke glühen jetzt selbst in ihrer eigenen Farbe und bloomen. Die *Lichtausbreitung* in die Umgebung bleibt aber vanilla-warm (dafür bräuchte es Voxelisierung wie bei Complementary).

## Zweite Überarbeitung mit Blick auf ComplementaryReimagined

Gleiche Regel wie oben: **kein Code aus Complementary kopiert**, nur Techniken angeschaut und komplett neu geschrieben. Complementarys `block.properties` diente lediglich als Nachschlagewerk dafür, welche Blocknamen es in aktuellen Minecraft-Versionen gibt (`pale_oak_leaves`, `copper_torch`, `short_dry_grass`, ...) - Blocknamen sind Fakten aus dem Spiel; Aufteilung, IDs und Kommentare der neuen `shaders/block.properties` sind eigene.

Neu:
- **Wehende Pflanzen und Blätter** (`WAVING_PLANTS`, `WAVING_STRENGTH`, `WAVING_SPEED`): Gras, Blumen, Setzlinge, Getreide und Blätter bewegen sich im Wind, bei Regen stärker. Bodenpflanzen bleiben unten verankert (nur die obere Kante schwingt), bei zwei Blöcke hohen Pflanzen schwingt die obere Hälfte doppelt so weit und bleibt nahtlos mit der unteren verbunden. Derselbe Wind läuft im Shadow-Pass, damit die Schatten mitwehen statt zu "kriechen". Ranken, Lianen, Zuckerrohr und Seegras werden bewusst nicht bewegt (sie hängen an anderen Blöcken).
- **Weiches Pflanzenlicht**: gekreuzte Gras-/Blumen-Flächen und Blätter nehmen Licht von beiden Seiten an, statt auf der sonnenabgewandten Seite schwarz zu werden; ihr Schatten-Test wird zur Lichtseite hin versetzt, damit sie sich nicht selbst beschatten.
- **Leuchtende Blöcke** (`EMISSION_STRENGTH`): Lava, Glowstone, Seelaterne, Pilzlicht, Froschlichter, Magma, Kürbislaterne, eingeschaltete Redstone-Lampe, Leuchtfeuer, weinender Obsidian glühen ganz; bei Fackeln, Laternen, Feuer, Lagerfeuer und Endstab glühen nur die hellen Pixel (Flamme/Glas, nicht Stiel/Gestell). Sie landen über 1.0 im HDR-Puffer und bekommen dadurch auch Bloom.
- **Licht aus der Hand** (`HELD_LIGHT`): eine Fackel/Laterne/Glowstone in der Haupt- oder Nebenhand beleuchtet die Umgebung, mit Vanillas Abfall von einer Lichtstufe pro Block.
- **Kein Sonnenlicht mehr in Höhlen**: direktes Sonnen-/Mondlicht wird über Vanillas Himmelslicht-Wert ausgeblendet. Vorher wurden Höhlenwände, die zufällig zur Sonne zeigten, hell angestrahlt, sobald die Shadow Map den Verdecker nicht erfasste - jenseits der Schattenreichweite und auf `POTATO` (keine Shadow Map) **immer**.
- **Echte Himmelsspiegelung im Wasser** (`WATER_SKY_REFLECTION`): Wasser spiegelt jetzt den tatsächlichen Himmel inkl. Sonne, Wolken, Sternen und Polarlicht statt einer flachen Himmelsfarbe. Dafür liegt der komplette Himmel jetzt in `lib/sky.glsl` und wird von `composite` und Wasser gemeinsam benutzt. In Höhlen/Innenräumen und beim Blick von unter Wasser wird die Spiegelung ausgeblendet. Außerdem bekommen jetzt **nur noch echtes Wasser** Wellen und Spiegelung - vorher wellten sich auch die Oberseiten von Glas, Eis, Schleim usw. Zwei Folgen davon: (1) Glas, Eis, Schleim, Honig usw. behalten jetzt einfach die Transparenz ihrer Textur - `WATER_OPACITY` wirkt nur noch auf Wasser, wer es verstellt hatte, sieht Glas wieder wie in Vanilla. (2) Wasser wird über `block.properties` (ID 300) erkannt - falls Iris diese Datei nicht liest, hat Wasser keine Wellen/Spiegelung mehr (dann bitte melden, siehe Teststatus).
- **Polarlichter** (`ENABLE_AURORA`, `AURORA_BRIGHTNESS`): grün-violette, langsam wabernde Lichtvorhänge in klaren Nächten, vor allem Richtung Norden - passend zum Namen "Aurora Nights". Komplett prozedural (eigenes Value-Noise, feste 8 Schichten), keine Textur.
- **Himmel**: warmes Leuchten am Horizont auf der Sonnenseite bei Sonnenauf-/-untergang, Mond-Halo, Wolken mit rötlicher Unterseite bei Sonnenuntergang; bei Regen wird der Himmel grauer, die Wolkendecke dichter und Sonne/Mond/Sterne/Polarlicht verschwinden.
- **Nebel in Himmelsfarbe**: entferntes Terrain verblasst jetzt genau in die Himmelsfarbe dahinter statt in Vanillas Nebelfarbe - keine sichtbare Kante mehr zwischen Landschaft und Himmel. Unter Wasser, in Lava, in Pulverschnee sowie bei Blindheit/Dunkelheit bleibt Vanillas Nebel; Blindheit/Dunkelheit verdunkeln jetzt auch den Himmel.
- **Nether und End** (neue Ordner `world-1/` und `world1/`): Vorher bekamen beide Dimensionen den Overworld-Himmel (im End einen blauen Taghimmel samt Sonne, im Nether einen Sternen-/Wolkenhimmel hinter dem Nebel) und Sonnenlicht/Schatten. Jetzt: **Nether** ohne Sonne, ohne Shadow-Programm und ohne jeden Schatten-Code (sollte Iris den Shadow-Pass dort dadurch komplett weglassen, spart das zusätzlich Leistung - das lässt sich nur im Spiel bestätigen), mit warmem Grundlicht und Vanillas Nebelfarbe im Hintergrund; **End** mit eigenem dunkelviolettem Sternenhimmel samt treibendem Schleier und fahlem violettem Licht von oben.
- **Mobs blitzen wieder rot auf**, wenn sie getroffen werden (und Creeper weiß vor der Explosion) - dieses Vanilla-Feedback (`entityColor`) ging vorher verloren.

## Automatisierter Multi-Agent-Review: gefundene und behobene Fehler

Diese Überarbeitung wurde zusätzlich durch einen mehrteiligen, automatisierten Review geprüft (fünf unabhängige Perspektiven - GLSL-Syntax/Portabilität, Koordinatenraum-/Mathematik-Korrektheit, Iris/OptiFine-`shaders.properties`-Konventionen, Lizenz-/Originalitäts-Check gegen ComplementaryReimagined, Regressions-Check der unveränderten Dateien -, jeder Fund danach gegengeprüft durch zusätzliche, unabhängige Verifizierer). Dabei wurden mehrere echte, teils schwerwiegende Fehler gefunden und behoben:

- **Schwerwiegend - Schatten wären nie sichtbar gewesen**: `shadowDistance` war in `common.glsl` fälschlich als `uniform float` deklariert, in der (falschen) Annahme, Iris/OptiFine würde diesen Wert automatisch als Laufzeit-Uniform bereitstellen. Tatsächlich ist `shadowDistance` - wie `shadowMapResolution` - ausschließlich eine vom Pack-Loader zur Ladezeit aus dem Quellcode gelesene `const`-GUI-Option, keine echte Uniform; ohne einen tatsächlichen Schreibzugriff blieb der Wert bei GLSLs Standardwert `0.0`. Das ließ `smoothstep(0.0, 0.0, distanz)` für jede sichtbare Fläche auf `1.0` auswerten (Division durch Null → +Infinity → geklemmt auf 1.0), wodurch `sampleShadow()` unabhängig vom eigentlichen Schatten-Sample-Ergebnis immer "voll beleuchtet" zurückgab - Schatten wären auf JEDEM Profil mit aktivierten Schatten (Low/Medium/High) unsichtbar geblieben, obwohl die Shadow Map weiterhin (nutzlos) gerendert worden wäre. Behoben durch denselben Single-Source-of-Truth-Fix, der bei `shadowMapResolution` bereits richtig gemacht wurde: `shadowDistance` ist jetzt eine einzige `const float` in `common.glsl`, nirgends mehr eine `uniform`.
- **Performance-Profile hätten Entity-Schatten nicht abgeschaltet**: `shadowEntities=...` stand direkt in den `profile.*`-Zeilen, ist aber eine rohe Iris/OptiFine-Direktive ohne zugehörige `#define`/`const`-GUI-Option - Profile können nur registrierte Optionen setzen, daher wurde dieser Wert beim Profilwechsel stillschweigend verworfen (durch Nachverfolgen des tatsächlichen Iris-Quellcodes bestätigt). Behoben nach demselben Muster wie in ComplementaryReimagined: `shadowEntities = false` steht jetzt unconditional außerhalb der Profile, gesteuert über die bereits registrierte `SHADOW_QUALITY`-Option.
- **Sichtbare Naht in den neuen Wolken**: Die Wolken-Rauschkoordinate wurde per `mod(pos, 4096.0)` gefaltet, um (nach einer Lehre aus diesem Projekt selbst, siehe `highperf-shader`) Präzisionsverlust bei sehr großen Weltkoordinaten zu vermeiden - das Rauschfeld ist an dieser Grenze aber nicht periodisch, wodurch alle 4096 Blöcke eine sichtbare Naht entstanden wäre. Nach genauerer Prüfung: bei der hier verwendeten Skalierung bleibt die Eingabe selbst am Rand der Minecraft-Weltgrenze weit im unproblematischen Bereich - das ursprüngliche Präzisionsproblem bestand für diese Skalierung gar nicht. Die `mod()`-Faltung wurde daher komplett entfernt.
- **Bloom hätte auf Low/Potato unnötig Leistung gekostet**: `colortex0MipmapEnabled = true` (löst pro Frame eine Mip-Chain-Neuberechnung aus) stand unconditional, obwohl es ausschließlich von `getBloom()` gebraucht wird, das auf Low/Potato bereits komplett wegkompiliert ist. Jetzt hinter denselben `ENABLE_BLOOM`-Schalter gestellt.
- **Kleinere Korrekturen**: ein irreführender Kommentar bei `getBloom()` (behauptete pauschal, "ein einzelnes Glowstone/Fackel-Licht" würde immer bloomen - das stimmt nur für große/sehr helle Flächen, nicht für kleine, isolierte Lichtquellen aus der Distanz, da die Mip-Mittelung vor der Schwellenwert-Prüfung passiert) wurde präzisiert; eine unbenannte, weithin öffentlich verbreitete Hash-Funktion (Dave Hoskins, "Hash without Sine") wurde nachträglich benannt, konsistent mit der bereits vorhandenen Namensnennung für die Dithering-Formel.

**Bewusst nicht behoben** (siehe "Bekannte bewusste Vereinfachungen" unten): ein einmal pro Stunde durchgehenden Spiels auftretendes, kurzes "Springen" der Wolkenanimation, verursacht durch `frameTimeCounter`s dokumentierten Reset auf 0 nach 3600 Sekunden - dasselbe, bereits vor dieser Überarbeitung im Sternenfeld und in den Wasserwellen vorhandene Verhalten, hier nur für die neuen Wolken übernommen statt neu verursacht. Eine robuste Lösung würde alle drei Effekte gleichzeitig umbauen und war für diesen fokussierten Bugfix-Durchgang zu riskant/groß angesetzt.

## Dritte Überarbeitung mit Blick auf ComplementaryReimagined

Wieder dieselbe Regel: **kein Code aus Complementary kopiert.** Angeschaut wurden nur, *welche* Effekte es dort gibt (Optionsliste, Programmliste), und ein paar Fakten über die Iris/OptiFine-Schnittstelle: welche Uniforms es gibt (`wetness`, `moonPhase`, `eyeBrightnessSmooth`), welche Werte `biome_precipitation` hat (0 = kein Niederschlag, 1 = Regen, 2 = Schnee), wie Dimensions-Ordner in `program.<ordner>/<programm>.enabled` angesprochen werden und welche Programme Iris für Blitze und Partikel sucht. Alles Folgende ist selbst geschrieben.

**Fehler behoben:**
- **POTATO hat im End trotzdem Schatten gerendert.** `program.shadow.enabled=SHADOW_ENABLED` gilt nur für `shaders/shadow.*`; das End hat mit `world1/shadow.*` ein eigenes Shadow-Programm, das weiterlief. Neu: `program.world1/shadow.enabled=SHADOW_ENABLED`.
- **Regen, Schnee und Partikel leuchteten nachts und in Höhlen.** Sie landeten im unbeleuchteten `gbuffers_textured` und blieben dadurch so hell wie am Tag. Neu ist `gbuffers_textured_lit` (das Programm, das Iris und OptiFine für Partikel und Wetter suchen): Partikel und Niederschlag bekommen jetzt Himmels-, Block- und Sonnenlicht samt Schatten. Partikel, die Vanilla selbst leuchten lässt (Flammen, Lavafunken, Endstab-Partikel, ...), glühen weiter. `gbuffers_textured` bleibt bewusst unbeleuchtet für Himmelsgeometrie, Leuchtfeuerstrahl, Spinnenaugen und Verzauberungsglanz.
- **Blitze sahen in Gewitternächten wie ein trübes, graublaues Band aus**, weil Iris sie mangels eigenem Programm wie einen Mob beleuchtete. Neu: `gbuffers_lightning` gibt den Blitz unbeleuchtet und mehrfach über 1,0 aus, sodass er im Bloom aufstrahlt.
- **Doppelte Vignette:** Vanilla dunkelt den Bildrand selbst ab, zusätzlich zur eigenen Vignette. Jetzt `vignette=false`, damit nur noch der Regler `VIGNETTE_STRENGTH` gilt.

**Neu:**
- **Lichtstrahlen** (`LIGHT_SHAFTS`, `LIGHT_SHAFT_SAMPLES`, `LIGHT_SHAFT_STRENGTH`): sichtbare Sonnen- und Mondstrahlen in der Luft, z. B. durch Baumkronen oder an einem Hügel vorbei bei Sonnenuntergang. `composite` geht für jeden Pixel in 8 (HIGH: 12) Schritten den Weg von der Kamera bis zum Objekt ab und prüft an jedem Schritt in der **Shadow Map**, ob dort Sonnenlicht hinkommt. Die beleuchteten Stücke streuen etwas Licht zur Kamera, am stärksten in Richtung Sonne (Henyey-Greenstein-Phasenfunktion). Deshalb geht es diesmal und früher nicht: Das Verfahren muss die Sonne nie auf den Bildschirm projizieren, funktioniert also auch, wenn sie hinter der Kamera steht. Am stärksten bei Sonnenauf- und -untergang, schwach mittags, ganz schwach nachts; aus bei Regen, unter Wasser, in Höhlen (über das geglättete Himmelslicht am Auge) und bei Blindheit. Nur im Overworld, nur mit Schatten, aus auf `LOW`/`POTATO`.
- **Wolkenschatten** (`CLOUD_SHADOWS`): Die Wolkenebene wirft große, langsam wandernde Schatten auf die Landschaft. Dafür liegt die Wolkenform jetzt als eine einzige Funktion (`cloudCoverage()`) in `common.glsl`, die Himmel und Beleuchtung gemeinsam nutzen, damit Schatten und Wolken immer zusammenpassen. Die Wolken-Optionen sind dafür von `sky.glsl` nach `common.glsl` umgezogen. Aus auf `LOW`/`POTATO`.
- **Nasser Boden und Pfützen** (`RAIN_PUDDLES`): Bei Regen werden Flächen unter freiem Himmel dunkler und satter. Auf nach oben zeigenden Flächen (nicht auf Pflanzen, Blättern oder leuchtenden Blöcken) bilden sich Pfützen, die den Himmel spiegeln, mit `WATER_SKY_REFLECTION` den echten Himmel samt Sonne und Wolken. Nach dem Regen trocknet der Boden langsam wieder (`wetness`, eingestellt über `wetnessHalflife`/`drynessHalflife`). Nass wird es nur dort, wo Regen wirklich hinkommt (volles Himmelslicht, unter Laub kaum noch), und nur in Biomen, in denen es regnet: Ein neues Custom-Uniform `rainBiome` in `shaders.properties` hält Wüsten, Savannen und Schneebiome trocken. `WATER_SKY_REFLECTION` steht dafür jetzt in `sky.glsl` statt in der Wasser-Datei. Ist die Option aus (`POTATO`), spiegeln Wasser und Pfützen den einfachen Himmelsverlauf statt einer flachen Einheitsfarbe; das kostet praktisch nichts.
- **Regenbogen** (`RAINBOWS`): Hört der Regen auf, während der Boden noch nass ist, steht gegenüber der Sonne ein Regenbogen (rot außen, violett innen, etwa 42° um den Gegenpunkt der Sonne). Gezeichnet wird nur sein Teil über dem Horizont: Bei tiefer Sonne steht er hoch, mittags verschwindet er, wie in echt. Er verblasst, während der Boden trocknet, und spiegelt sich auch in Wasser und Pfützen.
- **Mondphasen** (`MOON_PHASE_INFLUENCE`): Der Mond zeigt jetzt seine Phase von Vollmond bis Neumond, mit schwachem Erdschein auf der dunklen Seite und angedeuteten "Meeren". Mondlicht, Mond-Halo und Mondstrahlen werden zum Neumond hin schwächer, Neumond-Nächte sind also dunkler.
- **Geneigte Sonnenbahn** (`sunPathRotation`, Standard -30°): Die Sonne steht mittags nicht mehr genau senkrecht. Schatten haben dadurch den ganzen Tag eine Richtung, und Blockkanten flimmern weniger im Schatten. Bei 0° ist es wie vorher.
- **Unter Wasser** (`UNDERWATER_CAUSTICS`, `UNDERWATER_WOBBLE`): Ist der Kopf unter Wasser, zieht ein wanderndes Lichtnetz (Kaustiken) über alles, was Sonnenlicht abbekommt, und das Bild wabert leicht.
- **Leuchtende Erze** (`GLOWING_ORES`, standardmäßig **aus**): Die farbigen Kristalle von Eisen-, Kupfer-, Gold-, Redstone-, Lapis-, Smaragd- und Diamanterz (auch in Tiefenschiefer) glühen leicht und bloomen. Erkannt werden sie an der Sättigung: Stein und Tiefenschiefer sind grau, die Erzkristalle farbig. Nether-Erze bleiben außen vor, weil dort der rote Netherrack selbst farbig ist. Dafür gibt es die neue Block-ID 202 in `block.properties`.
- Auf `POTATO` ist jetzt auch `SHADOW_QUALITY=0` gesetzt, damit jedes Profil dieselben Optionen setzt. Optisch ändert das nichts, weil die Schatten dort aus sind.

## Vierte Überarbeitung: der große Umbau

Rückmeldung nach der dritten Runde: *"hat sich fast gar nichts verbessert"*. Das stimmt. Die dritte Runde brachte fast nur Effekte für bestimmte Situationen (Regen, Sonnenuntergang, unter Wasser, Mondphasen); bei normalem Tageslicht sah das Bild fast gleich aus. Diese Runde ändert deshalb das, was man **die ganze Zeit** sieht.

Eine 1:1-Kopie von Complementary ist nicht möglich. Seine Lizenz verbietet das Weitergeben veränderten Codes, und dieses Repo ist öffentlich. Wieder gilt also: **kein Code kopiert**, nur die großen Bausteine angeschaut, die Complementary so gut aussehen lassen, und selbst nachgebaut. Dafür bekommt Aurora Nights zum ersten Mal einen zusätzlichen Puffer (`colortex2`): Die Blöcke, Mobs, die Hand und das Wasser schreiben dort ihre Flächen-Normale, das Himmelslicht und einen Materialcode hinein. Damit können spätere Bildschirm-Pässe Effekte berechnen, die vorher technisch nicht gingen. Beleuchtet wird weiterhin direkt beim Zeichnen; das ist kein kompletter Umbau auf Deferred Rendering, der sich ohne Test im Spiel nicht verantworten ließe.

Jeder neue Effekt hat einen eigenen Schalter. Falls einer im Spiel Probleme macht, lässt er sich einzeln abschalten, ohne den ganzen Pack zu verlieren.

**Neu:**
- **Umgebungsverdeckung / SSAO** (`SSAO`, `SSAO_STRENGTH`): Ecken, Spalten, der Boden unter Bäumen und Mobs und Innenkanten werden weich dunkler. Das gibt Blöcken und Landschaft deutlich mehr Tiefe; vorher stand das in der Liste "bewusst nicht übernommen", weil der Normalen-Puffer fehlte. Ein neuer Pass `deferred` prüft für jeden Pixel 8 Punkte auf der Halbkugel über der Fläche gegen den Tiefenpuffer. `deferred1` glättet das Ergebnis tiefenbewusst, damit nichts über Kanten blutet, und wendet es an. Läuft vor Wasser und Glas, die Hand ist ausgenommen. Auf `LOW`/`POTATO` wird der ganze Pass übersprungen.
- **Wasser, neu gemacht:**
  - **Tiefenfärbung** (`WATER_FOG`, `WATER_FOG_DENSITY`): Aus den zwei Tiefenpuffern (mit und ohne Wasser) ergibt sich, wie weit der Blick durchs Wasser geht. Flaches Wasser ist jetzt klar und zeigt seinen Grund, tiefes wird dunkel blaugrün, beleuchtet vom Himmels- und Sonnenlicht dort. Die Wasseroberfläche selbst ist dafür durchsichtiger.
  - **Spiegelung der Landschaft** (`WATER_REFLECTIONS`, seit der fünften Überarbeitung `SCREEN_SPACE_REFLECTIONS`): Bäume, Hügel und Häuser am Ufer spiegeln sich jetzt im Wasser, nicht mehr nur der Himmel. Das ist Screen-Space-Reflection: Der gespiegelte Blickstrahl wird in wachsenden Schritten durchs Bild verfolgt, bis er hinter einer Fläche verschwindet, danach wird der Treffer mit vier Halbierungsschritten genau bestimmt. Was nicht im Bild ist, ersetzt der echte Himmel (bzw. in Höhlen die Wasserfarbe), zum Bildrand hin wird weich übergeblendet. Stärke nach Fresnel: flach über das Wasser geblickt spiegelt es stark, von oben kaum.
- **3D-Wolken** (`VOLUMETRIC_CLOUDS`): Statt einer flachen Ebene gibt es jetzt eine 56 Blöcke dicke Wolkenschicht, die in 14 Schritten durchlaufen wird. Jede Wolke hat eine gewölbte Oberseite über einer flacheren Basis und ausgefranste Ränder. Sie wird von der Sonne beleuchtet: helle Oberseiten, dunklere Unterseiten (ein Blick Richtung Sonne pro Schritt), leuchtende Ränder im Gegenlicht, golden bei Sonnenuntergang, grau bei Regen. Ferne Wolken verschwimmen mit dem Himmel. Form und Wind sind dieselben wie bei den Wolkenschatten. In Spiegelungen bleibt die günstige flache Ebene, sonst müsste jeder Wasserpixel die Wolken durchlaufen.
- **Himmel vor Wasser und Glas**: Der Himmel wird jetzt in `deferred1` gemalt, vor Wasser und Glas. Durchscheinende Blöcke vor dem Himmel zeigen dadurch den echten Himmel samt Wolken statt einer flachen Füllfarbe.
- **Überarbeitetes Licht**:
  - Vanillas eingebackene Flächenschattierung ist aus (`oldLighting=false`). Stattdessen gibt es eine eigene, weichere (`faceShade()`): Oberseiten bekommen das volle Himmels- und Fackellicht, Wände weniger, Unterseiten am wenigsten. Das Sonnenlicht kommt aus seiner echten Richtung, nicht mehr doppelt verdunkelt.
  - Wärmeres Sonnenlicht gegen kühleres Himmelslicht, mehr Kontrast zwischen Sonne und Schatten, neuer Regler `SUN_INTENSITY`.
  - Ein breiter, weicher Lichthof um die Sonne im Himmel.
- **Dunst in der Ferne** (`ATMOSPHERIC_FOG`): Nicht erst am Rand der Sichtweite, sondern schon ab mittlerer Entfernung legt sich ein dünner Schleier in Himmelsfarbe über die Landschaft. Dadurch wirken ferne Hügel ferner. Dichter bei Sonnenauf-/-untergang und Regen, nicht in Höhlen.

**Technisch wichtig:** In GLSL 1.20 schreibt `gl_FragColor` in **alle** gebundenen Puffer. Deshalb sagt jetzt jedes Programm per `/* DRAWBUFFERS:... */`, wohin es schreibt; sonst hätten z. B. Partikel die Normalen im neuen Puffer überschrieben. Außerdem ist Blending für `colortex2` in Terrain, Mobs, Hand und Wasser abgeschaltet (`blend.<programm>.colortex2=off`), damit halbtransparente Pixel keine Normalen vermischen. Das Prüfskript kontrolliert beides.

## Fünfte Überarbeitung: TAA und spiegelnde Blöcke

Auf Wunsch die beiden größten Lücken zum Beispiel-Shader, die nach der vierten Runde blieben. Wieder kein Code aus Complementary, nur dieselben bekannten Verfahren selbst umgesetzt.

**TAA - zeitliche Kantenglättung** (`TEMPORAL_AA`, `TAA_BLEND`, `TAA_SHARPNESS`):
- Jedes Bild wird um einen anderen Bruchteil eines Pixels verschoben gezeichnet (8 Positionen einer Halton-Folge; `taaJitter()` am Ende jedes gbuffers-Vertex-Shaders). Der neue Pass `composite2` mischt das aktuelle Bild mit dem gesammelten Verlauf der letzten Bilder (`colortex4`, wird nie gelöscht). Über ein paar Bilder bekommt so jeder Pixel Proben von mehreren Stellen: glatte Kanten, ruhige Blätter und Zäune.
- Damit der Verlauf an der richtigen Stelle gelesen wird, rechnet `composite2` jeden Pixel zurück: über die Tiefe zur Weltposition, korrigiert um die Kamerabewegung, durch die Kamera des letzten Bildes. Die Hand bleibt, wo sie ist.
- Gegen Geisterbilder (Mobs, Wellen, wechselndes Licht) wird der Verlauf auf den Farbbereich der 3×3-Nachbarschaft im aktuellen Bild begrenzt. Bei schneller Bewegung zählt das aktuelle Bild etwas mehr.
- Das Rauschen von Umgebungsverdeckung, 3D-Wolken, Lichtstrahlen und Spiegelungen ändert sich mit TAA jetzt jedes Bild (`effectDither()`). TAA mittelt es weg, statt ein festes Körnungsmuster stehen zu lassen.
- TAA macht das Bild minimal weicher; `final` schärft deshalb leicht nach (`TAA_SHARPNESS`).
- Auf `MEDIUM`/`HIGH` an, auf `LOW`/`POTATO` wird der ganze Pass übersprungen. FXAA ist jetzt in jedem Profil aus, lässt sich aber von Hand wieder einschalten (z. B. auf `LOW`).

**Spiegelnde Blöcke** (`REFLECTIVE_BLOCKS`):
- Vier neue Gruppen in `block.properties`, mit unterschiedlich starkem Glanz (`shineOfBlock()`):
  - **400**, leichter, weicher Schimmer: polierter Andesit, Diorit, Granit, Tiefenschiefer, Schwarzstein, Tuff und Basalt, glatter Stein, alle Quarzblöcke, Prismarinziegel und dunkler Prismarin, jeweils samt Stufen, Treppen und Mauern.
  - **401**, deutlich glänzend: Packeis, Blaueis, Obsidian, alle 16 glasierten Keramiken.
  - **402**, sehr glänzend: Diamant-, Smaragd- und Amethystblock.
  - **403**, Metall: Eisen-, Gold-, Netherit- und (nicht oxidierte) Kupferblöcke, Eisentür und -falltür, Eisengitter, Ketten, Ambosse, Kessel, Wägeplatten.
- Gespiegelt wird in `composite` mit demselben Verfahren wie beim Wasser: die Landschaft per Screen-Space-Reflection, sonst der Himmel. Glänzende Steine spiegeln geradeaus kaum und zum flachen Blickwinkel hin stark (Fresnel). **Metalle** spiegeln auch geradeaus kräftig und **färben ihre Spiegelung in ihrer eigenen Farbe**: Gold spiegelt golden, Kupfer kupfern.
- Rauere Flächen (polierter Stein) spiegeln unscharf: Mit TAA wird der Spiegelstrahl jedes Bild zufällig etwas gekippt, und TAA mittelt das zu einem weichen Spiegelbild.
- **Pfützen** gehen jetzt denselben Weg. Sie spiegeln also auch Bäume und Häuser, nicht nur den Himmel.
- Auf `LOW` spiegeln die Blöcke nur den Himmel (ohne Screen-Space-Reflection), auf `POTATO` ist es aus.
- Die Option `WATER_REFLECTIONS` heißt jetzt `SCREEN_SPACE_REFLECTIONS`, weil sie nicht mehr nur fürs Wasser gilt.

## Sechste Überarbeitung: ein Himmel wie in Minecraft

Wunsch: *"mach den Himmel viel mehr minecraftmäßig"*. Der Himmel war bisher bewusst realistisch: runde Sonne, runder Mond, weiche Wolken, eigene Farbverläufe. Jetzt sieht er standardmäßig wie der Minecraft-Himmel aus, nur schöner beleuchtet. Der alte Himmel bleibt über zwei Optionen erhalten. Neue Programme oder Puffer gibt es dafür nicht, alles steckt in `lib/common.glsl` und `lib/sky.glsl`.

- **Minecrafts eigene Himmelsfarben** (`VANILLA_SKY_COLORS`): Oben kommt Minecrafts Himmelsfarbe (`skyColor`), am Horizont seine Nebelfarbe (`fogColor`). Damit hat jedes Biom wieder seinen eigenen Himmel, Regen verdunkelt ihn wie im Original, und der Nebel über der Landschaft passt genau dazu. Damit das typische Minecraft-Blau nicht von Belichtung, ACES-Tonemapping und Sättigung in `composite1` blass gewaschen wird, rechnet `fromDisplay()` diese drei Schritte vorher rückwärts heraus. Die Farbe kommt so auf dem Bildschirm an, wie Minecraft sie zeigt, nur knapp unter der Bloom-Schwelle gedeckelt, damit der Himmel nicht das ganze Bild überstrahlt. Bei Sonnenauf- und -untergang kommt ein warmer Schein auf der Sonnenseite dazu, wie Minecrafts Sonnenaufgangs-Fächer. Unter Wasser, in Lava und in Pulverschnee, wo Minecrafts Nebelfarbe die Farbe des Materials annimmt, übernimmt wieder der eigene Verlauf.
- **Eckige, pixelige Sonne und eckiger Mond** (`SKY_STYLE` = 0):
  - Die Sonne ist ein großes Quadrat aus 8×8 "Texeln" mit etwas wärmerem Rand und einem schwachen quadratischen Schein.
  - Der Mond ist ein kleineres 8×8-Quadrat mit ein paar dunkleren "Krater"-Texeln. Seine Phase wächst und schrumpft **spaltenweise**, wie bei Minecrafts Mondtextur.
  - Beide sind entlang ihrer Bahn ausgerichtet, auch bei geneigter Sonnenbahn.
  - Ihre Kanten sind genau einen Bildschirmpixel weich. Zusätzlich bekommt der Himmel jetzt denselben TAA-Versatz wie die Geometrie, sodass TAA auch Sonne, Mond und Wolkenkanten glättet.
  - Sonne und Mond verschwinden jetzt unter dem Horizont, statt beim Blick von einem Berg hinab darunter aufzutauchen.
- **Eckige Sterne:** kleine, ruhige Quadrate in leicht unterschiedlicher Helligkeit, ohne Funkeln.
- **Blockige Wolken** (`CLOUD_STYLE` = 0): wie Minecrafts Wolken eine 4 Blöcke dicke Schicht aus 12×12-Feldern, die langsam Richtung +X zieht.
  - Eine grobe Rauschfunktion fasst die Felder zu unregelmäßigen Wolken von ein paar Feldern Größe zusammen, Regen füllt den Himmel.
  - Gezeichnet wird, indem der Blickstrahl Feld für Feld durch die Schicht läuft. Die erste Wolkenzelle bestimmt, welche Seite man sieht, und jede Seite bekommt Minecrafts flache Schattierung: oben hell, Seiten mittel, unten dunkler.
  - Weiß am Tag, warm bei Sonnenuntergang, dunkel in der Nacht, grau bei Regen.
  - Weil das billig ist, erscheinen dieselben blockigen Wolken auch in Spiegelungen.
  - Die **Wolkenschatten** sind jetzt entsprechend quadratisch und passen genau zu den Wolken darüber.
- **Zurück zum realistischen Himmel:** `SKY_STYLE` = 1 (runde Sonne und runder Mond, funkelnde Sterne), `CLOUD_STYLE` = 1 (weiche Wolken; mit `VOLUMETRIC_CLOUDS` in 3D), `VANILLA_SKY_COLORS` aus (eigener Farbverlauf). `VOLUMETRIC_CLOUDS` wirkt nur noch beim weichen Wolken-Stil.

Das Prüfskript kompiliert jetzt zusätzlich einen Lauf "ALT" (MEDIUM plus realistischer Himmel, weiche Wolken, FXAA und leuchtende Erze). So wird auch Code geprüft, den kein Profil einschaltet.

## Ehrlicher Hinweis zum Teststatus

Ich konnte diesen Shader in dieser Umgebung **nicht in Minecraft/Iris kompilieren oder testen** (kein Spiel/keine GPU hier verfügbar) - das gilt auch für diese Überarbeitung. Der Code wurde sorgfältig von Hand nach den bekannten Iris/OptiFine-Konventionen geschrieben, bewusst auf GLSL-1.20-sichere Funktionen beschränkt (kein `texelFetch`/`texture2DLod` in Fragment-Shadern, die auf manchen Treibern - gerade den älteren/schwächeren GPUs, um die es hier ja geht - Probleme machen können), und zusätzlich durch den oben beschriebenen automatisierten Multi-Agent-Review geprüft, der mehrere echte Fehler fand und die anschließend behoben wurden - aber auch das ersetzt keinen echten Compile-/Rendertest.

**Neu seit der zweiten Überarbeitung:** Jetzt wurde tatsächlich kompiliert - nicht im Spiel, aber mit dem offiziellen Khronos-Referenz-Compiler **glslangValidator 16.6.0**. Ein kleines Prüfskript löst dafür die Iris-`#include`s auf, wendet jedes der vier Profile genau so auf den Quelltext an, wie Iris es tut (Schalter aus-/einkommentieren, Werte ersetzen), und kompiliert dann jede Stufe in allen drei Dimensionen: **58 Stufen × 4 Profile = 232 Kompilierungen, alle fehlerfrei und ohne Warnungen.** Zusätzlich wurde im vorverarbeiteten Code stichprobenartig geprüft, dass die richtigen Pfade aktiv sind (Nether ohne Schatten-Code, Polarlicht nur ab `MEDIUM`, kein Wind auf `POTATO`, ...).

**Stand dritte Überarbeitung:** Das Prüfskript wurde erweitert und läuft fehlerfrei durch: Wrapper in allen drei Dimensionen, jede Option genau einmal deklariert und in ihrer eigenen Datei per `#ifdef` abgefragt, alle Profile setzen dieselben, gültigen Optionen, und die Datei-Standardwerte entsprechen `MEDIUM`. **Die Kompilierung mit glslang steht für diese Runde noch aus**; die 232 Kompilierungen oben beziehen sich auf den Code der zweiten Überarbeitung.

**Stand vierte Überarbeitung:** Das Prüfskript kontrolliert jetzt zusätzlich, dass jedes Programm seine Ausgabe-Puffer angibt und nicht darüber hinaus schreibt. Es läuft fehlerfrei: 82 Stufen, 50 Optionen. **Kompiliert ist auch diese Runde noch nicht.** Bitte vor dem ersten Laden im Spiel einmal das glslang-Prüfskript laufen lassen.

**Stand fünfte Überarbeitung:** Das Prüfskript läuft fehlerfrei (88 Stufen, 54 Optionen). **Kompiliert ist weiterhin nichts seit der zweiten Überarbeitung.**

**Stand sechste Überarbeitung:** Das Prüfskript läuft fehlerfrei (88 Stufen, 57 Optionen, 5 Profil-Läufe plus "ALT"). Kompiliert ist es noch nicht.

Was das **nicht** abdeckt: alles, was nur Iris selbst weiß - ob `block.properties` so gelesen wird wie gedacht, ob jede Option im Menü auftaucht, ob die Uniforms (`heldBlockLightValue`, `entityColor`, `darknessFactor`, ...) in Minecraft 26.3 befüllt werden, und natürlich wie es aussieht und wie schnell es läuft.

**Bitte beim ersten Laden im Spiel kurz gegenchecken:**
- Lädt der Pack ohne Fehlermeldung im Shader-Auswahlmenü?
- Falls Iris/OptiFine eine Fehlermeldung mit Datei + Zeilennummer zeigt: mir die Meldung schicken, dann behebe ich es gezielt.
- Sehen Schatten, Himmel/Wolken/Sterne und Wasser wie erwartet aus?
- Wehen Gras und Blätter (und ihre Schatten)? Glühen Lava, Glowstone und Fackelflammen? Leuchtet eine Fackel in der Hand die Umgebung aus?
- Sieht man nachts (klares Wetter, Profil `MEDIUM`/`HIGH`) Richtung Norden Polarlichter?
- Haben Nether und End ihren eigenen Look (kein blauer Himmel/keine Sonne im End)?
- Läuft es mit `POTATO`/`LOW` auf schwacher Hardware spürbar besser als vorher?
- *Dritte Überarbeitung:* Sieht man bei Sonnenuntergang Lichtstrahlen durch Bäume (`MEDIUM`/`HIGH`), ohne dass in Höhlen heller Nebel entsteht? Wandern Wolkenschatten über die Landschaft?
- Wird der Boden bei Regen dunkel, bilden sich Pfützen (nicht in Wüsten/Schneebiomen), und steht nach dem Regen bei tiefer Sonne ein Regenbogen gegenüber der Sonne? (`/weather rain`, dann `/weather clear`.)
- Hat der Mond Phasen (`/time set` auf aufeinanderfolgende Nächte)? Sind Regen, Rauch und Partikel nachts nicht mehr hell? Leuchten Blitze hell auf?
- Unter Wasser: Wabert das Bild, und laufen Lichtnetze über den Grund?
- *Vierte Überarbeitung:* Sind Ecken und Spalten weich abgedunkelt (SSAO), ohne helle/dunkle Ränder um Objekte? Spiegeln sich Ufer und Bäume im Wasser, ist flaches Wasser klar und tiefes dunkel? Sehen die 3D-Wolken nach Wolken aus (nicht nach Rauschen oder Streifen)? Wie läuft `MEDIUM` jetzt im Vergleich zu vorher?
- *Fünfte Überarbeitung:* Sind Kanten und Blätter mit TAA ruhig, ohne Schlieren hinter laufenden Mobs oder beim schnellen Umdrehen? Ist das Bild nicht zu weich (sonst `TAA_SHARPNESS` hoch)? Glänzen Quarz, Eis, Gold- und Eisenblöcke, und spiegelt Gold golden?
- *Sechste Überarbeitung:* Ist der Himmel Minecraft-blau (und z. B. in Wüste, Dschungel und Sumpf jeweils anders)? Sind Sonne und Mond eckig und mit sauberen Kanten, hat der Mond Phasen? Sehen die blockigen Wolken wie Minecraft-Wolken aus, und passen die Wolkenschatten darunter?

## Bekannte bewusste Vereinfachungen

- Farbige/transluzente Schatten (z. B. getöntes Licht durch Buntglas/Blätter) sind nicht implementiert, nur harte Sonnen-/Mond-Schatten mit weichen Kanten (PCF).
- Pfützen spiegeln nur den Himmel, keine Landschaft, und liegen nur auf nach oben zeigenden Flächen. Ob es irgendwo nass wird, entscheidet das Biom, in dem der Spieler steht: Wer bei Regen aus einem Wald in eine Wüste schaut, sieht dort auch nassen Sand.
- Sollte Iris/OptiFine das Custom-Uniform `rainBiome` nicht liefern, bleibt es 0. Dann gibt es weder Pfützen noch Regenbogen; kaputt aussehen kann dadurch aber nichts.
- Kaustiken gibt es nur, wenn der Kopf selbst unter Wasser ist. Ein Forward-Renderer weiß beim Zeichnen eines Seebodens nicht, ob darüber Wasser liegt, deshalb bekommt der Grund eines Sees von oben gesehen keine Kaustiken.
- Lichtstrahlen gibt es nur im Overworld und nur, so weit die Shadow Map reicht (etwa 85 % von `shadowDistance`).
- Unter OptiFine laufen Blitze vermutlich weiter über `gbuffers_entities` (`gbuffers_lightning` ist ein Iris-Programm) und bleiben dort so matt wie vorher.
- Polarlichter erscheinen in **jeder** klaren Nacht (nicht nur in kalten Biomen o. ä.); wer sie seltener/schwächer will, nimmt `AURORA_BRIGHTNESS` zurück oder schaltet `ENABLE_AURORA` ab.
- Wasser spiegelt die Landschaft nur, soweit sie im Bild ist (Screen-Space-Reflection): Was hinter der Kamera oder außerhalb des Bildes liegt, wird durch den Himmel ersetzt, und am Bildrand blendet die Spiegelung aus. Von unter Wasser gibt es keine Spiegelung an der Oberfläche. Pfützen spiegeln weiterhin nur den Himmel.
- Die Umgebungsverdeckung arbeitet nur mit dem, was im Bild ist; an Bildrändern und hinter dünnen Objekten kann sie leicht flackern oder fehlen. Ohne TAA ist sie mit nur 8 Proben etwas körnig, die Glättung in `deferred1` mildert das.
- Wolken (blockig wie 3D) werden nur hinter dem Himmel gezeichnet: Ein Berg, der in die Wolkenschicht ragt, steht immer vor den Wolken.
- Sonne und Mond sind gezeichnet, nicht Minecrafts Texturen: Ressourcenpakete, die Sonne oder Mond ändern, wirken sich darauf nicht aus. Die Himmelsfarben dagegen kommen direkt aus dem Spiel. Sie hängen davon ab, dass Iris/OptiFine `skyColor` und `fogColor` liefern, und landen wegen der Bloom-Deckelung etwas dunkler als im Original auf dem Bildschirm.
- TAA kennt keine eigenen Bewegungsvektoren für Mobs, Wellen oder Partikel. Dort verhindert nur das Begrenzen auf die Nachbarfarben Schlieren, was bei schnellen, kontrastreichen Bewegungen nicht immer ganz reicht. Regen und Partikel können mit TAA etwas blasser wirken.
- Spiegelnde Blöcke spiegeln wie Wasser nur, was im Bild ist. Glas, Eis (das durchsichtige) und Erze spiegeln nicht; die Liste in `block.properties` lässt sich leicht erweitern.
- Im Nether gibt es kein direktes Licht, nur ein warmes Grundlicht plus Block-/Lavalicht - er kann dadurch abseits von Lichtquellen dunkler wirken als in Vanilla.
- Gegenstände in der Hand leuchten nicht selbst (eine Fackel in der Hand beleuchtet die Umgebung, ihre Flamme glüht aber nicht wie die einer platzierten Fackel).
- Die Wolkenebene ist eine einzelne flache, animierte Rauschebene auf fester Welt-Höhe (`CLOUD_HEIGHT`) - kein echtes 3D-Volumen, und vor allem für den Blick von unten (dem Normalfall) gedacht. Ihr Schatten (`CLOUD_SHADOWS`) ist entsprechend ein flacher, weicher Schatten ohne Tiefe.
- Nach exakt einer Stunde durchgehenden Spiels (ohne Neuladen/Dimensionswechsel dazwischen) kann die Wolkenanimation kurz springen - `frameTimeCounter` wird von Iris/OptiFine alle 3600 Sekunden auf 0 zurückgesetzt; dasselbe gilt für Sternenfeld, Wasserwellen, wehende Pflanzen, Polarlicht, Wolkenschatten und Kaustiken (ein einzelner kurzer Ruck, danach läuft alles normal weiter).
