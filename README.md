# Aurora Nights

Ein realistischer, aber bewusst "minecraftiger" Shader für **Minecraft Java Edition 26.2**, gebaut für **Iris** (empfohlen) oder **OptiFine**.

Fokus:
- weiche Richtungsschatten (Sonne/Mond) über eine echte Shadow Map
- ein selbst gemalter, dynamischer Himmel mit sanftem Tag/Nacht/Sonnenuntergangs-Verlauf
- ein **funkelndes, prozedurales Sternenfeld** bei Nacht
- Wasser mit animierten Wellen, Spiegel-Highlight und Fresnel-Reflexion
- warmes Fackellicht, kühles Himmelslicht, sanftes Bloom, Filmic-Tonemapping und dezente Vignette

## Installation

1. Diesen gesamten Ordner (bzw. ein ZIP davon) nach `.minecraft/shaderpacks/` kopieren, z. B. als `AuroraNights` bzw. `AuroraNights.zip`.
   - Wichtig ist, dass `pack.mcmeta` und der `shaders/`-Ordner direkt in diesem kopierten Ordner liegen (nicht in einem Unterordner).
2. [Iris](https://irisshaders.net/) installieren (empfohlen) oder OptiFine verwenden.
3. Im Spiel: Video-Einstellungen → Shader Pack → **AuroraNights** auswählen.
4. Feintuning über *Shader Options* im selben Menü: Sterndichte/-helligkeit, Wellenhöhe, Schattenweichheit, Belichtung, Sättigung, Bloom, Vignette.

## Struktur

```
pack.mcmeta
shaders/
  shaders.properties
  lib/common.glsl        # gemeinsame Uniforms, Beleuchtungsmodell, Himmel/Sterne-Funktionen
  shadow.vsh / .fsh       # Shadow Map
  gbuffers_terrain.*      # Blöcke/Terrain
  gbuffers_water.*        # Wasser (Wellen, Specular, Fresnel)
  gbuffers_entities.*     # Mobs/Spieler
  gbuffers_hand.*         # Item/Block in der Hand
  gbuffers_basic.* / gbuffers_textured.*  # einfache Fallbacks (Partikel, Auswahlbox, Himmel-Grundgeometrie)
  composite.*             # malt den Himmel + Sterne, einfaches Bloom
  final.*                 # Tonemapping, Sättigung, Vignette
```

Nicht enthaltene Programme (z. B. `gbuffers_skybasic`, `gbuffers_weather`) fallen automatisch auf `gbuffers_basic`/`gbuffers_textured` zurück (Iris/OptiFine-Standardverhalten) — der Himmel wird davon unabhängig komplett von `composite.fsh` neu gezeichnet.

## Ehrlicher Hinweis zum Teststatus

Ich konnte diesen Shader in dieser Umgebung **nicht in Minecraft/Iris kompilieren oder testen** (kein Spiel/keine GPU hier verfügbar). Der Code wurde sorgfältig von Hand nach den bekannten Iris/OptiFine-Konventionen geschrieben und zusätzlich durch mehrere unabhängige Review-Durchgänge auf Konsistenz (Varyings, Koordinatenräume, API-Nutzung, GLSL-Syntax) geprüft — aber das ersetzt keinen echten Compile-/Rendertest.

**Bitte beim ersten Laden im Spiel kurz gegenchecken:**
- Lädt der Pack ohne Fehlermeldung im Shader-Auswahlmenü?
- Falls Iris/OptiFine eine Fehlermeldung mit Datei + Zeilennummer zeigt: mir die Meldung schicken, dann behebe ich es gezielt.
- Sehen Schatten, Himmel/Sterne und Wasser wie erwartet aus?

## Bekannte bewusste Vereinfachungen

- Farbige/transluzente Schatten (z. B. getöntes Licht durch Buntglas/Blätter) sind nicht implementiert, nur harte Sonnen-/Mond-Schatten mit weichen Kanten (PCF).
- Item-Entities/Mobs bekommen keinen speziellen "Hurt-Flash"-Overlay-Effekt, sondern nur das normale Beleuchtungsmodell.
- Regen dimmt/entsättigt die Beleuchtung leicht, es gibt aber keine nassen Oberflächen-Reflexionen.
