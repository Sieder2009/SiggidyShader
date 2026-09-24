#version 120

/* DRAWBUFFERS:01 */
// Zwei Ausgaben: gl_FragData[0] -> colortex0 (fertig beleuchtetes Bild, wie
// bisher), gl_FragData[1] -> colortex1 (nur eine "Erde/Sand/Kies vs. Stein"-
// Kategorie, siehe ID_TERRAIN_SOFT/ID_TERRAIN_STONE unten). colortex1 wird
// von composite.fsh (applyTerrainTransition()) gelesen, um einen weichen
// Übergang NUR zwischen diesen beiden Kategorien zu zeichnen - echte
// Nachbar-Erkennung ist hier im Terrain-Durchlauf selbst nicht möglich
// (derselbe "Feedback Loop"-Grund, aus dem Wasser eine eigene Datei braucht,
// siehe Kommentar weiter unten).

/* =============================================================================
   gbuffers_terrain.fsh
   -----------------------------------------------------------------------------
   Beleuchtung für undurchsichtiges Terrain (Blöcke). Wasser läuft NICHT mehr
   über diese Datei - siehe gbuffers_water.vsh/.fsh: echte Refraktion braucht
   eine bereits vollständig fertig gerenderte Opak-Szene in colortex0, die es
   innerhalb DIESES Terrain-Durchlaufs noch nicht geben kann (dieselbe Textur
   gleichzeitig als aktives Render-Target UND als Sampler zu lesen ist laut
   OpenGL-Spezifikation ein undefiniertes Feedback-Loop - deshalb die
   Aufteilung in zwei echte, nacheinander laufende Programme).

   Enthält:
     - PCF-weiche Schatten (Sonne/Mond) über eine eigene, unverzerrte
       Shadow Map (siehe shadow.vsh/.fsh) - das Sampling hier nutzt daher
       unverzerrte 1:1-Schattenkoordinaten, exakt passend zu shadow.vsh.
     - Warmes Sonnenlicht am Tag, kühles Mondlicht bei Nacht, weicher
       Sonnenuntergang dazwischen.
     - Fackel-/Blocklicht über den Torch-Kanal der Vanilla-Lightmap.
     - Colored Block Emission: bekannte Lichtquellen-Blöcke (Fackel, Seelen-
       fackel, Glowstone, Lava, Redstone, Seelaterne, Froschlicht, Amethyst)
       glühen jeweils in ihrer eigenen, typischen Farbe statt alle gleich
       warm-orange (siehe getEmissionColor()).
     - Wetness/PBR: bei Regen bekommen nasse Oberflächen (mit Himmelslicht)
       einen zusätzlichen Glanzlicht-Reflex, der weich (nicht hart) einblendet.

   Hinweis: Dayfactor/getDayNightSunColor/applyFog/sampleShadow sind hier
   bewusst direkt in der Datei definiert (kein lib/common.glsl), genau wie in
   gbuffers_water.fsh und composite.fsh - für ein vollständiges Pack sollten
   diese Hilfsfunktionen in eine gemeinsame Include-Datei wandern.
   ============================================================================= */

// ---------------------------------------------------------------------------
// Einstellungen - im Iris/OptiFine Shader-Options-Menü direkt anpassbar
// ---------------------------------------------------------------------------

// -- Schatten --
const int shadowMapResolution = 2048;   // [1024 2048 4096]  Auflösung der Shadow Map
const float shadowDistance    = 140.0;  // [64.0 96.0 128.0 140.0 160.0 200.0]  Schattenreichweite
#define SOFT_SHADOW_SAMPLES 2            // [1 2 3]  PCF-Radius in Texeln - höher = weicher, aber teurer
#define SHADOW_BIAS 0.0015               // Tiefen-Bias gegen Shadow-Acne

