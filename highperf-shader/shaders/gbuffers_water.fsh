#version 120

/* DRAWBUFFERS:0 */
// Explizit auf NUR colortex0 begrenzt. Seit gbuffers_terrain.fsh eine zweite
// Ausgabe (colortex1, Erde/Sand/Kies-vs-Stein-Kategorie) hat, würde Iris/
// OptiFine OHNE dieses Directive hier standardmäßig die ersten 8 vorhandenen
// colortex-Buffer binden (nicht nur colortex0!) - und gl_FragColor sendet
// seinen Wert an ALLE gebundenen Ziele. Ohne dieses Directive würde also
// JEDES Wasser-/Glas-/Eis-Fragment seine eigene Farbe in colortex1
// hineinschreiben und die Terrain-Kategorie darunter mit einem praktisch
// zufälligen Wert überschreiben - genau an jeder Uferlinie.

/* =============================================================================
   gbuffers_water.fsh
   -----------------------------------------------------------------------------
   Diese Stufe rendert die GESAMTE transluzente Ebene (Wasser, Eis, Glas,
   Blattglas, Schleim/Honig, Nether-Portal, ...), nicht nur Wasser - deshalb
   wird hier IMMER zuerst die echte Blocktextur gesampelt und normal
   beleuchtet; NUR für als Wasser erkannte Fragmente (isWater, siehe
   gbuffers_water.vsh + block.properties) kommt zusätzlich die aufwendige
   Wellen-/Fresnel-/Refraktions-Behandlung obendrauf.

   WARUM EINE EIGENE DATEI (und nicht wie ursprünglich über gbuffers_terrain,
   dessen Fallback-Kette Wasser normalerweise übernehmen würde)?
   Weil `uniform sampler2D colortex0` gleichzeitig lesen UND (als Ziel von
   gl_FragColor) beschreiben, INNERHALB DESSELBEN Zeichenaufrufs/derselben
   Stufe, laut OpenGL-Spezifikation ein undefiniertes "Rendering Feedback
   Loop" ist - anders als der scheinbar ähnliche Fall in composite.fsh, wo
   Iris/OptiFine colortex0 zwischen zwei GETRENNTEN physischen Texturen
   hin- und herschaltet (Lese- und Schreib-Textur sind dort nie identisch).
   Iris/OptiFine rendern gbuffers_water grundsätzlich als eigenen, späteren
   Durchlauf NACH dem kompletten undurchsichtigen Terrain - der Hintergrund
   in colortex0 ist an dieser Stelle also bereits fertig und abgeschlossen,
   und das Sampling hier ist damit sicher (dieselbe Technik, die reale
   Shaderpacks für Wasser-Refraktion verwenden).
   ============================================================================= */

// ---------------------------------------------------------------------------
// Einstellungen - im Iris/OptiFine Shader-Options-Menü direkt anpassbar
// ---------------------------------------------------------------------------
#define SOFT_SHADOW_SAMPLES 2
#define SHADOW_BIAS 0.0015
const int shadowMapResolution = 2048;   // MUSS zum Wert in gbuffers_terrain.fsh passen (eine gemeinsame Shadow Map)
const float shadowDistance    = 140.0;  // dito

// Bewusst identisch zu gbuffers_terrain.fsh, damit Sonnen-/Mondlicht auf
// Wasser/Glas/Eis und Land gleich aussehen (siehe Hinweis zu duplizierten
// Hilfsfunktionen oben in gbuffers_terrain.fsh). SKY_AMBIENT_STRENGTH < 1
// verhindert, dass Himmelslicht + direktes Licht in Summe weit über 1.0
// steigen - sonst läuft alles beim Tonemapping Richtung Weiß/entsättigt.
#define SUN_WARMTH      1.05   // [0.8 0.9 1.0 1.05 1.1 1.2]
#define MOON_BRIGHTNESS 0.55   // [0.3 0.4 0.55 0.7 0.9]
#define TORCH_INTENSITY 1.0    // [0.6 0.8 1.0 1.2 1.5]
#define SKY_AMBIENT_STRENGTH 0.55 // [0.3 0.4 0.55 0.7 0.9]
#define SHADOW_AO_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.65]  identisch zu gbuffers_terrain.fsh - siehe dortiger Kommentar (gilt für shadeGeneric(), NICHT für echtes Wasser)

