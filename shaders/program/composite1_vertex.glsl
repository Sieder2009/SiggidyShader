// composite1.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/composite1.vsh, shaders/world-1/composite1.vsh
// and shaders/world1/composite1.vsh, which only set AURORA_WORLD (see lib/common.glsl).

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
