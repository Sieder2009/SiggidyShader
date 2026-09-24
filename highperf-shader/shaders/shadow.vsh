#version 120

/* shadow.vsh
   -----------------------------------------------------------------------------
   Rendert die Shadow Map (Tiefe aus Sicht der Sonne/des Mondes). Bewusst OHNE
   Verzerrung (reines ftransform(), kein Distortion-Warp Richtung Kamera) -
   die Schatten-Sampling-Codes in gbuffers_terrain.fsh/gbuffers_water.fsh/
   gbuffers_entities.fsh rechnen ausdrücklich mit unverzerrten 1:1-
   Schattenkoordinaten, das MUSS zu dieser Datei passen.

   Diese Datei wurde nachträglich ergänzt: ursprünglich verließ sich dieses
   Pack auf Iris/OptiFine's eingebauten Standard-Shadow-Pass (der greift,
   wenn shadowtex0/shadowModelView/shadowProjection referenziert werden, aber
   kein eigenes shadow.vsh/.fsh existiert) - das war eine nicht restlos
   verifizierte Annahme. Eine eigene, explizite Shadow-Stufe nimmt dieses
   Risiko komplett raus.
   ============================================================================= */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
