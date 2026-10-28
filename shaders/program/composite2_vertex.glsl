// composite2.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/composite2.vsh, shaders/world-1/composite2.vsh
// and shaders/world1/composite2.vsh, which only set AURORA_WORLD (see lib/common.glsl).

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
