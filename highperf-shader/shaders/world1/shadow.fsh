#version 120

/* shadow.fsh
   -----------------------------------------------------------------------------
   Reiner Tiefen-Durchlauf für die Shadow Map. Alpha-Test, damit Gras/Blätter/
   Cutout-Blöcke eine passend geformte Schattensilhouette werfen statt eines
   vollen Quadrats.
   ============================================================================= */

uniform sampler2D tex;

varying vec2 texcoord;

void main() {
    if (texture2D(tex, texcoord).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