#define WATER_WAVE_HEIGHT 0.06          // [0.0 0.03 0.06 0.09 0.12]  Stärke der Wellen-Normale
#define WATER_WAVE_SPEED  1.0           // [0.5 0.75 1.0 1.3 1.6]
#define WATER_REFRACTION_STRENGTH 0.035 // [0.0 0.02 0.035 0.05 0.08]  Verzerrung des Hintergrunds
#define WATER_DEEP_COLOR    vec3(0.01, 0.11, 0.15)  // Wasserfarbe (sattes, tiefes Petrol/Smaragd statt zuvor blasserem Ton)
// Echte, TIEFENABHÄNGIGE Absorption (Beer-Lambert) statt eines festen
// Prozentsatzes: WATER_EXTINCTION ist die "Trübung pro Block" - flaches
// Wasser (kurze Durchquerungsstrecke) bleibt dadurch durchsichtig genug, um
// den Boden zu sehen, tiefes/unbegrenztes Wasser (z. B. offener Ozean ohne
// sichtbaren Grund) wird asymptotisch Richtung WATER_DEEP_COLOR gezogen.
// Ohne diesen Tiefenbezug (der vorherige, feste WATER_ABSORPTION-Wert) sah
// ein 30cm tiefer Teich genauso undurchsichtig aus wie tiefer Ozean.
// WICHTIG zur Kalibrierung: ein üblicher Minecraft-Ozean/-See ist eher
// 15-30 Blöcke tief, nicht nur 2-3. Bei 0.18 wäre 1-exp(-Tiefe*0.18) dort
// schon bei 0.97-0.995 - undurchsichtiger als der alte feste Wert (0.7),
// nicht durchsichtiger! 0.07 hält typische Seen/Ozeane bei ca. 0.65-0.88
// (klar durchsichtiger als vorher), während flache Teiche (2-3 Blöcke)
// weiterhin gut durchsichtig bleiben (~0.15-0.2) und nur wirklich
// unbegrenztes/sehr tiefes Wasser Richtung 1.0 sättigt.
#define WATER_EXTINCTION 0.07   // [0.03 0.05 0.07 0.1 0.15]  Trübung pro Block Durchquerungstiefe
#define WATER_REFLECTION_TINT 0.35       // [0.0 0.1 0.22 0.35 0.5]  wie stark die Himmelsspiegelung Richtung WATER_DEEP_COLOR eingefärbt wird (verhindert reinweiße Spiegelung)
#define WATER_SPECULAR_STRENGTH 1.2      // [0.4 0.6 0.9 1.2 1.6]    Stärke des Sonnen-/Mond-Glanzlichts auf dem Wasser
#define WATER_FRESNEL_FLOOR 0.05         // [0.02 0.05 0.08 0.12 0.18]  Mindest-Reflexionsanteil auch bei senkrechtem Blick auf die Oberfläche

// -- Regen-Reaktion --
#define RAIN_WAVE_BOOST     1.8   // [1.0 1.3 1.6 1.8 2.2 2.6]  wie viel unruhiger/höher die Wellen bei Regen werden
#define RAIN_RIPPLE_STRENGTH 0.18 // [0.0 0.1 0.18 0.28 0.4]    Helligkeit der Regentropfen-Ringe

uniform sampler2D tex;
uniform sampler2D colortex0;    // bereits fertig gerenderte, undurchsichtige Szene - siehe Kommentar oben
uniform sampler2D shadowtex0;
uniform sampler2D depthtex1;    // Iris/OptiFine-Standard: Tiefe der undurchsichtigen Szene VOR dieser transluzenten Stufe - für die echte, tiefenabhängige Wasser-Absorption (siehe WATER_EXTINCTION)

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelView;         // Welt-Wellen-Neigung -> Sichtraum rotieren
uniform mat4 gbufferModelViewInverse;  // Sichtraum-Position/-Normale -> Schattenraum
uniform mat4 gbufferProjectionInverse; // Tiefenwert -> Sichtraum-Position (für die Wassertiefen-Rekonstruktion)

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;