// -- Licht --
// Werte bewusst so kalibriert, dass volles Tageslicht (Sonne + Himmel) in
// Summe nahe 1.0-1.3 bleibt statt (wie in einer früheren Version) über 2.0
// zu gehen - sonst läuft praktisch jede Außenfläche beim ACES-Tonemapping
// Richtung Weiß/entsättigt, und das Bloom (Schwelle 0.85) würde durch die
// überhöhte Helligkeit bei fast jeder Tageslicht-Oberfläche mit auslösen.
#define SUN_WARMTH       1.05   // [0.8 0.9 1.0 1.05 1.1 1.2]  Intensität/Wärme des Sonnenlichts
#define MOON_BRIGHTNESS  0.55   // [0.3 0.4 0.55 0.7 0.9]      Helligkeit des Mondlichts
#define TORCH_INTENSITY  1.0    // [0.6 0.8 1.0 1.2 1.5]       Helligkeit von Fackeln/Blocklicht
#define SKY_AMBIENT_STRENGTH 0.55 // [0.3 0.4 0.55 0.7 0.9]    Anteil des Himmelslichts an der Gesamtbeleuchtung
// Bewusste Stilisierung (keine echte Bounce-/AO-Berechnung): in vom
// Sonnen-/Mondlicht abgeschatteten Bereichen wird zusätzlich auch das
// Himmelslicht etwas gedämpft (statt nur der direkte Sonnenanteil). Physikalisch
// korrekt wäre Himmelslicht unabhängig vom Sonnenschatten (eine Fläche unter
// einem Vordach sieht ja weiterhin den Himmel), aber ohne echte Bounce-/AO-Stufe
// sorgt genau das für den "flachen", kontrastarmen Look. Dieser Kompromiss
// (Sonnenschatten wirkt teilweise wie ein günstiger AO-Ersatz) ist der
// Standardtrick, den auch BSL/Complementary-artige Packs für plastischere,
// "hochwertigere" Schatten nutzen.
#define SHADOW_AO_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.65]     wie stark Himmelslicht im Sonnenschatten zusätzlich abgedunkelt wird

// -- Wetness / PBR --
#define WETNESS_STRENGTH 0.8    // [0.0 0.4 0.8 1.2 1.6]  Stärke des Regen-Glanzlichts auf nassen Flächen

// -- Colored Block Emission --
// Jeder Lichtquellen-Typ bekommt seine eigene Glühfarbe (statt vorher alle
// gleich warm-orange über den Torch-Kanal der Lightmap). Das färbt NUR die
// Oberfläche der Lichtquelle selbst ein - das tatsächlich AUSGESTRAHLTE
// Licht auf benachbarte Blöcke bleibt der normale, warme Torch-Ton der
// Vanilla-Lightmap (eine echte farbige Lichtausbreitung bräuchte ein
// komplettes Voxel-Lichtsystem, das den Rahmen dieser Datei sprengen würde).
#define EMISSION_STRENGTH 1.4   // [0.6 1.0 1.4 1.8 2.4]  Stärke des Eigen-Leuchtens

#define ID_EMIT_TORCH      1010.0  // Fackel, Wandfackel, Laterne
#define ID_EMIT_SOUL       1011.0  // Seelenfackel, Seelenlaterne
#define ID_EMIT_GLOWSTONE  1012.0  // Glowstone, Leuchtpilz
#define ID_EMIT_LAVA       1013.0  // Lava, Magmablock
#define ID_EMIT_REDSTONE   1014.0  // Redstone-Fackel/-Lampe (nur "an")
#define ID_EMIT_SEALANTERN 1015.0  // Seelaterne
#define ID_EMIT_FROG_VERDANT   1016.0  // Froschlicht grün
#define ID_EMIT_FROG_OCHRE     1017.0  // Froschlicht gelb
#define ID_EMIT_FROG_PEARL     1018.0  // Froschlicht rosa-weiß
#define ID_EMIT_AMETHYST   1019.0  // Amethyst-Cluster/-Knospen (leuchten in Vanilla nicht wirklich,
                                    // hier rein optisch für den "Wow-Effekt")

// -- Erde/Sand/Kies <-> Stein: weicher Übergang (siehe DRAWBUFFERS-Kommentar
//    oben und applyTerrainTransition() in composite.fsh) --
#define ID_TERRAIN_SOFT  1030.0  // Erde, Grobe Erde, Podsol, Myzel, Wurzelerde, Sand, roter Sand, Kies
#define ID_TERRAIN_STONE 1031.0  // Stein, Cobble, Andesit/Diorit/Granit, Tiefenschiefer, Tuffstein, Calcit, Stein-/Sandstein-Ziegel, Schwarzstein, Basalt

// Liefert die Glühfarbe für eine Block-ID, oder Schwarz (= kein Glühen) für
// alles andere. Eigene Farbe hier ändern oder neue Zeile + passenden
// block.properties-Eintrag ergänzen, um weitere Lichtquellen einzufärben.
vec3 getEmissionColor(float id) {
    if (id == ID_EMIT_TORCH)       return vec3(1.00, 0.55, 0.20); // warmes Orange
    if (id == ID_EMIT_SOUL)        return vec3(0.25, 0.75, 0.90); // kühles Türkisblau
    if (id == ID_EMIT_GLOWSTONE)   return vec3(1.00, 0.85, 0.35); // warmes Gelb
    if (id == ID_EMIT_LAVA)        return vec3(1.00, 0.32, 0.05); // tiefes Rot-Orange
    if (id == ID_EMIT_REDSTONE)    return vec3(1.00, 0.12, 0.10); // Rot
    if (id == ID_EMIT_SEALANTERN)  return vec3(0.55, 0.95, 0.95); // kühles Cyan-Weiß
    if (id == ID_EMIT_FROG_VERDANT) return vec3(0.45, 0.90, 0.55); // Grün
    if (id == ID_EMIT_FROG_OCHRE)   return vec3(1.00, 0.75, 0.25); // Gelb-Orange
    if (id == ID_EMIT_FROG_PEARL)   return vec3(1.00, 0.80, 0.88); // Rosa-Weiß
    if (id == ID_EMIT_AMETHYST)    return vec3(0.65, 0.45, 0.95); // sanftes Violett
    return vec3(0.0);
}

