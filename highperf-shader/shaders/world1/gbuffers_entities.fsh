#version 120

/* DRAWBUFFERS:01 */
// Zwei Ausgaben, genau wie gbuffers_terrain.fsh: gl_FragData[0] -> colortex0
// (fertiges Bild), gl_FragData[1] -> colortex1 (Erde/Sand/Kies-vs-Stein-
// Kategorie für applyTerrainTransition() in composite.fsh). Entities sind
// selbst NIE "weicher Boden" oder "Stein" - hier wird also bewusst IMMER 0.0
// (= keine Kategorie) geschrieben. Zwei Gründe, warum das nötig ist, nicht
// nur eine reine gl_FragColor-Ausgabe:
//   1) Ohne eigenes DRAWBUFFERS-Directive würde Iris/OptiFine hier
//      standardmäßig mehrere colortex-Buffer binden (seit gbuffers_terrain.fsh
//      colortex1 nutzt), und gl_FragColor würde die Entity-Farbe fälschlich
//      auch nach colortex1 senden (dieselbe Gefahr wie bei Wasser/Regen).
//   2) Ein reines "nichts schreiben" würde colortex1 an dieser Stelle auf dem
//      VERALTETEN Terrain-Wert stehen lassen, den der Terrain-Durchlauf dort
//      VOR dem Entity gezeichnet hat - z. B. ein Mob, der genau vor einer
//      Erde/Stein-Grenze steht, würde dadurch selbst einen (falschen)
//      Übergangs-Farbeinschlag von der Terrain-Nachbarschaft abbekommen. Das
//      explizite 0.0 "räumt" die Kategorie an der Entity-Position korrekt auf.

/* gbuffers_entities.fsh
   -----------------------------------------------------------------------------
   Gleiches Beleuchtungsmodell wie gbuffers_terrain.fsh (Sonne/Mond, PCF-
   Schatten, Himmelslicht, Fackellicht) für Mobs/Spieler/Item-Frames usw.,
   damit sie farblich/lichttechnisch nicht wie ein Fremdkörper wirken.
   Bewusst OHNE Wind (Entities wackeln nicht) und OHNE Colored Block Emission
   (das ist eine block.properties/mc_Entity-Sache, Entities haben keine
   mc_Entity-ID).

   Nebeneffekt: alles, was über diese Datei gerendert wird und hell genug
   ist (z. B. ein Blitzeinschlag, falls dieser über gbuffers_entities läuft),
   profitiert automatisch vom bestehenden Bloom in composite.fsh - das liest
   den fertigen Bildpuffer und ist unabhängig davon, welches gbuffers-
   Programm den hellen Pixel erzeugt hat.

   ambient-Sockel bewusst höher als bei Terrain (0.05 statt 0.02): Mobs/
   Spieler sollen auch im Dunkeln (z. B. in Höhlen) nie komplett schwarz
   wirken - üblicher Shaderpack-Kompromiss zugunsten der Erkennbarkeit.
   ============================================================================= */

const int shadowMapResolution = 2048;   // MUSS zum Wert in gbuffers_terrain.fsh passen
const float shadowDistance    = 140.0;  // dito
#define SOFT_SHADOW_SAMPLES 2
#define SHADOW_BIAS 0.0015

#define SUN_WARMTH      1.05   // [0.8 0.9 1.0 1.05 1.1 1.2]
#define MOON_BRIGHTNESS 0.55   // [0.3 0.4 0.55 0.7 0.9]
#define TORCH_INTENSITY 1.0    // [0.6 0.8 1.0 1.2 1.5]
#define SKY_AMBIENT_STRENGTH 0.55 // [0.3 0.4 0.55 0.7 0.9]
#define SHADOW_AO_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.65]  identisch zu gbuffers_terrain.fsh - siehe dortiger Kommentar

uniform sampler2D tex;
uniform sampler2D shadowtex0;

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;

// -- Tag/Nacht (identisch zu gbuffers_terrain.fsh) --------------------------
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

// -- Schatten (identisch zu gbuffers_terrain.fsh) ---------------------------
float sampleShadow(vec3 fragViewPos, vec3 normal) {
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

    // Weich zur Schattenreichweite hin ausblenden (identisch zu
    // gbuffers_terrain.fsh - siehe dortiger Kommentar) statt am Frustum-Rand
    // hart umzuschalten.
    float distFade = 1.0 - smoothstep(shadowDistance * 0.8, shadowDistance, length(fragViewPos));
    return mix(1.0, shadowValue, distFade);
}

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec3 N = normalize(viewNormal);
    float h = sunHeight();
    vec3 sunColor = getDayNightSunColor(h);

    float NdotL = max(dot(N, normalize(shadowLightPosition)), 0.0);
    float shadow = sampleShadow(viewPos, N);
    float directStrength = mix(0.15, 1.0, dayFactor(h));
    vec3 directLight = sunColor * NdotL * shadow * directStrength;

    float shadowAO = mix(1.0 - SHADOW_AO_STRENGTH, 1.0, shadow);
    vec3 skyLight = getSkyAmbient(h) * SKY_AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y) * shadowAO;
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(lmcoord.x, 0.0), 2.6) * 1.6 * TORCH_INTENSITY;

    vec3 lighting = directLight + skyLight + torchLight + vec3(0.05);
    vec3 color = albedo.rgb * lighting;
    color = applyFog(color, viewPos);

    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = vec4(0.0, 0.0, 0.0, 1.0);
}
