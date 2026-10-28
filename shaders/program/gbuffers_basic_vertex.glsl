// gbuffers_basic.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_basic.vsh, shaders/world-1/gbuffers_basic.vsh
// and shaders/world1/gbuffers_basic.vsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    vColor = gl_Color;
    gl_Position = taaJitter(gl_Position); // TAA sub-pixel shift (common.glsl)
}
