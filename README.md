# Aurora Nights

Ein realistischer, aber bewusst "minecraftiger" Shader für **Minecraft Java Edition 26.2**, gebaut für **Iris** (empfohlen) oder **OptiFine**.

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
- **neu:** wehende Gräser, Blumen, Getreide und Blätter (auch ihre Schatten wehen mit), weiches Pflanzenlicht, leuchtende Blöcke (Lava, Glowstone, Fackelflammen, Laternen, ...), Licht aus der Hand, kein Sonnenlicht mehr in Höhlen, echte Himmelsspiegelung im Wasser, **Polarlichter** am Nachthimmel, Nebel in der Farbe des Himmels sowie eigene Looks für **Nether** und **End** (Details im Abschnitt "Zweite Überarbeitung" unten)

## Installation

1. Diesen gesamten Ordner (bzw. ein ZIP davon) nach `.minecraft/shaderpacks/` kopieren, z. B. als `AuroraNights` bzw. `AuroraNights.zip`.
   - Wichtig ist, dass `pack.mcmeta` und der `shaders/`-Ordner direkt in diesem kopierten Ordner liegen (nicht in einem Unterordner).
2. [Iris](https://irisshaders.net/) installieren (empfohlen) oder OptiFine verwenden.
3. Im Spiel: Video-Einstellungen → Shader Pack → **AuroraNights** auswählen.
4. Bei schwacher/alter GPU: als Erstes oben im Options-Menü das **Profile**-Dropdown auf `POTATO` oder `LOW` stellen (siehe unten). Feintuning danach wie gewohnt über *Shader Options*: Sterndichte/-helligkeit, Wellenhöhe, Schattenweichheit, Belichtung, Sättigung, Bloom, Vignette, Wolken, Polarlicht-Helligkeit, Wind-Stärke/-Tempo, Leuchtstärke der Blöcke, Licht aus der Hand.

## Performance-Profile

Ganz oben in den Shader Options gibt es ein **Profile**-Dropdown mit vier Stufen. Es schaltet nur die tatsächlich performance-relevanten Optionen um; rein optische Regler (Farben, Wellenhöhe, Sternhelligkeit, Belichtung, Leuchtstärke, ...) bleiben davon unberührt und lassen sich weiterhin unabhängig einstellen:

| Profil | Schatten | Schattenreichweite/-auflösung | Wolken | Polarlicht | Wehende Pflanzen | Wasser-Himmelsspiegelung | Bloom | Kantenglättung |
|---|---|---|---|---|---|---|---|---|
| **POTATO** | **komplett aus** (kompletter Shadow-Pass wird übersprungen - der größte Performance-Hebel) | - | aus | aus | aus | aus | aus | aus |
| **LOW** | an, 1 Tap (billigste Stufe) | 96 Blöcke / 1024px | an | aus | an | an | aus | aus |
| **MEDIUM** *(Standard)* | an, 5 Taps | 160 Blöcke / 2048px | an | an | an | an | an | an |
| **HIGH** | an, 9 Taps | 200 Blöcke / 3072px | an | an | an | an | an | an |

Wichtig: `POTATO` deaktiviert die Schatten nicht nur optisch, sondern über `program.shadow.enabled=SHADOW_ENABLED` in `shaders.properties` den **kompletten Shadow-Map-Renderdurchlauf** - das ist mit Abstand der größte Performance-Hebel für schwache/alte GPUs (integrierte Grafik, alte Notebooks, ...), nicht nur ein optisches Weglassen des Effekts.

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
    gbuffers_basic_* / gbuffers_textured_*  # einfache Fallbacks (Partikel, Auswahlbox, Himmel-Grundgeometrie)
    composite_*.glsl        # malt den Himmel (in HDR, ungetonemapped)
    composite1_*.glsl       # Bloom (Mip-Chain-Trick) + Belichtung/ACES-Tonemapping/Sättigung
    final_*.glsl            # Kantenglättung, Vignette, Dithering
  *.vsh / *.fsh           # Overworld: 5-zeilige Wrapper (#version, AURORA_WORLD 0, #include program/...)
  world-1/*.vsh / *.fsh   # Nether: dieselben Wrapper mit AURORA_WORLD -1 (ohne Shadow-Pass)
  world1/*.vsh / *.fsh    # End: dieselben Wrapper mit AURORA_WORLD 1
```

**Wichtig beim Weiterbearbeiten:** Code immer in `program/` bzw. `lib/` ändern, nicht in den Wrapper-Dateien. Die Wrapper gibt es, weil Iris/OptiFine einen Dimensions-Ordner (`world-1/`, `world1/`) als **komplett eigenständiges** Programm-Set laden - fehlende Dateien werden dort *nicht* aus `shaders/` nachgeladen (dieselbe Erfahrung wie bei `highperf-shader`). So gibt es den Code trotzdem nur einmal.

Nicht enthaltene Programme (z. B. `gbuffers_skybasic`, `gbuffers_weather`) fallen automatisch auf `gbuffers_basic`/`gbuffers_textured` zurück (Iris/OptiFine-Standardverhalten) - der Himmel wird davon unabhängig komplett von `composite.fsh` neu gezeichnet. Vanillas eigene Wolken werden über `clouds=off` in `shaders.properties` ausgeblendet, damit sie sich nicht mit der neuen, selbst gemalten Wolkenebene überlagern.

## Was sich mit Blick auf ComplementaryReimagined geändert hat

Auf Wunsch wurde `ComplementaryReimagined_r5.9.3/` (ein sehr großer, deferred-gerenderter Shader mit eigener Voxel-Global-Illumination, SSR, TAA, vollem PBR-Materialsystem, ...) als Referenz für Ideen herangezogen. Wichtig dabei: **es wurde kein Code von dort kopiert.** Complementary steht unter einer eigenen Lizenz (`ComplementaryReimagined_r5.9.3/License.txt`), die eine Weiterverbreitung/Bearbeitung ihres Codes nur unter engen Bedingungen erlaubt (u. a. sichtbare Namensnennung, unveränderte Lizenzdatei, deutlich abweichender Look) - und selbst ohne diese Lizenz wäre ihr Code (deferred, mit einem Dutzend zusätzlicher Buffer, SSBOs zur Voxelisierung, ...) technisch gar nicht in Aurora Nights' viel simplerem Forward-Renderer lauffähig gewesen. Stattdessen wurden nur allgemeine, in der Shader-Community verbreitete **Techniken** studiert und für Aurora Nights komplett neu, im eigenen Stil und in der eigenen Architektur implementiert:

- **Performance-Profile** (`profile.POTATO/LOW/MEDIUM/HIGH` in `shaders.properties`) - dasselbe Grundprinzip wie Complementarys eigenes Profil-System, aber mit eigenen, viel kleineren Werten passend zu Aurora Nights' simplerem Feature-Set.
- **Hardware-gefilterte Schatten** (`sampler2DShadow` + `shadow2D()` + `shadowHardwareFiltering`) statt manueller `texture2D`-Tiefenvergleiche - eine Standard-Iris/OptiFine-API, kein Complementary-Code, aber der gleiche Kerntrick: jeder Sample-Tap bekommt "gratis" eine bilineare 2×2-Filterung von der GPU.
- **Mip-basiertes Bloom**: `colortex0` ist jetzt als HDR-Puffer deklariert (`R11F_G11F_B10F`, gleich viele Bits wie vorher, nur anders verteilt) und `composite1.fsh` liest zwei Mip-Stufen davon (`texture2D(colortex0, uv, bias)`, der GLSL-1.20-fragmentshader-sichere Weg für einen expliziten LOD-Bias) statt eines manuellen 5×5-Weichzeichners mit 25 Texturzugriffen. Günstiger *und* mit weicherem Ergebnis.
- **Eine einfache 2D-Wolkenebene** (prozedurales Value-Noise/FBM, komplett selbst geschrieben, keine Textur nötig) statt echter, teurer volumetrischer Wolken.
- **Eine leichte, selbst geschriebene Kantenglättung** nach dem öffentlich dokumentierten FXAA-Prinzip (Timothy Lottes/NVIDIA-Whitepaper) - bewusst vereinfacht (keine iterative Kantenende-Suche) für Performance auf schwacher Hardware.
- **Dithering** über die weit verbreitete "Interleaved Gradient Noise"-Formel (Jimenez 2014) gegen Banding im Himmel/Bloom.

**Bewusst nicht übernommen** (zu teuer und/oder zu riskant für eine "auch auf schwacher GPU"-Anforderung, und architektonisch nicht ohne einen kompletten Umbau auf Deferred Rendering möglich):
- Echtes SSAO (bräuchte einen eigenen Normalen-Buffer, den dieser Forward-Renderer nicht hat).
- TAA (bräuchte Motion Vectors + History-Buffer + Reprojection - mehr Architektur-Risiko und potenziell mehr, nicht weniger, Kosten auf schwacher Hardware als das jetzt ergänzte FXAA).
- Voxel-basierte Global Illumination / farbige Lichtausbreitung / Screen-Space-Reflections.
- Echte volumetrische Wolken und Godrays/Lichtschächte - wurden erwogen, aber wegen des Risikos einer fehlerhaften Sonnen-Bildschirmprojektion (die Kamera kann hinter der Sonne stehen, was die Perspektivteilung entarten lässt) in dieser Umgebung ohne Testmöglichkeit bewusst weggelassen.
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

## Ehrlicher Hinweis zum Teststatus

Ich konnte diesen Shader in dieser Umgebung **nicht in Minecraft/Iris kompilieren oder testen** (kein Spiel/keine GPU hier verfügbar) - das gilt auch für diese Überarbeitung. Der Code wurde sorgfältig von Hand nach den bekannten Iris/OptiFine-Konventionen geschrieben, bewusst auf GLSL-1.20-sichere Funktionen beschränkt (kein `texelFetch`/`texture2DLod` in Fragment-Shadern, die auf manchen Treibern - gerade den älteren/schwächeren GPUs, um die es hier ja geht - Probleme machen können), und zusätzlich durch den oben beschriebenen automatisierten Multi-Agent-Review geprüft, der mehrere echte Fehler fand und die anschließend behoben wurden - aber auch das ersetzt keinen echten Compile-/Rendertest.

**Neu seit der zweiten Überarbeitung:** Jetzt wurde tatsächlich kompiliert - nicht im Spiel, aber mit dem offiziellen Khronos-Referenz-Compiler **glslangValidator 16.6.0**. Ein kleines Prüfskript löst dafür die Iris-`#include`s auf, wendet jedes der vier Profile genau so auf den Quelltext an, wie Iris es tut (Schalter aus-/einkommentieren, Werte ersetzen), und kompiliert dann jede Stufe in allen drei Dimensionen: **58 Stufen × 4 Profile = 232 Kompilierungen, alle fehlerfrei und ohne Warnungen.** Zusätzlich wurde im vorverarbeiteten Code stichprobenartig geprüft, dass die richtigen Pfade aktiv sind (Nether ohne Schatten-Code, Polarlicht nur ab `MEDIUM`, kein Wind auf `POTATO`, ...).

Was das **nicht** abdeckt: alles, was nur Iris selbst weiß - ob `block.properties` so gelesen wird wie gedacht, ob jede Option im Menü auftaucht, ob die Uniforms (`heldBlockLightValue`, `entityColor`, `darknessFactor`, ...) in Minecraft 26.2 befüllt werden, und natürlich wie es aussieht und wie schnell es läuft.

**Bitte beim ersten Laden im Spiel kurz gegenchecken:**
- Lädt der Pack ohne Fehlermeldung im Shader-Auswahlmenü?
- Falls Iris/OptiFine eine Fehlermeldung mit Datei + Zeilennummer zeigt: mir die Meldung schicken, dann behebe ich es gezielt.
- Sehen Schatten, Himmel/Wolken/Sterne und Wasser wie erwartet aus?
- Wehen Gras und Blätter (und ihre Schatten)? Glühen Lava, Glowstone und Fackelflammen? Leuchtet eine Fackel in der Hand die Umgebung aus?
- Sieht man nachts (klares Wetter, Profil `MEDIUM`/`HIGH`) Richtung Norden Polarlichter?
- Haben Nether und End ihren eigenen Look (kein blauer Himmel/keine Sonne im End)?
- Läuft es mit `POTATO`/`LOW` auf schwacher Hardware spürbar besser als vorher?

## Bekannte bewusste Vereinfachungen

- Farbige/transluzente Schatten (z. B. getöntes Licht durch Buntglas/Blätter) sind nicht implementiert, nur harte Sonnen-/Mond-Schatten mit weichen Kanten (PCF).
- Item-Entities/Mobs bekommen keinen speziellen "Hurt-Flash"-Overlay-Effekt, sondern nur das normale Beleuchtungsmodell.
- Regen dimmt/entsättigt die Beleuchtung leicht, es gibt aber keine nassen Oberflächen-Reflexionen.
- Polarlichter erscheinen in **jeder** klaren Nacht (nicht nur in kalten Biomen o. ä.); wer sie seltener/schwächer will, nimmt `AURORA_BRIGHTNESS` zurück oder schaltet `ENABLE_AURORA` ab.
- Das Wasser spiegelt nur den Himmel, keine Landschaft (dafür bräuchte es Screen-Space-Reflections). Im End spiegelt Wasser gar nicht, weil das End kein Himmelslicht hat, an dem die Spiegelung hängt.
- Im Nether gibt es kein direktes Licht, nur ein warmes Grundlicht plus Block-/Lavalicht - er kann dadurch abseits von Lichtquellen dunkler wirken als in Vanilla.
- Gegenstände in der Hand leuchten nicht selbst (eine Fackel in der Hand beleuchtet die Umgebung, ihre Flamme glüht aber nicht wie die einer platzierten Fackel).
- Die Wolkenebene ist eine einzelne flache, animierte Rauschebene auf fester Welt-Höhe (`CLOUD_HEIGHT`) - kein echtes 3D-Volumen, wirft keinen Schatten, und ist vor allem für den Blick von unten (dem Normalfall) gedacht.
- Nach exakt einer Stunde durchgehenden Spiels (ohne Neuladen/Dimensionswechsel dazwischen) kann die Wolkenanimation kurz springen - `frameTimeCounter` wird von Iris/OptiFine alle 3600 Sekunden auf 0 zurückgesetzt; dasselbe gilt für Sternenfeld, Wasserwellen und jetzt auch für wehende Pflanzen und Polarlicht (ein einzelner kurzer Ruck, danach läuft alles normal weiter).