uniform sampler2D tex;
uniform sampler2D shadowtex0;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;  // für: Sichtraum-Position/-Normale -> Schattenraum

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;      // zeigt automatisch zur Sonne ODER zum Mond (je nachdem was gerade über dem Horizont steht)

uniform float rainStrength;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying float blockID;

// ---------------------------------------------------------------------------
// Tag/Nacht-Hilfsfunktionen. Alle smoothstep()-Aufrufe sind bewusst AUFSTEIGEND
// sortiert (edge0 < edge1) - GLSL garantiert smoothstep()-Verhalten nur in
// dieser Reihenfolge; eine "umgekehrte" Rampe wird über 1.0-smoothstep(...)
// gebaut statt die Kanten zu vertauschen.
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

vec3 getSkyAmbient(float h) {
    vec3 day    = vec3(0.55, 0.72, 1.00);
    vec3 sunset = vec3(0.55, 0.40, 0.48);
    vec3 night  = vec3(0.05, 0.07, 0.14);
    return day * dayFactor(h) + sunset * twilightFactor(h) + night * nightFactor(h);
}

vec3 applyFog(vec3 color, vec3 fragViewPos) {
    float dist = length(fragViewPos);
    float fogFactor = clamp((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 1.0), 0.0, 1.0);
    fogFactor *= fogFactor;
    return mix(color, gl_Fog.color.rgb, fogFactor);
}