uniform float frameTimeCounter;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;
varying float isWater;

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

// -- Wasserwellen: Gradient eines Sinus-Musters aus zwei Frequenzen --------
float waveHeight(vec2 p, float t) {
    return sin(p.x * 0.8 + t) * cos(p.y * 0.6 - t * 0.7) * 0.65
         + sin(p.x * 2.1 - t * 1.4) * 0.35;
}
vec2 waveGradient(vec2 p, float t) {
    float e = 0.4;
    float h0 = waveHeight(p, t);
    float hx = waveHeight(p + vec2(e, 0.0), t);
    float hy = waveHeight(p + vec2(0.0, e), t);
    return vec2(hx - h0, hy - h0) / e;
}

// -- Regentropfen-Ringe -------------------------------------------------
// Kein echtes Partikelsystem nötig: pro Gitterzelle taucht periodisch ein
// expandierender Ring an einer zufälligen Position auf (Zeit + Zellposition
// gehasht). rainStrength ist ein UNIFORM (für jedes Fragment gleich), daher
// ist "if (rainStrength > 0.01)" am Aufrufort ein günstiger, komplett
// divergenzfreier Branch - bei Trockenheit kostet diese Funktion nichts.
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float rainRipples(vec2 p, float t) {
    // Weit vom Weltursprung entfernt (schon ab ein paar tausend Blöcken,
    // im normalen Spiel leicht erreicht) verliert `cell * (großer Hash-
    // Faktor)` bei float32-Genauigkeit fast alle Nachkommastellen, und die
    // Ringe würden einfrieren/sich wiederholen. p hier auf ein großes, aber
    // begrenztes Kachel-Intervall falten behebt das - p kommt bereits mit
    // Faktor 2.0 herein (Aufrufer übergibt worldPos.xz * 2.0), der
    // entstehende Nahtübergang liegt also alle 4096/2.0 = 2048 echte
    // Weltblöcke und ist damit praktisch nie sichtbar.
    p = mod(p, 4096.0);

    float result = 0.0;
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            vec2 cell = floor(p) + vec2(float(ox), float(oy));
            float seed = hash21(cell);
            float cycle = fract(t * 0.35 + seed); // 0..1, wiederholt sich pro Zelle
            vec2 dropPos = cell + vec2(hash21(cell + 3.7), hash21(cell + 9.1));
            float dist = length(p - dropPos);
            // Radius bewusst auf max. 1 Zelle begrenzt (statt z. B. 1.4) -
            // so kann ein Ring nie über den Rand der 3x3-Nachbarschaft
            // hinauswachsen, die hier durchsucht wird, und es entsteht kein
            // sichtbarer Schnitt/Sprung an Zellgrenzen.
            float radius = cycle * 1.0;
            float ringWidth = 0.05 + cycle * 0.05;
            float ring = 1.0 - smoothstep(0.0, ringWidth, abs(dist - radius));
            float fade = (1.0 - cycle) * step(dist, radius + 0.2);
            result += ring * fade;
        }
    }
    return clamp(result, 0.0, 1.0);
}

