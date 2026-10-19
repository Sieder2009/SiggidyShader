// composite.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/composite.fsh, shaders/world-1/composite.fsh
// and shaders/world1/composite.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

// Reconstructs the VIEW-SPACE ray direction for this screen pixel at the
// far plane. Deliberately left in view space (not transformed to
// world/scene space) so it can be dotted directly against sunPosition /
// moonPosition / upPosition, which Iris/OptiFine also provide in view space.
vec3 getViewRay() {
    vec4 clip = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    view /= view.w;
    return normalize(view.xyz);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    if (depth >= 1.0) {
#if AURORA_WORLD == -1
        // The Nether has no sky: the void past the render distance shows
        // vanilla's fog color, so it blends into the fogged terrain.
        color = fogColor;
#else
        color = renderSky(getViewRay());
        // Blindness / Darkness black out the sky, like in vanilla.
        color *= 1.0 - clamp(max(blindness, darknessFactor), 0.0, 1.0);
#endif
    }

    gl_FragColor = vec4(color, 1.0);
}
