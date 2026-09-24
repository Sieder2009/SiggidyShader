#version 120

/* DRAWBUFFERS:0 */
// Explizit auf NUR colortex0 begrenzt - ohne Directive würde Iris/OptiFine
// (seit gbuffers_terrain.fsh colortex1 nutzt) auch hier standardmäßig
// mehrere Buffer binden. In der Praxis unkritisch, da dieser Durchlauf der
// letzte im Frame ist und colortex1 hier nur GELESEN wird, bevor am Ende
// gl_FragColor geschrieben wird (die eigentliche Terrain-Kategorie kommt erst
// wieder im NÄCHSTEN Frame aus gbuffers_terrain.fsh) - trotzdem hier explizit
// gemacht, um nicht von dieser Reihenfolge-Annahme abhängig zu sein.

/* =============================================================================
   composite.fsh
   -----------------------------------------------------------------------------
   Läuft einmal pro Bildschirmpixel, NACHDEM die ganze Szene (Terrain, Wasser,
   Entities über die Iris-Standardpfade) bereits in colortex0 liegt. Aufgaben:

     1. Himmel neu zeichnen, wo nichts Festes steht (depth >= 1.0): Farbverlauf
        Zenit/Horizont je nach Tageszeit, Sonnen-/Mondscheibe, 2D-Wolkenebene.
     2. Cinematic God Rays: pro Pixel entlang des Sichtstrahls durch die
        Shadow Map marschieren und aufsummieren, wie viel davon von der Sonne
        beleuchtet ist -> volumetrisches Licht durch "Nebel".
     3. Bloom: weicher Glanz nur auf wirklich hellen Stellen.
     4. ACES-Filmic-Tonemapping (ausbalancierte Farben, kein Ausbrennen).

   Hinweis: dayFactor/getDayNightSunColor/sunHeight sind hier absichtlich noch
   einmal definiert (identisch zu gbuffers_terrain.fsh), weil kein gemeinsames
   lib/common.glsl angefragt wurde. Für ein vollständiges Pack gehören diese
   Funktionen in eine gemeinsame Include-Datei, damit beide Kopien nicht
   auseinanderlaufen können.
   ============================================================================= */

// ---------------------------------------------------------------------------
// Einstellungen
// ---------------------------------------------------------------------------

// -- God Rays --
#define GODRAY_SAMPLES  16     // [8 12 16 24 32]  mehr = weicher/genauer, aber teurer (Performance!)
#define GODRAY_STRENGTH 0.75   // [0.0 0.25 0.5 0.75 1.0 1.5]
#define GODRAY_MAX_DIST 96.0   // wie weit (in Blöcken) durch den "Nebel" marschiert wird
#define FOG_DENSITY     0.02   // [0.005 0.01 0.02 0.035 0.05]  Dichte des volumetrischen Nebels

// -- Wolken (animierte 2D-Ebene, kein vollständiges volumetrisches Raymarching -
//    für "3 Dateien"-Umfang eine bewusste, dokumentierte Vereinfachung).
//    Blockiges Zellraster statt glattem Perlin-Rauschen (Minecraft-typisch),
//    mit abgerundeten Ecken statt scharfer Kanten - siehe cloudDensity(). --
#define CLOUD_COVERAGE  0.55   // [0.3 0.4 0.5 0.55 0.6 0.7]  mehr = mehr Wolken
#define CLOUD_HEIGHT    12.0   // virtuelle Höhe der Wolkenebene
#define CLOUD_SPEED     0.6    // [0.2 0.4 0.6 0.9 1.3]
#define CLOUD_ROUNDNESS 0.15   // [0.0 0.08 0.15 0.25 0.35]  wie stark die Ecken der blockigen Wolken-Zellen abgerundet werden (0 = scharfkantig)

// -- Sonne/Mond: QUADRATISCH statt rund (wie Vanilla Minecrafts eigene
//    Sonnen-/Mond-Textur), siehe squareDisc() --
#define SUN_SIZE  0.02   // [0.012 0.016 0.02 0.026 0.032]  "Winkel"-Halbbreite der Sonnenscheibe
#define MOON_SIZE 0.024  // [0.014 0.019 0.024 0.03 0.038]  dito für den Mond

// -- Sterne (nur nachts sichtbar, weich einblendend) --
#define STAR_DENSITY    0.02   // [0.005 0.01 0.02 0.03 0.05]  ungefährer Anteil des Himmels, der Sterne zeigt
#define STAR_SHARPNESS  0.35   // [0.2 0.25 0.3 0.35 0.4 0.5]  kleiner = schärfere Punkte
#define STAR_BRIGHTNESS 1.0    // [0.5 0.75 1.0 1.5 2.0]

