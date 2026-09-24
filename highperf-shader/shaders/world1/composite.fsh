#version 120

/* DRAWBUFFERS:0 */
// Explizit auf NUR colortex0 begrenzt - siehe identischer Kommentar in der
// Overworld-composite.fsh.

/* =============================================================================
   world1/composite.fsh  -  "etwas Besonderes" für The End
   -----------------------------------------------------------------------------
   Iris/OptiFine laden Dateien aus shaders/world1/ automatisch ANSTELLE der
   gleichnamigen Datei aus shaders/ (world1 = The End; world-1 = Nether;
   Overworld = die Basis-Dateien direkt in shaders/).

   WICHTIG (Review-Erkenntnis): Sobald shaders/world1/ existiert, behandelt
   Iris es als KOMPLETT EIGENSTÄNDIGES Programm-Set für das End - es werden
   NICHT die fehlenden Dateien aus dem Basis-shaders/-Ordner nachgeladen!
   Ohne eigene gbuffers_terrain/gbuffers_water HIER in world1/ würden Blöcke
   und Wasser im End auf Iris' eingebauten generischen Fallback-Shader
   zurückfallen (kein PCF-Schatten, keine Colored Block Emission, keine
   Wetness) statt die Beleuchtung dieses Packs zu behalten. Deshalb liegen
   world1/gbuffers_terrain.vsh/.fsh und world1/gbuffers_water.vsh/.fsh als
   1:1-Kopien der Basis-Dateien hier - nur der Himmel (composite) ist im End
   wirklich anders, Blöcke/Wasser sehen bewusst genauso aus wie in der
   Overworld.

   Statt des normalen Overworld-Himmels (Farbverlauf + Sonne/Mond + Wolken +
   Sterne) gibt es hier:
     - Ein sich langsam bewegendes, violett-magentafarbenes "Void-Nebula"
       (zwei überlagerte Rausch-Ebenen statt einer flachen Wolkendecke).
     - Treibender, funkelnder "Sternenstaub" in Lila/Gold (wiederverwendet
       dieselbe Sterne-Technik wie die Overworld, nur anders eingefärbt).
     - Ein sanftes Pulsieren der gesamten Himmelshelligkeit ("Herzschlag").
     - Cinematic God Rays weiterhin aktiv (die Shadow Map / shadowLightPosition
       existieren auch im End, auch ohne sichtbare Sonne), aber violett statt
       sonnenfarben getönt und ohne Tag/Nacht-Abhängigkeit.
   Bloom und ACES-Tonemapping sind identisch zur Overworld-Datei.
   ============================================================================= */

// ---------------------------------------------------------------------------
// Einstellungen
// ---------------------------------------------------------------------------
#define GODRAY_SAMPLES  16     // [8 12 16 24 32]
// Eigener Name (nicht GODRAY_STRENGTH wie in der Overworld-Datei): Iris/
// OptiFine fasst gleichnamige, GUI-annotierte #defines pack-weit zu EINEM
// gemeinsamen Regler zusammen und übernimmt den gewählten Wert in JEDE Datei,
// die den Namen deklariert - bei unterschiedlichen Default-Werten/Werte-
// Listen (wie hier: 0.7 im End vs. 0.75 in der Overworld) könnte das einen
// Wert einschleusen, der auf der jeweils anderen Liste gar nicht steht. Ein
// eigener Name hält beide Regler garantiert unabhängig.
#define GODRAY_STRENGTH_END 0.7 // [0.0 0.2 0.45 0.7 1.0]
#define GODRAY_MAX_DIST 96.0
#define FOG_DENSITY     0.02   // [0.005 0.01 0.02 0.035 0.05]

#define END_DUST_DENSITY    0.03  // [0.01 0.02 0.03 0.05 0.08]  Anteil "Sternenstaub" am Himmel
#define END_DUST_SHARPNESS  0.4   // [0.25 0.3 0.4 0.5 0.6]
#define END_DUST_BRIGHTNESS 1.3   // [0.6 1.0 1.3 1.8 2.4]
#define END_PULSE_SPEED     0.6   // [0.2 0.4 0.6 0.9 1.3]  Geschwindigkeit des "Herzschlags"

#define BLOOM_THRESHOLD 0.85   // [0.7 0.8 0.85 0.9 0.95]
#define BLOOM_STRENGTH  0.5    // [0.0 0.2 0.35 0.5 0.75]
#define EXPOSURE 1.0           // [0.8 0.9 1.0 1.1 1.2 1.3]

// -- Farb-Grading (identisch zur Overworld-Datei, siehe dortiger Kommentar) --
#define SATURATION 1.3         // [1.0 1.1 1.2 1.3 1.4 1.5]
#define CONTRAST   1.1         // [1.0 1.05 1.1 1.15 1.2]

