// gbuffers_basic.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_basic.fsh, shaders/world-1/gbuffers_basic.fsh
// and shaders/world1/gbuffers_basic.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Used for untextured geometry (selection outlines, world border, ...).
// Left unshaded on purpose - low risk, purely cosmetic elements.

varying vec4 vColor;

void main() {
    /* DRAWBUFFERS:0 */
    gl_FragColor = vColor;
}