// -- Bloom --
#define BLOOM_THRESHOLD 0.85   // [0.7 0.8 0.85 0.9 0.95]  nur Pixel heller als das glühen
#define BLOOM_STRENGTH  0.5    // [0.0 0.2 0.35 0.5 0.75]

// -- Tonemapping --
#define EXPOSURE 1.0           // [0.8 0.9 1.0 1.1 1.2 1.3]

// -- Farb-Grading (NACH dem Tonemapping, siehe applyColorGrade()) --
#define SATURATION 1.3         // [1.0 1.1 1.2 1.3 1.4 1.5]  Farbsättigung fürs "kräftigere", hochwertigere Gesamtbild
#define CONTRAST   1.1         // [1.0 1.05 1.1 1.15 1.2]    Kontrast um Mittelgrau (0.5) herum

// -- Licht (MUSS zu den gleichnamigen Werten in gbuffers_terrain.fsh /
//    gbuffers_water.fsh passen, sonst driften Sonnenscheibe/God-Rays farblich
//    von der Boden-/Wasserbeleuchtung auseinander - siehe #defines sind pro
//    Datei unabhängig, kein gemeinsames lib/common.glsl) --
#define SUN_WARMTH      1.05   // [0.8 0.9 1.0 1.05 1.1 1.2]
#define MOON_BRIGHTNESS 0.55   // [0.3 0.4 0.55 0.7 0.9]

// -- Regen auf der Linse (screen-space, nur bei Regen sichtbar) --
#define RAIN_LENS_STRENGTH 0.4 // [0.0 0.2 0.4 0.6 0.8]

// -- Unter Wasser --
#define UNDERWATER_BRIGHTNESS 1.25 // [1.0 1.15 1.25 1.4 1.6]  etwas hellere Sicht, wenn die Kamera selbst unter Wasser steht (sonst wirkt es zu dunkel/dumpf)

// -- Erde/Sand/Kies <-> Stein: weicher Übergang (siehe applyTerrainTransition()) --
#define TERRAIN_TRANSITION_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.7]  wie stark die Farben an der Grenze ineinander verlaufen
#define TERRAIN_TRANSITION_RADIUS   2.0  // [1.0 1.5 2.0 3.0 4.0]   Sample-Radius in Pixeln (Performance!)

uniform sampler2D colortex0;
uniform sampler2D colortex1;    // von gbuffers_terrain.fsh: Erde/Sand/Kies-vs-Stein-Kategorie (0/0.5/1.0), siehe applyTerrainTransition()
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 cameraPosition;

uniform int isEyeInWater;    // Iris/OptiFine-Standard: 0 = Luft, 1 = Wasser, 2 = Lava - hier nur auf ==1 geprüft

uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;

varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Tag/Nacht (identisch zu gbuffers_terrain.fsh - siehe Hinweis oben).
// Alle smoothstep()-Kanten sind bewusst aufsteigend sortiert.
// ---------------------------------------------------------------------------
float sunHeight() {
    return dot(normalize(upPosition), normalize(sunPosition));
}
float dayFactor(float h) { return smoothstep(-0.05, 0.30, h); }
float nightFactor(float h) { return 1.0 - smoothstep(-0.30, -0.05, h); }
float twilightFactor(float h) { return clamp(1.0 - dayFactor(h) - nightFactor(h), 0.0, 1.0); }

vec3 getDayNightSunColor(float h) {
    vec3 day    = vec3(1.05, 0.97, 0.85) * SUN_WARMTH;
    vec3 sunset = vec3(1.00, 0.55, 0.24);
    vec3 night  = vec3(0.35, 0.45, 0.85) * MOON_BRIGHTNESS;
    return day * dayFactor(h) + sunset * twilightFactor(h) + night * nightFactor(h);
}

// ---------------------------------------------------------------------------
// Reconstruiert aus Bildschirm-UV + Tiefenwert eine VIEW-SPACE-Sichtstrahl-
// Richtung und (falls depth < 1.0) die tatsächliche Entfernung zur Oberfläche.
// Standardtechnik: NDC -> gbufferProjectionInverse -> durch w teilen.
// ---------------------------------------------------------------------------
vec3 reconstructViewRay(vec2 uv, float depth, out float dist) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewP = gbufferProjectionInverse * clip;
    viewP /= viewP.w;
    dist = length(viewP.xyz);
    return viewP.xyz / max(dist, 0.0001);
}

