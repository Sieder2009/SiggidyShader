#version 120

/* =============================================================================
   gbuffers_terrain.vsh
   -----------------------------------------------------------------------------
   Vertex-Stufe für sämtliche Terrain-Geometrie (Blöcke, KEIN Wasser mehr -
   Wasser hat eine eigene gbuffers_water.vsh/.fsh, siehe dort für den Grund:
   echte Refraktion braucht eine bereits fertig gerenderte Opak-Szene, die es
   innerhalb dieses einen Terrain-Durchlaufs noch nicht gibt).

   Aufgaben hier:
     1. Block-Erkennung (Gras+Blumen / Blätter / Lichtquellen) über das
        Attribut mc_Entity - dafür MUSS die mitgelieferte block.properties
        vorhanden sein, sonst ist mc_Entity.x für jeden Block -1.0 und nichts
        greift.
     2. Wind-Animation: Gras/Blumen wackeln nur an der Spitze (erkannt über
        mc_midTexCoord, den Mittelpunkt der Textur), Blätter wackeln als
        Ganzes, aber schwächer.
     3. Block-ID als Varying weiterreichen, damit gbuffers_terrain.fsh
        Lichtquellen (Fackel, Glowstone, Lava, ...) individuell einfärben
        kann (Colored Block Emission).
     4. Weiterreichen von Position/Normale/UV/Vertexfarbe an die Fragment-Stufe.

   Bekannte Einschränkung: bei zweistöckigen Pflanzen (z. B. tall_grass,
   sunflower) besteht die Pflanze aus zwei unabhängigen Blöcken mit je einem
   eigenen mc_midTexCoord. Die Ober-/Unter-Erkennung läuft pro Block, nicht
   über die ganze Pflanze - am Übergang zwischen den beiden Blöcken kann das
   Wackeln daher einen leichten, sichtbaren Knick zeigen statt eines
   durchgehend weichen Verlaufs. Für eine saubere Lösung bräuchte es
   zusätzliche block.properties-Einträge je Blockstate (half=upper/lower),
   die hier bewusst weggelassen wurden, um die Komplexität zu begrenzen.
   ============================================================================= */

// ---------------------------------------------------------------------------
// Einstellungen - über das Iris/OptiFine Shader-Options-Menü anpassbar
// ---------------------------------------------------------------------------
#define WIND_STRENGTH 0.09   // [0.0 0.04 0.06 0.09 0.12 0.18]  Stärke des Wind-Wackelns
#define WIND_SPEED    1.0    // [0.5 0.75 1.0 1.3 1.6]          Windgeschwindigkeit

// Block-IDs - MÜSSEN exakt zu block.properties und zu gbuffers_terrain.fsh passen.
#define ID_FOLIAGE 1002.0   // Gras, Blumen, Ranken: nur die obere Hälfte bewegt sich
#define ID_LEAVES  1003.0   // Blätter: der ganze Block wackelt sanft mit

// ---------------------------------------------------------------------------
// Von Iris/OptiFine bereitgestellte Zusatz-Attribute (benötigen block.properties
// bzw. sind immer vorhanden)
// ---------------------------------------------------------------------------
attribute vec4 mc_Entity;       // .x = benutzerdefinierte Block-ID aus block.properties
attribute vec4 mc_midTexCoord;  // Mittelpunkt der Textur im Atlas (für Gras-Spitzen-Erkennung)

uniform float frameTimeCounter;
uniform vec3 cameraPosition;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;   // echte Weltposition, für die Windphase
varying float blockID;   // mc_Entity.x, für farbige Lichtquellen-Erkennung im Fragment-Shader

// Billige Wind-Wellenfunktion aus zwei überlagerten Sinusquellen (kein
// Perlin-/Simplex-Noise nötig - für sanftes Wackeln völlig ausreichend und
// sehr performant).
vec2 windOffset(vec3 pos, float phase) {
    float t = frameTimeCounter * WIND_SPEED;
    float w1 = sin(pos.x * 0.6 + pos.z * 0.4 + t + phase);
    float w2 = sin(pos.x * 1.7 - pos.z * 1.1 + t * 1.7 + phase * 2.0);
    return vec2(w1 * 0.7 + w2 * 0.3, w1 * 0.4 - w2 * 0.2);
}

void main() {
    vec4 pos = gl_Vertex;

    // Terrain hat (anders als Entities!) keine eigene Objekt-/Modellmatrix -
    // gl_Vertex liegt bereits "kamerarelativ, aber nicht kameragedreht" vor.
    // + cameraPosition ergibt daraus die echte, absolute Weltposition. WICHTIG:
    // dieser Kurzschluss gilt NUR hier in gbuffers_terrain, NICHT in
    // gbuffers_entities/gbuffers_hand (dort gibt es eine echte Rotation).
    // Wird VOR der Wind-Verschiebung berechnet, damit die Windphase pro
    // Vertex stabil bleibt (unabhängig von der eigenen Verschiebung).
    worldPos = pos.xyz + cameraPosition;

    // Direkt in die Varying schreiben statt in eine gleichnamige lokale
    // Variable - eine lokale "float blockID = ..." würde die Varying
    // verdecken (Shadowing) und im Fragment-Shader käme dann für jeden
    // Block derselbe (Default-)Wert an.
    blockID = mc_Entity.x;

    if (blockID == ID_FOLIAGE) {
        // Kreuz-Modelle (Gras/Blumen): nur die obere Hälfte bewegt sich.
        // mc_midTexCoord.t ist die V-Koordinate der Textur-Mitte; V wächst
        // nach unten, also ist "obere Pflanzenhälfte" = kleineres V als die Mitte.
        float isTop = step(gl_MultiTexCoord0.t, mc_midTexCoord.t);
        vec2 sway = windOffset(worldPos, 0.0) * WIND_STRENGTH * isTop;
        pos.xz += sway;
    } else if (blockID == ID_LEAVES) {
        // Volle Blöcke: schwächeres, gleichmäßiges Wackeln über den ganzen Block.
        vec2 sway = windOffset(worldPos, 1.7) * WIND_STRENGTH * 0.4;
        pos.xz += sway;
    }

    // ACHTUNG: ftransform() würde IMMER das unveränderte gl_Vertex benutzen
    // und die Wind-Verschiebung ignorieren - deshalb hier die Matrizen von
    // Hand anwenden.
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * pos;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos    = (gl_ModelViewMatrix * pos).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
}