// Gemeinsame Beleuchtung (Sonne/Mond + Himmelslicht + Fackellicht), identisch
// zum Terrain-Modell - genutzt für ALLES außer echtem Wasser (Eis, Glas,
// Blattglas, Schleim/Honig, ...), damit diese Blöcke normal aussehen statt
// wie dunkles Wasser.
vec3 shadeGeneric(vec3 albedo, vec3 N, float shadow) {
    float h = sunHeight();
    vec3 sunColor = getDayNightSunColor(h);

    float NdotL = max(dot(N, normalize(shadowLightPosition)), 0.0);
    float directStrength = mix(0.15, 1.0, dayFactor(h));
    vec3 directLight = sunColor * NdotL * shadow * directStrength;

    float shadowAO = mix(1.0 - SHADOW_AO_STRENGTH, 1.0, shadow);
    vec3 skyLight = getSkyAmbient(h) * SKY_AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y) * shadowAO;
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(lmcoord.x, 0.0), 2.6) * 1.6 * TORCH_INTENSITY;

    return albedo * (directLight + skyLight + torchLight + vec3(0.02));
}

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    vec3 N = normalize(viewNormal);
    vec3 viewDir = normalize(-viewPos);
    float shadow = sampleShadow(viewPos, N);

    vec3 color;
    float alpha;

    if (isWater > 0.5) {
        // ================= ECHTES WASSER =================
        // Bei Regen: deutlich unruhigere Wellen (mehr Amplitude + eine
        // zusätzliche, höherfrequente Kräuselung), passend zur Vorgabe "auf
        // Seen/Flüssen ruhig, bei Regen/Gewitter stärker".
        //
        // WICHTIG: t bleibt IMMER mit konstanter Rate an frameTimeCounter
        // gekoppelt (keine rainStrength-Multiplikation auf die Uhr selbst!).
        // frameTimeCounter akkumuliert unbegrenzt über die Spielsitzung -
        // würde man ihn mit einem sich über Zeit ändernden Faktor
        // multiplizieren (wie hier ursprünglich versucht), ergäbe die
        // Produktregel bei jedem Regen-Start/Stop einen Phasensprung
        // proportional zu frameTimeCounter selbst (nach Minuten Spielzeit
        // ein sichtbares "Strobe"/Flackern der ganzen Wasserfläche). Nur
        // AMPLITUDEN dürfen mit rainStrength skaliert werden (unbedenklich,
        // da gedächtnislos) - deshalb hier ausschließlich rainChop bzw. der
        // letzte Faktor 0.6*rainStrength der Zusatzschicht.
        float t = frameTimeCounter * WATER_WAVE_SPEED;
        float rainChop = mix(1.0, RAIN_WAVE_BOOST, rainStrength);
        vec2 grad = waveGradient(worldPos.xz * 0.25, t) * WATER_WAVE_HEIGHT * rainChop;

        // Zusätzliche, höherfrequente Kräuselung nur bei Regen (Tropfen-
        // Unruhe) - feste Geschwindigkeit (t * 2.3, NICHT rainStrength-
        // abhängig), nur die Amplitude blendet mit rainStrength ein.
        if (rainStrength > 0.01) {
            grad += waveGradient(worldPos.xz * 1.4, t * 2.3 + 17.0) * WATER_WAVE_HEIGHT * 0.6 * rainStrength;
        }

        // grad ist eine WELT-Neigung (worldPos.xz) - N liegt in Sichtraum vor,
        // also erst mit derselben Rotation wie gl_NormalMatrix (~gbufferModelView
        // für Terrain-artige Geometrie) in den Sichtraum drehen.
        vec3 waveTiltView = mat3(gbufferModelView) * vec3(grad.x, 0.0, grad.y);
        N = normalize(N + waveTiltView);

        // Fresnel (Schlick-Näherung): flacher Blickwinkel = starke Reflexion.
        // WATER_FRESNEL_FLOOR > 0 sorgt dafür, dass auch bei fast senkrechtem
        // Blick (NdotV~1) noch ein bisschen Himmels-/Umgebungsreflexion zu
        // sehen ist, statt bei 0.02 fast unsichtbar zu werden.
        float NdotV = clamp(dot(N, viewDir), 0.0, 1.0);
        float fresnel = mix(WATER_FRESNEL_FLOOR, 1.0, pow(1.0 - NdotV, 5.0));

        vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

        // Echte Wassertiefe: depthtex1 enthält die Tiefe der Szene OHNE
        // transluzente Objekte (Iris/OptiFine füllt das automatisch kurz
        // bevor diese Stufe läuft) - an derselben Bildschirmposition ist das
        // also der Boden UNTER diesem Wasser-Fragment. Beide Tiefenwerte in
        // Sichtraum-Positionen zurückrechnen (Standardtechnik, wie
        // reconstructViewRay() in composite.fsh) und deren Abstand als
        // Durchquerungsstrecke fürs Beer-Lambert-Gesetz nutzen.
        float floorDepthSample = texture2D(depthtex1, screenUV).r;
        vec4 floorClip = vec4(screenUV * 2.0 - 1.0, floorDepthSample * 2.0 - 1.0, 1.0);
        vec4 floorViewP = gbufferProjectionInverse * floorClip;
        floorViewP /= floorViewP.w;
        float waterDepth = length(floorViewP.xyz - viewPos);
        float depthAbsorb = clamp(1.0 - exp(-waterDepth * WATER_EXTINCTION), 0.0, 1.0);

        // Refraktion: den bereits fertigen, undurchsichtigen Hintergrund
        // leicht entlang der Wellen-Normale verschoben abgreifen (siehe
        // Datei-Kommentar oben zur Sicherheit dieses Zugriffs).
        vec2 refractedUV = clamp(screenUV + N.xy * WATER_REFRACTION_STRENGTH, 0.001, 0.999);
        vec3 background = texture2D(colortex0, refractedUV).rgb;

        // WATER_DEEP_COLOR ist die Eigenfarbe/Trübung des Wassers - OHNE
        // Tag/Nacht-Bezug wäre das die einzige Fläche im ganzen Pack, die
        // nachts genauso hell wie mittags aussieht (tiefes Wasser hätte sich
        // dadurch praktisch NIE verändert, egal zu welcher Tageszeit). Mit
        // demselben dayFactor()-Faktor gedämpft wie der Rest der Beleuchtung -
        // 0.4 als Bodenwert, damit tiefes Wasser nachts nicht auf Schwarz fällt.
        vec3 deepColorLit = WATER_DEEP_COLOR * mix(0.4, 1.0, dayFactor(sunHeight()));

        // Lichtabsorption nach der ECHTEN Tiefe (depthAbsorb, siehe oben):
        // flaches Wasser lässt den Boden durchscheinen, tiefes/unbegrenztes
        // Wasser wird Richtung deepColorLit gezogen.
        vec3 refracted = mix(background, deepColorLit, depthAbsorb);

        // Echtes Wasser spiegelt nie den Himmel als reinen, unveränderten
        // Weiß-/Blauton - ein Rest der Wasser-Eigenfarbe bleibt auch in der
        // Reflexion sichtbar (Sub-Surface-/Trübungs-Effekt). Ohne diesen
        // Tint sieht die Wasseroberfläche bei flachem Blickwinkel (der beim
        // normalen Spielen sehr häufige Fall) wie eine fast weiße Fläche aus.
        vec3 reflected = mix(getSkyAmbient(sunHeight()), deepColorLit, WATER_REFLECTION_TINT);

        vec3 L = normalize(shadowLightPosition);
        vec3 Hh = normalize(L + viewDir);
        float spec = pow(max(dot(N, Hh), 0.0), 130.0) * shadow;

        color = mix(refracted, reflected, fresnel) + getDayNightSunColor(sunHeight()) * spec * WATER_SPECULAR_STRENGTH;

        // Regentropfen-Ringe: kleine, helle Kringel-Highlights auf der
        // Oberfläche, nur bei Regen (kostenlos wenn trocken, siehe Kommentar
        // bei rainRipples()).
        if (rainStrength > 0.01) {
            float ripples = rainRipples(worldPos.xz * 2.0, frameTimeCounter) * rainStrength;
            color += vec3(0.55, 0.65, 0.70) * ripples * RAIN_RIPPLE_STRENGTH;
        }

        alpha = mix(0.75, 1.0, fresnel);
    } else {
        // ============ EIS / GLAS / BLATTGLAS / SCHLEIM / HONIG / ... ============
        // Ganz normal texturiert und beleuchtet wie Terrain, nur eben
        // (halb-)transparent mit der jeweils eigenen Textur-Alpha.
        color = shadeGeneric(albedo.rgb, N, shadow);
        alpha = albedo.a;
    }

    color = applyFog(color, viewPos);
    gl_FragColor = vec4(color, alpha);
}