// ---------------------------------------------------------------------------
// Wolken: blockiges Zellraster mit abgerundeten Ecken (siehe cloudDensity()
// weiter unten), auf eine horizontale Fläche in CLOUD_HEIGHT projiziert
// (Standard-"Flat Cloud Plane"-Technik). hash21()/valueNoise() hier werden
// außerdem von applyRainLens() weiter unten für die Regenstreifen genutzt.
// ---------------------------------------------------------------------------
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
// 2D-Rounded-Box-Distanzfunktion MIT VIER EINZELN WÄHLBAREN Eck-Radien
// (Standardtechnik, z. B. Inigo Quilez' "2D Distance Functions" - die
// Variante mit vec4-Radius für vier unabhängige Ecken). r = (oben-rechts,
// unten-rechts, oben-links, unten-links). p wird per Vorzeichen der
// jeweiligen Ecke zugeordnet, danach läuft die normale Rounded-Box-Formel
// mit NUR diesem einen Eck-Radius. Bei halfSize=0.5 reicht die Box an
// GERADEN Kanten immer exakt bis zum Zellrand, unabhängig vom Radius (nur
// die jeweilige Ecke wird abgerundet) - zwei benachbarte "Wolken"-Zellen
// verschmelzen dadurch entlang ihrer gemeinsamen Kante nahtlos.
float roundedBoxSDF4(vec2 p, vec2 halfSize, vec4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    vec2 q = abs(p) - halfSize + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

float cloudDensity(vec2 uv) {
    // Blockiges Zellraster statt glattem Perlin-Rauschen (wie zuvor) - jede
    // Zelle ist per Zell-Hash entweder "Wolke" oder nicht. Damit NUR die
    // AUSSENECKEN eines zusammenhängenden Wolkenfelds abgerundet werden
    // (nicht auch Ecken TIEF IM INNEREN eines großen Felds, wo das sonst
    // kleine "Dellen" erzeugen würde), wird pro Ecke geprüft, ob die beiden
    // angrenzenden Nachbarzellen ebenfalls "Wolke" sind - wenn ja, ist diese
    // Ecke innen und bleibt scharf (Radius 0), sonst wird sie abgerundet.
    vec2 cell = floor(uv);
    vec2 localPos = fract(uv) - 0.5;

    if (hash21(cell) < 1.0 - CLOUD_COVERAGE) return 0.0;

    float onE = step(1.0 - CLOUD_COVERAGE, hash21(cell + vec2( 1.0,  0.0)));
    float onW = step(1.0 - CLOUD_COVERAGE, hash21(cell + vec2(-1.0,  0.0)));
    float onN = step(1.0 - CLOUD_COVERAGE, hash21(cell + vec2( 0.0,  1.0)));
    float onS = step(1.0 - CLOUD_COVERAGE, hash21(cell + vec2( 0.0, -1.0)));

    // ODER, nicht UND: eine Ecke bleibt scharf, sobald MINDESTENS einer der
    // beiden angrenzenden Nachbarn ebenfalls "Wolke" ist - das deckt sowohl
    // echte Innen-Ecken (beide Nachbarn an) als auch Punkte MITTEN auf einer
    // geraden Kante ab (genau einer der beiden Nachbarn an, z. B. eine lange
    // waagerechte Zellreihe ohne Nachbarn darüber). Nur wenn BEIDE Nachbarn
    // fehlen, handelt es sich um eine echte, nach außen zeigende Ecke, die
    // abgerundet werden soll.
    float rTR = (onE > 0.5 || onN > 0.5) ? 0.0 : CLOUD_ROUNDNESS;
    float rBR = (onE > 0.5 || onS > 0.5) ? 0.0 : CLOUD_ROUNDNESS;
    float rTL = (onW > 0.5 || onN > 0.5) ? 0.0 : CLOUD_ROUNDNESS;
    float rBL = (onW > 0.5 || onS > 0.5) ? 0.0 : CLOUD_ROUNDNESS;

    float sd = roundedBoxSDF4(localPos, vec2(0.5), vec4(rTR, rBR, rTL, rBL));
    // Einseitig ausgehend von sd=0 (statt eines symmetrischen Bandes) -
    // sonst würden auch gerade, eigentlich nahtlose Kanten (die exakt bei
    // sd=0 liegen) auf halbe Deckkraft abfallen statt voll verbunden zu sein.
    float shape = 1.0 - smoothstep(0.0, 0.06, sd);

    // Skala 0.3 (nicht 3.0): uv trägt bereits die 10-fache Wolkenraster-
    // Skalierung (siehe applyClouds()) - ohne Gegenskalierung hier würde die
    // innere "wispy"-Struktur ebenfalls 10x feiner und potenziell in Richtung
    // Horizont zu Flimmern neigen, statt einer sanften, groben Binnenstruktur.
    float wispy = 0.85 + 0.15 * valueNoise(uv * 0.3 + 11.0);
    return clamp(shape * wispy, 0.0, 1.0);
}
// sceneDir MUSS bereits in Szenen-/Weltraum vorliegen (siehe renderSky()) -
// Y ist hier wirklich "nach oben", nicht "Bildschirm oben".
vec3 applyClouds(vec3 skyColor, vec3 sceneDir, float h) {
    if (sceneDir.y <= 0.02) return skyColor; // unterhalb/am Horizont keine Wolkenebene zeichnen
    float planeDist = CLOUD_HEIGHT / sceneDir.y;
    // Skala 0.2 (statt zuvor 0.02): bei 0.02 passte der gesamte sichtbare
    // Himmel (Zenit bis Horizont-Ausblendung) in ca. 1-2 Zellen - das Raster
    // war praktisch unsichtbar, wirkte wie ein einziger großer Fleck statt
    // eines Blockrasters. +cameraPosition.xz (mit derselben Skala): ohne das
    // würde sich das Wolkenmuster beim Laufen/Fliegen NIE verschieben, nur
    // beim Umschauen - derselbe Fehlerfall wie bei anderen welt-festen
    // Effekten in diesem Pack (siehe Kommentar bei applyTerrainTransition()).
    vec2 uv = (sceneDir.xz * planeDist + cameraPosition.xz) * 0.2
              + frameTimeCounter * CLOUD_SPEED * 0.1;
    float coverage = cloudDensity(uv);
    vec3 cloudColor = mix(vec3(0.35, 0.38, 0.45), vec3(1.0, 0.98, 0.95), dayFactor(h));
    float horizonFade = smoothstep(0.02, 0.15, sceneDir.y);
    return mix(skyColor, cloudColor, coverage * horizonFade * 0.85);
}

// ---------------------------------------------------------------------------
// Sterne: hash-basiertes Punktmuster, in ein 3D-Gitter entlang sceneDir
// projiziert (nicht in dir!) - genau wie bei den Wolken MUSS das im Szenen-/
// Weltraum passieren, sonst würden die "Sterne" am Bildschirm kleben bleiben
// und sich beim Umschauen nicht mit der Sicht mitbewegen.
// ---------------------------------------------------------------------------
float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float starField(vec3 sceneDir, float density, float sharpness) {
    vec3 p = sceneDir * 400.0;
    vec3 cell = floor(p);
    float star = hash13(cell);
    float mask = step(1.0 - density, star);

    vec3 f = fract(p) - 0.5;
    float d = length(f);
    float twinkle = 0.6 + 0.4 * sin(frameTimeCounter * (1.5 + star * 3.0) + star * 30.0);

    return mask * (1.0 - smoothstep(0.0, sharpness, d)) * twinkle;
}

// ---------------------------------------------------------------------------
// Liefert 0..1 für eine QUADRATISCHE Scheibe um lightDir, statt einer runden
// Scheibe über reine Winkel-Distanz (dot-Produkt) - Vanilla Minecrafts
// eigene Sonnen-/Mond-Textur ist selbst quadratisch, eine runde Scheibe
// würde dem "wie in Minecraft" widersprechen. Technik: lightDir/up/right
// spannen eine lokale Tangentialebene auf; dir wird dort hinein projiziert
// (Gnomonic-Projektion) und per Chebyshev-Abstand (max(|x|,|y|), nicht
// euklidisch) bewertet - das ergibt eine Quadrat- statt Kreisform.
// `dir`/`lightDir`/`up` MÜSSEN alle im selben Raum vorliegen (hier: Sichtraum,
// wie überall in dieser Funktion).
//
// WICHTIG (Entartungsfall Sonnenhöchststand/Mond-Mitternacht): Minecrafts
// Standard-Sonnenbahn (kein SUN_PATH_ROTATION o.ä. in diesem Pack) führt
// Sonne/Mond täglich nahe am Zenit vorbei - genau dann liegt lightDir fast
// parallel zu up, cross(up, lightDir) geht gegen den Nullvektor, und
// normalize() davon würde NaN liefern (0 * unendlich). Da right/localUp NUR
// von lightDir/up abhängen (nicht vom Pixel dir), würde ein NaN hier nicht
// nur die Scheibe selbst, sondern JEDEN Himmels-Pixel mit align>0 verfärben -
// also einen Großteil des sichtbaren Himmels, zweimal pro Tag. Deshalb bei
// Bedarf eine Ausweich-Referenzachse verwenden, die anhand von lightDir
// SELBST gewählt wird (nicht anhand von up) - dadurch kann sie nie zufällig
// ebenfalls parallel zu lightDir werden.
// ---------------------------------------------------------------------------
float squareDisc(vec3 dir, vec3 lightDir, vec3 up, float halfWidth) {
    float align = dot(dir, lightDir);
    if (align <= 0.0) return 0.0;

    vec3 refAxis = (abs(lightDir.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 useUp = (abs(dot(up, lightDir)) > 0.999) ? refAxis : up;

    vec3 right = normalize(cross(useUp, lightDir));
    vec3 localUp = cross(lightDir, right);
    vec2 local = vec2(dot(dir, right), dot(dir, localUp)) / align;
    float d = max(abs(local.x), abs(local.y));
    return 1.0 - smoothstep(halfWidth * 0.92, halfWidth, d);
}

// ---------------------------------------------------------------------------
// Himmel: Verlauf Horizont->Zenit je nach Tageszeit, Sonnen-/Mondscheibe,
// Wolken. dot(dir, up)/dot(dir, sunDir) statt dir.y, weil alle diese Vektoren
// im Sichtraum vorliegen und "Weltrichtung nach oben" dort NICHT einfach
// (0,1,0) ist, sondern von der Kamera-Neigung abhängt.
// ---------------------------------------------------------------------------
vec3 renderSky(vec3 dir) {
    vec3 up = normalize(upPosition);
    float h = sunHeight();

    vec3 zenith  = mix(vec3(0.02, 0.03, 0.08), vec3(0.35, 0.55, 0.90), dayFactor(h));
    vec3 horizon = mix(vec3(0.10, 0.11, 0.18), vec3(0.75, 0.85, 1.00), dayFactor(h));
    horizon = mix(horizon, vec3(1.00, 0.55, 0.25), twilightFactor(h) * 0.85);

    float t = clamp(dot(dir, up) * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, pow(t, 0.45));

    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);

    // Quadratische Scheiben (siehe squareDisc() oben) statt runder - der
    // weiche, weiterhin kreisförmige "Glow" drumherum bleibt bewusst rund
    // (wie ein atmosphärischer Dunst-/Streulicht-Schein um eine eckige
    // Lichtquelle), nur die scharfe Scheibe selbst wird eckig.
    float sunDisc = squareDisc(dir, sunDir, up, SUN_SIZE);
    float sunAlign = dot(dir, sunDir);
    float sunGlow = pow(max(sunAlign, 0.0), 300.0) * 0.6;
    sky += (sunDisc * 3.0 + sunGlow) * getDayNightSunColor(h);

    float moonDisc = squareDisc(dir, moonDir, up, MOON_SIZE);
    sky += moonDisc * vec3(0.85, 0.88, 1.0) * 0.7 * nightFactor(h);

    // Ab hier: dir (Sichtraum) einmalig in Szenen-/Weltraum drehen, für
    // Wolken UND Sterne - beide brauchen eine tatsächlich welt-feste
    // Richtung (siehe Kommentare bei applyClouds()/starField()).
    vec3 sceneDir = normalize(mat3(gbufferModelViewInverse) * dir);

    float night = nightFactor(h);
    if (night > 0.001) {
        float stars = starField(sceneDir, STAR_DENSITY, STAR_SHARPNESS) * STAR_BRIGHTNESS;
        sky += stars * night * vec3(0.9, 0.95, 1.0);
    }

    sky = applyClouds(sky, sceneDir, h);
    return sky;
}

// ---------------------------------------------------------------------------
// Ein einzelner Schatten-Lookup OHNE PCF (für den God-Ray-Raymarch reicht ein
// Sample pro Schritt - Performance!). `scenePos` ist bereits im Schatten-/
// Weltraum (siehe computeGodRays).
// ---------------------------------------------------------------------------
float sampleShadowPoint(vec3 scenePos) {
    vec4 shadowClip = shadowProjection * (shadowModelView * vec4(scenePos, 1.0));
    vec3 shadowScreen = shadowClip.xyz * 0.5 + 0.5;
    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }
    float depthSample = texture2D(shadowtex0, shadowScreen.xy).r;
    return (shadowScreen.z - 0.0015 > depthSample) ? 0.0 : 1.0;
}

// ---------------------------------------------------------------------------
// Cinematic God Rays: entlang des Sichtstrahls von der Kamera bis zur
// sichtbaren Oberfläche (oder GODRAY_MAX_DIST bei Himmel-Pixeln) marschieren,
// an jedem Punkt prüfen ob er von der Sonne beleuchtet ist, und die
// beleuchteten Anteile (mit Distanz-Extinktion) aufsummieren.
// ---------------------------------------------------------------------------
vec3 computeGodRays(vec2 uv, float depth) {
    float surfaceDist;
    vec3 dir = reconstructViewRay(uv, depth, surfaceDist);
    float maxDist = (depth >= 1.0) ? GODRAY_MAX_DIST : min(surfaceDist, GODRAY_MAX_DIST);

    float stepSize = maxDist / float(GODRAY_SAMPLES);

    // Dither pro Pixel gegen sichtbares Banding im Raymarch (billiges Hash-Muster).
    float dither = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);

    float scatter = 0.0;
    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        float t = (float(i) + dither) * stepSize;
        vec3 viewSample = dir * t;
        vec3 scenePos = (gbufferModelViewInverse * vec4(viewSample, 1.0)).xyz;
        float lit = sampleShadowPoint(scenePos);
        float extinction = exp(-t * FOG_DENSITY);
        scatter += lit * extinction;
    }
    scatter /= float(GODRAY_SAMPLES);

    vec3 sunDir = normalize(sunPosition);
    // Richtung Sonne heller (Sunburst-Look), aber nie komplett dunkel.
    float phase = pow(max(dot(dir, sunDir), 0.0), 8.0) * 0.7 + 0.3;

    return getDayNightSunColor(sunHeight()) * scatter * phase * GODRAY_STRENGTH * dayFactor(sunHeight());
}

