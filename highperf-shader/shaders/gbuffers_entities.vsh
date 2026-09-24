#version 120

/* gbuffers_entities.vsh
   -----------------------------------------------------------------------------
   Mobs, Spieler, Item-Frames, Bilder usw. WICHTIG: anders als Terrain haben
   Entities eine ECHTE Objekt-/Rotationsmatrix (ein Mob dreht/bewegt sich
   unabhängig von der Kamera) - deshalb hier KEIN "gl_Vertex + cameraPosition
   = Weltposition"-Kurzschluss wie in gbuffers_terrain.vsh (dort ausdrücklich
   als nur-für-Terrain-gültig dokumentiert). gl_ModelViewMatrix/gl_NormalMatrix
   berücksichtigen die Entity-Transformation bereits korrekt.
   ============================================================================= */

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos    = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
}