// -- Unter Wasser (identisch zur Overworld-Datei) --
// Das End hat zwar KEIN natürlich generiertes Wasser, aber platzierte
// Wassereimer verdunsten dort NICHT (das ist eine Nether-Besonderheit,
// "ultrawarm"-Dimensionen) - ein im End platzierter Wassertümpel bleibt
// bestehen, und isEyeInWater kann daher auch hier 1 werden. Damit Wasser
// dort nicht wieder zu dunkel wirkt (world1/gbuffers_water.fsh ist eine
// 1:1-Kopie der Basis-Datei), bekommt auch diese Datei denselben Regler.
#define UNDERWATER_BRIGHTNESS 1.25 // [1.0 1.15 1.25 1.4 1.6]

// -- Erde/Sand/Kies <-> Stein: weicher Übergang (identisch zur Overworld-
//    Datei, siehe dortiger Kommentar bei applyTerrainTransition()) --
#define TERRAIN_TRANSITION_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.7]
#define TERRAIN_TRANSITION_RADIUS   2.0  // [1.0 1.5 2.0 3.0 4.0]

uniform sampler2D colortex0;
uniform sampler2D colortex1;    // von world1/gbuffers_terrain.fsh (1:1-Kopie der Basis-Datei): Erde/Sand/Kies-vs-Stein-Kategorie
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;

uniform int isEyeInWater;    // Iris/OptiFine-Standard: 0 = Luft, 1 = Wasser, 2 = Lava

uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Sichtstrahl-Rekonstruktion (identisch zur Overworld-Datei).
// ---------------------------------------------------------------------------
vec3 reconstructViewRay(vec2 uv, float depth, out float dist) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewP = gbufferProjectionInverse * clip;
    viewP /= viewP.w;
    dist = length(viewP.xyz);
    return viewP.xyz / max(dist, 0.0001);
}

// ---------------------------------------------------------------------------
// Rausch-Grundlage für Nebel/Nebula (identisch zur Overworld-Datei).
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
float fbm(vec2 p) {
    float n = valueNoise(p) * 0.5;
    n += valueNoise(p * 2.0) * 0.25;
    n += valueNoise(p * 4.0) * 0.125;
    return n / 0.875; // siehe Overworld-Datei: Gewichte normalisieren, sonst wirkt CLOUD-artige Deckung verzerrt
}

// ---------------------------------------------------------------------------
// Sternenstaub - dieselbe Technik wie die Overworld-Sterne (composite.fsh),
// hier in Lila/Gold statt Weiß-Blau, und ohne Tag/Nacht-Abhängigkeit (im End
// ist es immer "Nacht"-artig dunkel).
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
// End-Himmel: dunkles Void-Lila mit zwei überlagerten, langsam wandernden
// Nebel-Ebenen + Sternenstaub + sanftem Pulsieren. sceneDir MUSS bereits in
// Szenen-/Weltraum vorliegen (siehe main()) - sonst würde das Muster am
// Bildschirm kleben statt am Himmel fest zu bleiben (derselbe Grundsatz wie
// bei Wolken/Sternen in der Overworld-Datei).
// ---------------------------------------------------------------------------
vec3 renderEndSky(vec3 sceneDir) {
    float t = frameTimeCounter * 0.06;

    vec3 deepVoid = vec3(0.035, 0.010, 0.055);
    vec3 nebulaA  = vec3(0.28, 0.08, 0.38);
    vec3 nebulaB  = vec3(0.55, 0.18, 0.60);

    vec2 uvA = sceneDir.xz * 1.6 + sceneDir.y * 1.2 + t;
    vec2 uvB = sceneDir.zy * 2.4 - t * 1.4;

    float nA = fbm(uvA);
    float nB = fbm(uvB);

    vec3 sky = mix(deepVoid, nebulaA, nA);
    sky = mix(sky, nebulaB, nB * 0.45);

    // Sanftes "Herzschlag"-Pulsieren der Gesamthelligkeit.
    float pulse = 0.85 + 0.15 * sin(frameTimeCounter * END_PULSE_SPEED);
    sky *= pulse;

    // Treibender Sternenstaub, abwechselnd lila und golden eingefärbt.
    // Gemeinsame, langsame Drift-Bewegung des ganzen Staubfelds (kein
    // Perlin-Flow pro Einzelpartikel nötig, wirkt aber sichtbar "treibend"
    // statt starr am Himmel zu kleben).
    vec3 driftOffset = vec3(sin(t * 0.7), cos(t * 0.55), sin(t * 0.4 + 1.7)) * 0.06;
    vec3 dustDir = normalize(sceneDir * 1.3 + driftOffset);
    float dust = starField(dustDir, END_DUST_DENSITY, END_DUST_SHARPNESS);
    // WICHTIG: Für die Farbe eine ANDERE Gitterzelle hashen als starField()
    // intern für die Existenzmaske benutzt (floor(dustDir*400.0)) - sonst
    // sind beide Werte praktisch identisch und der Lila-Zweig unten wird nie
    // erreicht (jeder sichtbare Staub-Punkt hätte star>=0.92, also auch
    // colorPick>=0.92, also IMMER golden).
    float colorPick = hash13(floor(dustDir * 400.0) + vec3(17.0, 31.0, 7.0));
    vec3 dustColor = mix(vec3(0.85, 0.55, 1.0), vec3(1.0, 0.85, 0.55), step(0.5, colorPick));
    sky += dust * dustColor * END_DUST_BRIGHTNESS;

    return sky;
}