// ---------------------------------------------------------------------------
// Bloom: 5x5-Nachbarschafts-Sample, gewichtet nach Helligkeit oberhalb von
// BLOOM_THRESHOLD - trifft helle, bereits in colortex0 vorhandene Stellen
// (Lava, Glowstone, Fackel-Textur usw.). Bei vollem Tageslicht (Beleuchtungs-
// Summe ~1.4, siehe Kommentar bei SKY_AMBIENT_STRENGTH in gbuffers_terrain.fsh)
// reicht dafür bereits eine Albedo-Luma von ca. 0.6 - das trifft AUCH
// gewöhnliches helles Terrain (Schnee, Sand, Quarz, weiße Wolle) und nicht
// nur echte Lichtquellen; bei erhöhtem BLOOM_STRENGTH entsprechend sichtbarer.
// `glow / total` ist zudem der Farb-MITTELWERT NUR der über der Schwelle
// liegenden Samples im 5x5-Fenster, nicht auf die Anzahl aller 25 Samples
// normiert - schon ein einzelner heller Nachbar im Fenster kann dadurch den
// vollen Bloom-Beitrag auslösen, nicht nur großflächig helle Bereiche.
//
// Bekannte Einschränkung: Diese Funktion liest colortex0, das den Stand VOR
// diesem composite-Durchlauf zeigt. Die Sonnen-/Mondscheibe und die God Rays
// werden aber erst weiter oben in main() (in genau diesem Durchlauf)
// berechnet und existieren nur lokal in der Variable `color` - sie bekommen
// dadurch selbst KEINEN Bloom-Halo. Für einen echten Glow um die Sonne
// bräuchte es einen zweiten Composite-Durchlauf (composite1.fsh), der nach
// diesem hier läuft und das fertige Bild (inkl. Himmel/God Rays) liest.
// ---------------------------------------------------------------------------
vec3 applyBloom(vec3 color, vec2 uv) {
    vec3 glow = vec3(0.0);
    float total = 0.0;
    vec2 px = vec2(1.0 / viewWidth, 1.0 / viewHeight) * 2.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2 offset = vec2(float(x), float(y)) * px;
            vec3 s = texture2D(colortex0, uv + offset).rgb;
            float luma = dot(s, vec3(0.2126, 0.7152, 0.0722));
            float w = max(luma - BLOOM_THRESHOLD, 0.0);
            glow += s * w;
            total += w;
        }
    }
    if (total > 0.0) {
        color += (glow / total) * BLOOM_STRENGTH * 0.5;
    }
    return color;
}

