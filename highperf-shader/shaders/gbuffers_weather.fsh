#version 120

/* DRAWBUFFERS:0 */
// Explizit auf NUR colortex0 begrenzt - siehe identischer Kommentar in
// gbuffers_water.fsh (seit gbuffers_terrain.fsh eine zweite Ausgabe/colortex1
// hat, würde Iris/OptiFine hier sonst standardmäßig mehrere Buffer binden und
// gl_FragColor würde die Regen-/Schneefarbe fälschlich auch dorthin senden).

/* gbuffers_weather.fsh
   -----------------------------------------------------------------------------
   Regen-/Schnee-Streifen. Bewusst UNBELEUCHTET (kein Sonnen-/Schatten-Modell)
   - Regentropfen-Sprites haben keine brauchbaren Normalen, reale Shaderpacks
   färben sie i. d. R. nur ein und lassen sie mit dem Nebel verschmelzen,
   statt sie wie Terrain zu beleuchten.
   ============================================================================= */

#define RAIN_TINT_STRENGTH 0.35 // [0.0 0.2 0.35 0.5 0.7]  wie stark Richtung Nebelfarbe eingefärbt wird
#define RAIN_OPACITY        1.15 // [0.8 1.0 1.15 1.3 1.5]  Deckkraft-Multiplikator (Regen/Schnee sichtbarer machen)

uniform sampler2D tex;

varying vec2 texcoord;
varying vec4 vColor;
varying vec3 viewPos;

vec3 applyFog(vec3 color, vec3 fragViewPos) {
    float dist = length(fragViewPos);
    float fogFactor = clamp((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 1.0), 0.0, 1.0);
    fogFactor *= fogFactor;
    return mix(color, gl_Fog.color.rgb, fogFactor);
}

void main() {
    vec4 color = texture2D(tex, texcoord) * vColor;
    if (color.a < 0.01) discard;

    // Leichte Einfärbung Richtung Nebelfarbe, damit Regen/Schnee wie Teil
    // der Atmosphäre wirkt statt wie ein aufgesetztes Overlay.
    color.rgb = mix(color.rgb, gl_Fog.color.rgb, RAIN_TINT_STRENGTH * 0.5);
    color.a = clamp(color.a * RAIN_OPACITY, 0.0, 1.0);

    color.rgb = applyFog(color.rgb, viewPos);

    gl_FragColor = color;
}