// ---------------------------------------------------------------------------
// Schatten-Punktprobe ohne PCF (wie in der Overworld-Datei).
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
// Volumetrisches "Void-Licht": gleiche Raymarch-Technik wie die Overworld-
// God-Rays, aber ohne Sonnenfarbe/Tag-Nacht-Abhängigkeit (der End hat keine
// echte Sonne) - stattdessen fest violett getönt, Helligkeit über die
// Blickrichtung relativ zu shadowLightPosition (der festen Licht-Richtung,
// die Iris/OptiFine auch im End für Schatten verwenden).
// ---------------------------------------------------------------------------
vec3 computeEndGodRays(vec2 uv, float depth) {
    float surfaceDist;
    vec3 dir = reconstructViewRay(uv, depth, surfaceDist);
    float maxDist = (depth >= 1.0) ? GODRAY_MAX_DIST : min(surfaceDist, GODRAY_MAX_DIST);

    float stepSize = maxDist / float(GODRAY_SAMPLES);
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

    vec3 lightDir = normalize(shadowLightPosition);
    // Anders als in der Overworld-Datei gibt es hier kein dayFactor(), das
    // die Stärke natürlich auf ~0 herunterdrückt (nachts/ohne Sonnenblick) -
    // ohne einen niedrigen Sockelwert (statt vorher 0.4) würde diese Fläche
    // selbst am dunkelsten Punkt heller als deepVoid sein und das ganze Bild
    // gleichmäßig lila übertünchen statt echte Strahlen erkennen zu lassen.
    float phase = pow(max(dot(dir, lightDir), 0.0), 6.0) * 0.75 + 0.12;

    vec3 endLightColor = vec3(0.75, 0.50, 1.0);
    return endLightColor * scatter * phase * GODRAY_STRENGTH_END;
}

// ---------------------------------------------------------------------------
// Bloom (identisch zur Overworld-Datei, inkl. derselben bekannten
// Einschränkung: erfasst nicht den in diesem Durchlauf gezeichneten Himmel).
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

vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Farb-Grading (identisch zur Overworld-Datei, siehe dortiger Kommentar).
vec3 applyColorGrade(vec3 color) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, SATURATION);
    color = (color - 0.5) * CONTRAST + 0.5;
    return clamp(color, 0.0, 1.0);
}

// Erde/Sand/Kies <-> Stein-Übergang (identisch zur Overworld-Datei, siehe
// dortiger Kommentar - inkl. distanzabhängiger Radius-Skalierung und der
// dort dokumentierten bekannten Grenzen). Im End über block.properties
// (pack-weit, nicht pro Dimension) genauso gültig, falls entsprechende
// Blöcke dort vorkommen (z. B. mitgebrachte/platzierte Blöcke) -
// world1/gbuffers_terrain.fsh ist eine 1:1-Kopie der Basis-Datei und
// schreibt dieselbe colortex1-Kategorie; world1/gbuffers_entities.fsh
// schreibt ebenso wie die Basis-Datei immer 0.0.
vec3 applyTerrainTransition(vec3 color, vec2 uv, float depth) {
    float ownCategory = texture2D(colortex1, uv).r;
    if (ownCategory < 0.01) return color;

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
        // Wie in der Overworld-Datei: dir (Sichtraum) einmalig in Szenen-/
        // Weltraum drehen, BEVOR .y/.xz für Himmelseffekte benutzt werden.
        vec3 sceneDir = normalize(mat3(gbufferModelViewInverse) * dir);
        color = renderEndSky(sceneDir);
    } else {
        color = applyTerrainTransition(color, texcoord, depth);
    }

    color += computeEndGodRays(texcoord, depth);
    color = applyBloom(color, texcoord);

    // Identisch zur Overworld-Datei (siehe dortiger Kommentar) - platziertes
    // Wasser verdunstet im End nicht, isEyeInWater kann also auch hier 1 sein.
    if (isEyeInWater == 1) {
        color *= UNDERWATER_BRIGHTNESS;
    }

    color *= EXPOSURE;
    color = tonemapACES(color);
    color = applyColorGrade(color);

    gl_FragColor = vec4(color, 1.0);
}