// ---------------------------------------------------------------------------
// "Regen auf der Linse": dezenter Screen-Space-Effekt, nur bei Regen aktiv.
// Nutzt dieselbe valueNoise()-Grundlage wie die Wolken, gestreckt und nach
// unten wandernd wie Tropfenspuren auf einer Scheibe. Liest colortex0 ein
// zweites Mal (wie applyBloom() direkt darunter) - das Lesen selbst ist
// unbedenklich, siehe Datei-Kopf: composite.fsh liest/schreibt colortex0
// sicher, weil Iris zwischen zwei getrennten physischen Texturen hin- und
// herschaltet.
//
// WICHTIG: colortex0 zeigt an dieser Stelle den Bildstand VOR diesem
// composite-Durchlauf (siehe applyBloom()-Kommentar oben) - der bereits neu
// gezeichnete Himmel/God Rays/Bloom stecken nur in der lokalen `color`-
// Variable, NICHT in colortex0. Ein reines mix(color, colortex0-Sample, ...)
// würde also teilweise wieder den ALTEN (Vanilla-)Himmel einblenden statt
// einer echten Verzerrung des aktuellen Bilds. Deshalb hier additiv: nur
// die DIFFERENZ zwischen verschobenem und unverschobenem colortex0-Sample
// wird auf `color` aufaddiert (wie beim ebenfalls additiven applyBloom()),
// nie der rohe, veraltete Puffer-Inhalt selbst.
//
// rainStrength ist ein UNIFORM -> der frühe Ausstieg unten ist komplett
// divergenzfrei und kostet bei Trockenheit nichts.
// ---------------------------------------------------------------------------
vec3 applyRainLens(vec3 color, vec2 uv) {
    if (rainStrength < 0.01) return color;

    vec2 streakUV = vec2(uv.x * 18.0, uv.y * 4.0 - frameTimeCounter * 0.15);
    float streaks = valueNoise(streakUV) * valueNoise(streakUV * 2.3 + 7.0);
    float mask = smoothstep(0.55, 0.75, streaks) * rainStrength * RAIN_LENS_STRENGTH;
    if (mask <= 0.0001) return color;

    vec2 offset = vec2(streaks - 0.5, 0.0) * 0.01;
    vec2 offsetUV = clamp(uv + offset, 0.001, 0.999);

    vec3 base = texture2D(colortex0, uv).rgb;
    vec3 shifted = texture2D(colortex0, offsetUV).rgb;

    return color + (shifted - base) * mask;
}

