#version 120

/* =============================================================================
   gbuffers_water.vsh
   -----------------------------------------------------------------------------
   Eigene, dedizierte Stufe für die GESAMTE transluzente Ebene (Wasser, Eis,
   Glas, Blattglas, Schleim/Honig, Nether-Portal, ...) - das ist, was Iris/
   OptiFine tatsächlich über gbuffers_water schicken, nicht nur Wasser.

   Diese Datei wurde nachträglich ergänzt (statt Wasser über gbuffers_terrain
   laufen zu lassen), weil echte Bild-Refraktion eine bereits vollständig
   fertig gerenderte Opak-Szene in colortex0 braucht, die es innerhalb des
   gbuffers_terrain-Durchlaufs selbst noch nicht geben kann. Iris/OptiFine
   rendern gbuffers_water grundsätzlich NACH dem gesamten undurchsichtigen
   Terrain, deshalb ist das Lesen von colortex0 in gbuffers_water.fsh sicher.

   mc_Entity wird hier gebraucht, damit gbuffers_water.fsh echtes Wasser von
   anderem transluzentem Material unterscheiden kann (siehe block.properties).
   ============================================================================= */

#define ID_WATER 1001.0   // MUSS zu block.properties und gbuffers_water.fsh passen

attribute vec4 mc_Entity;

uniform vec3 cameraPosition;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;   // echte Weltposition, für die Wasserwellen-Phase
varying float isWater;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos    = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    // Wie in gbuffers_terrain.vsh: für Terrain-artige Geometrie ohne eigene
    // Objektmatrix ist gl_Vertex + cameraPosition die echte Weltposition.
    worldPos = gl_Vertex.xyz + cameraPosition;

    isWater = (mc_Entity.x == ID_WATER) ? 1.0 : 0.0;
}
