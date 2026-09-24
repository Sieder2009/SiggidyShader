#version 120

#include "/lib/common.glsl"

#define WAVE_HEIGHT 0.10   // [0.0 0.05 0.10 0.15 0.20 0.30]
#define WAVE_SPEED 1.0     // [0.5 0.75 1.0 1.25 1.5]
#define WATER_OPACITY 0.75 // [0.5 0.6 0.7 0.75 0.8 0.9 1.0]

uniform sampler2D tex;
uniform mat4 gbufferModelView;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;
varying float topFace;

// Cheap analytic wave normal via finite differences of a sum-of-sines
// height field - no textures needed, animates with frameTimeCounter.
vec2 waveGradient(vec2 p, float t) {
    float e = 0.35;
    float h0 = sin(p.x * 0.9 + t) * cos(p.y * 0.7 - t * 0.8);
    float hx = sin((p.x + e) * 0.9 + t) * cos(p.y * 0.7 - t * 0.8);
    float hy = sin(p.x * 0.9 + t) * cos((p.y + e) * 0.7 - t * 0.8);
    return vec2(hx - h0, hy - h0) / e;
}

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;

    vec3 N = normalize(viewNormal);

    if (topFace > 0.5) {
        float t = frameTimeCounter * WAVE_SPEED;
        vec2 grad = waveGradient(worldPos.xz * 0.25, t) * WAVE_HEIGHT;
        // grad is a WORLD-space tilt (from worldPos.xz); N is a VIEW-space
        // normal. Rotate the tilt into view space before combining, or the
        // wave bump points the wrong way as soon as the camera yaws/pitches.
        vec3 viewTilt = mat3(gbufferModelView) * vec3(grad.x, 0.0, grad.y);
        N = normalize(N + viewTilt);
    }

    float shadowTerm = sampleShadow(viewPos, N);
    vec3 color = shadeLitCustom(albedo.rgb, N, viewPos, lmcoord, shadowTerm);

    vec3 viewDir = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 H = normalize(L + viewDir);
    float spec = pow(max(dot(N, H), 0.0), 90.0) * shadowTerm;
    color += getDayNightSunColor(sunHeight()) * spec * 1.5;

    float fresnel = pow(1.0 - clamp(dot(N, viewDir), 0.0, 1.0), 5.0);
    color = mix(color, getSkyAmbient(sunHeight()), fresnel * 0.55);

    float alpha = clamp(albedo.a + fresnel * 0.3, 0.0, 1.0) * WATER_OPACITY;

    color = applyFog(color, viewPos);

    gl_FragColor = vec4(color, alpha);
}
