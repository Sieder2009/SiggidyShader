// gbuffers_lightning.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_lightning.fsh, shaders/world-1/gbuffers_lightning.fsh
// and shaders/world1/gbuffers_lightning.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Lightning bolts. Without this program Iris draws them with
// gbuffers_entities, which lights them like a mob, so a bolt in a stormy
// night came out as a dim grey-blue ribbon. A bolt is light: its plain,
// untextured vertex color goes out as-is, several times over 1.0, so the
// layered, additively blended bolt flares in composite1's bloom.

varying vec4 vColor;

void main() {
    /* DRAWBUFFERS:0 */
    gl_FragColor = vec4(vColor.rgb * 4.0, vColor.a);
}