// ---------------------------------------------------------------------------
// Weiche Schatten (PCF). shadow.vsh (eigene Datei) rendert die Shadow Map
// unverzerrt (reines ftransform(), kein Distortion-Warp) - die Schatten-
// koordinaten hier werden deshalb ebenfalls bewusst OHNE Verzerrung berechnet,
// damit beide Seiten exakt zusammenpassen.
// `normal` MUSS in Sichtraum (view space) übergeben werden, wie viewNormal.
//
// WICHTIG: außerhalb der Shadow-Map-Frustum (jenseits shadowDistance) liefert
// diese Funktion ohne Weiteres hart 1.0 ("voll beleuchtet") zurück - ohne ein
// Ausblenden Richtung dieser Distanz entstünde am Frustum-Rand ein sichtbarer
// Helligkeits-Sprung (vorher primär bei direktem Licht durch NdotL oft
// kaschiert, seit skyLight ebenfalls von `shadow` abhängt - siehe
// SHADOW_AO_STRENGTH unten - aber auf JEDER Fläche sichtbar, unabhängig von
// der Ausrichtung). Deshalb wird der PCF-Wert nahe shadowDistance weich
// Richtung 1.0 ausgeblendet statt hart umzuschalten.
// ---------------------------------------------------------------------------
float sampleShadow(vec3 fragViewPos, vec3 normal) {
    // Normale vom Sichtraum in den (unrotierten) Schatten-/Weltraum drehen -
    // sonst würde der Anti-Acne-Versatz bei jeder Kamera-Drehung in die
    // falsche Richtung zeigen.
    vec3 sceneNormal = normalize(mat3(gbufferModelViewInverse) * normal);
    vec3 scenePos = (gbufferModelViewInverse * vec4(fragViewPos, 1.0)).xyz;
    scenePos += sceneNormal * 0.05;

    vec4 shadowClip = shadowProjection * (shadowModelView * vec4(scenePos, 1.0));
    vec3 shadowScreen = shadowClip.xyz * 0.5 + 0.5;

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    float texel = 1.0 / float(shadowMapResolution);
    float lit = 0.0;
    float total = 0.0;
    for (int x = -SOFT_SHADOW_SAMPLES; x <= SOFT_SHADOW_SAMPLES; x++) {
        for (int y = -SOFT_SHADOW_SAMPLES; y <= SOFT_SHADOW_SAMPLES; y++) {
            vec2 offset = vec2(float(x), float(y)) * texel;
            float depthSample = texture2D(shadowtex0, shadowScreen.xy + offset).r;
            lit += (shadowScreen.z - SHADOW_BIAS > depthSample) ? 0.0 : 1.0;
            total += 1.0;
        }
    }
    float shadowValue = lit / total;

    // Weich zur Schattenreichweite hin ausblenden (siehe Kommentar oben) -
    // die letzten 20% der Distanz blenden Richtung 1.0 (kein Schatten) statt
    // am Frustum-Rand hart umzuschalten.
    float distFade = 1.0 - smoothstep(shadowDistance * 0.8, shadowDistance, length(fragViewPos));
    return mix(1.0, shadowValue, distFade);
}

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;

    // Alpha-Test für Gras-/Blätter-Cutouts.
    if (albedo.a < 0.1) discard;

    vec3 N = normalize(viewNormal);
    vec3 viewDir = normalize(-viewPos);
    float h = sunHeight();
    vec3 sunColor = getDayNightSunColor(h);

    float NdotL = max(dot(N, normalize(shadowLightPosition)), 0.0);
    float shadow = sampleShadow(viewPos, N);
    float directStrength = mix(0.15, 1.0, dayFactor(h));
    vec3 directLight = sunColor * NdotL * shadow * directStrength;

    float shadowAO = mix(1.0 - SHADOW_AO_STRENGTH, 1.0, shadow);
    vec3 skyLight = getSkyAmbient(h) * SKY_AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y) * shadowAO;

    // Generischer, warm-oranger Torch-Kanal der Vanilla-Lightmap - stellt
    // das (ungefärbte) Licht dar, das von IRGENDEINER Blocklichtquelle in
    // der Nähe auf diese Fläche zurückfällt (z. B. eine Wand neben einer
    // Fackel). Auf der Lichtquelle selbst wird er unten auf 0 gesetzt und
    // durch die passende emissionColor ersetzt, sonst würde z. B. eine
    // Seelenfackel zu einer Orange-Türkis-Mischung statt reinem Türkis.
    vec3 emissionColor = getEmissionColor(blockID);
    float isKnownEmitter = step(0.0001, dot(emissionColor, emissionColor));
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(lmcoord.x, 0.0), 2.6) * 1.6 * TORCH_INTENSITY
                       * (1.0 - isKnownEmitter);

    // Wetness/PBR: bei Regen bekommen Außenflächen (Himmelslicht vorhanden)
    // einen zusätzlichen, engen Glanzlicht-Reflex - simuliert nasses
    // Holz/Stein, ohne eine vollständige Screen-Space-Reflexion zu benötigen.
    // smoothstep() statt eines harten if-Vergleichs, damit der Übergang an
    // Stellen mit wechselndem Himmelslicht (z. B. unter Bäumen/Dächern)
    // weich ausläuft statt eine sichtbare Kante zu erzeugen.
    vec3 L = normalize(shadowLightPosition);
    vec3 Hh = normalize(L + viewDir);
    float wetMask = smoothstep(0.4, 0.7, lmcoord.y);
    float wetSpec = pow(max(dot(N, Hh), 0.0), 28.0) * rainStrength * WETNESS_STRENGTH * shadow * wetMask;

    // Regen dunkelt/entsättigt die Umgebungsbeleuchtung leicht ab.
    vec3 wetTint = mix(vec3(1.0), vec3(0.8, 0.83, 0.9), rainStrength * 0.5);

    vec3 lighting = (directLight + skyLight + torchLight + vec3(0.02)) * wetTint;
    vec3 color = albedo.rgb * lighting + sunColor * wetSpec;

    // Colored Block Emission: bekannte Lichtquellen-Blöcke glühen zusätzlich
    // in ihrer eigenen Farbe, additiv oben drauf (bleibt auch bei Schatten/
    // Nacht gut sichtbar). Der Helligkeitswert der Textur selbst gewichtet
    // mit, damit z. B. bei einer Fackel eher die Flamme glüht als der Stiel.
    if (isKnownEmitter > 0.5) {
        float texBrightness = dot(albedo.rgb, vec3(0.2126, 0.7152, 0.0722));
        color += emissionColor * EMISSION_STRENGTH * (0.35 + 0.65 * texBrightness);
    }

    color = applyFog(color, viewPos);

    // Kategorie für applyTerrainTransition() in composite.fsh: 0.0 = anderer
    // Block (löst nie einen Übergang aus), 0.5 = weicher Boden, 1.0 = Stein.
    float terrainCategory = 0.0;
    if (blockID == ID_TERRAIN_SOFT) terrainCategory = 0.5;
    else if (blockID == ID_TERRAIN_STONE) terrainCategory = 1.0;

    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = vec4(terrainCategory, 0.0, 0.0, 1.0);
}
