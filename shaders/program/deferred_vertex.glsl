// deferred.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/deferred.vsh, shaders/world-1/deferred.vsh
// and shaders/world1/deferred.vsh, which only set AURORA_WORLD (see lib/common.glsl).

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