// ---------------------------------------------------------------------------
// ACES-Filmic-Tonemapping (Narkowicz-Approximation) - helle Stellen laufen
// weich aus statt hart auszubrennen.
// ---------------------------------------------------------------------------
vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Farb-Grading: Sättigung + Kontrast, NACH dem ACES-Tonemapping (Werte liegen
// dort schon garantiert in [0,1] - Grading vor dem Tonemapping würde die
// ACES-Kurve stattdessen mit verschobenen Eingabewerten füttern und deren
// sorgfältig kalibrierte Übergänge verzerren). Sättigung skaliert relativ zur
// Luminanz (mix Richtung Graustufe/davon weg), Kontrast pivotiert um 0.5
// (Mittelgrau), damit die generelle Belichtung dabei nicht wegdriftet.
// ---------------------------------------------------------------------------
vec3 applyColorGrade(vec3 color) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, SATURATION);
    color = (color - 0.5) * CONTRAST + 0.5;
    return clamp(color, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Weicher Übergang zwischen weichem Boden (Erde/Sand/Kies) und Stein-Blöcken,
// aber NUR zwischen genau diesen beiden Kategorien - andere Nachbarblöcke
// (Gras, Holz, ...) lösen bewusst KEINEN Übergang aus. gbuffers_terrain.fsh
// schreibt dafür colortex1 (0.0 = anderer Block, 0.5 = weicher Boden,
// 1.0 = Stein) - echte Nachbar-Erkennung ist im Terrain-Durchlauf selbst
// nicht möglich (derselbe "Feedback Loop"-Grund, aus dem Wasser eine eigene
// Datei braucht), deshalb läuft das hier, NACH dem fertigen Terrain.
// gbuffers_water.fsh/gbuffers_weather.fsh haben ein eigenes DRAWBUFFERS:0,
// gbuffers_entities.fsh ein eigenes DRAWBUFFERS:01 mit IMMER 0.0 - siehe
// Kommentare dort, sonst würde deren gl_FragColor versehentlich auch
// colortex1 überschreiben bzw. dort veraltete Terrain-Kategorien stehen
// bleiben.
//
// Für eine organische statt harten/geraden Kante wird zusätzlich mit
// WELT-festem (nicht bildschirmfestem!) Rauschen gewichtet - sonst würde das
// Übergangsmuster beim Kamera-Schwenk sichtbar "schwimmen" (derselbe
// Fehlerfall wie bei Wolken/Sternen weiter oben in dieser Datei).
//
// Der Sample-Radius wird mit der Blickdistanz skaliert (statt fest in
// Bildschirm-Pixeln zu bleiben): aus der Nähe (ein Blockgesicht kann
// hunderte Pixel groß sein) wäre ein reiner Pixel-Radius fast unsichtbar
// dünn, aus der Distanz (einzelne Blöcke nur wenige Pixel breit) dagegen zu
// breit und würde an praktisch jeder Kante auslösen. Grobe Näherung ohne
// echten Kamera-FOV-Abgleich - eine exakte Kalibrierung bräuchte einen
// echten Rendertest.
//
// Bekannte Grenzen (bewusst nicht vollständig gelöst):
//  - Das gehaltene Item (kein eigenes gbuffers_hand in diesem Pack, läuft
//    über Iris' interne Ersatz-Stufe) kann an einer Erde/Stein-Grenze eine
//    veraltete Kategorie darunter "sehen" und leicht mitfärben.
//  - Das weltraum-feste Rauschen bleibt beim Kamera-SCHWENKEN stabil, kann
//    aber bei sehr weit entfernten Kanten und kleinen Kamera-Bewegungen
//    trotzdem zwischen benachbarten Rausch-Zellen "umspringen" (ein anderes
//    Problem als das Schwimmen oben) - in der Praxis nur bei genauem
//    Hinsehen auf große Distanz bemerkbar.
// ---------------------------------------------------------------------------
vec3 applyTerrainTransition(vec3 color, vec2 uv, float depth) {
    float ownCategory = texture2D(colortex1, uv).r;
    if (ownCategory < 0.01) return color;

    // Weltposition/Distanz VOR der Nachbarsuche berechnen - wird für die
    // distanzabhängige Radius-Skalierung UND (weiter unten) fürs Rauschen
    // gebraucht, damit reconstructViewRay() nicht zweimal laufen muss.
    // cameraPosition ist hier zwingend nötig: gbufferModelViewInverse dreht
    // nur zurück in die Welt-ORIENTIERUNG, die absolute Kameraverschiebung
    // fehlt sonst (dieselbe Falle wie bei Wolken/Sternen).
    float dist;
    vec3 dir = reconstructViewRay(uv, depth, dist);
    vec3 scenePos = cameraPosition + (gbufferModelViewInverse * vec4(dir * dist, 1.0)).xyz;

    float distScale = clamp(dist / 8.0, 0.5, 6.0);
    vec2 px = vec2(1.0 / viewWidth, 1.0 / viewHeight) * TERRAIN_TRANSITION_RADIUS * distScale;
    vec3 neighborSum = vec3(0.0);
    float neighborCount = 0.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            vec2 sampleUV = uv + vec2(float(x), float(y)) * px;
            float otherCategory = texture2D(colortex1, sampleUV).r;
            if (otherCategory > 0.01 && abs(otherCategory - ownCategory) > 0.01) {
                neighborSum += texture2D(colortex0, sampleUV).rgb;
                neighborCount += 1.0;
            }
        }
    }
    if (neighborCount < 0.5) return color;
    vec3 neighborAvg = neighborSum / neighborCount;

    float n = hash13(floor(scenePos * 3.0));

    float edgeFactor = clamp(neighborCount / 3.0, 0.0, 1.0);
    float blendAmount = TERRAIN_TRANSITION_STRENGTH * edgeFactor * smoothstep(0.15, 0.85, n);

    return mix(color, neighborAvg, blendAmount);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    if (depth >= 1.0) {
        float unusedDist;
        vec3 dir = reconstructViewRay(texcoord, 1.0, unusedDist);
        color = renderSky(dir);
    } else {
        color = applyTerrainTransition(color, texcoord, depth);
    }

    color += computeGodRays(texcoord, depth);
    color = applyBloom(color, texcoord);
    color = applyRainLens(color, texcoord);

    // Steht die Kamera selbst im Wasser, wirkt die Szene sonst zu dunkel/
    // dumpf (Wasser-Eigenfarbe/-Absorption liegt dann quasi permanent über
    // dem gesamten Bild) - ein einfacher Helligkeits-Multiplikator kompensiert
    // das, ohne die Wasser-Beleuchtung selbst (gbuffers_water.fsh) anzufassen.
    if (isEyeInWater == 1) {
        color *= UNDERWATER_BRIGHTNESS;
    }

    color *= EXPOSURE;
    color = tonemapACES(color);
    color = applyColorGrade(color);

    gl_FragColor = vec4(color, 1.0);
}
