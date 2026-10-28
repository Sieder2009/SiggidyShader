// composite.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/composite.fsh, shaders/world-1/composite.fsh
// and shaders/world1/composite.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

#define LIGHT_SHAFTS // Beams of sun and moon light in the air ("god rays"), e.g. through leaves or past a hill at sunset. Needs shadows. Off in the Low and Potato profiles.
#define LIGHT_SHAFT_SAMPLES 8    // [6 8 12 16] Steps per pixel along the view ray: more = smoother beams, but slower.
#define LIGHT_SHAFT_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// Runs after water and glass. The sky itself is painted earlier, in
// deferred1.fsh, so that translucent blocks blend over it; this pass adds
// what needs the finished picture: depth color and reflections for water,
// then the light shafts.

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

varying vec2 texcoord;

// Light shafts read the shadow map, which only exists in the Overworld with
// shadows on (the End's light comes from a fixed point overhead, the Nether
// has none).
#ifdef LIGHT_SHAFTS
    #ifdef AURORA_SHADOWS
        #if AURORA_WORLD == 0
            #define AURORA_LIGHT_SHAFTS 1
        #endif
    #endif
#endif

// Reconstructs the VIEW-SPACE position of this pixel from the depth buffer.
// Kept in view space (not world/scene space) so it can be dotted directly
// against sunPosition / moonPosition / upPosition, which Iris/OptiFine also
// provide in view space. For the sky (depth 1) this is a point on the far
// plane, i.e. its direction is the sky ray.
vec3 getViewPos(float depth) {
    vec4 clip = vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

#ifdef AURORA_SSR
// View-space z of the opaque surface (no water/glass) at uv.
float opaqueZ(vec2 uv) {
    vec4 view = gbufferProjectionInverse * vec4(0.0, 0.0, texture2D(depthtex1, uv).r * 2.0 - 1.0, 1.0);
    return view.z / view.w;
}

vec2 viewToScreen(vec3 p) {
    vec4 clip = gbufferProjection * vec4(p, 1.0);
    return clip.xy / clip.w * 0.5 + 0.5;
}

// Screen-space reflection: follow the reflected ray through view space in
// growing steps; as soon as it slips behind the visible (opaque) surface,
// home in on the crossing with a few halving steps and take the picture's
// color there. Returns rgb + how much to trust it (0 = no hit: the ray left
// the screen, went toward the camera, or only passed into the sky).
vec4 traceReflection(vec3 start, vec3 dir) {
    float stepLength = 0.3 + length(start) * 0.02;
    vec3 p = start + dir * (stepLength * effectDither(gl_FragCoord.xy));
    for (int i = 0; i < 24; i++) {
        vec3 prev = p;
        p += dir * stepLength;
        stepLength *= 1.2;
        if (p.z > -0.1) break; // behind the camera: never on screen

        vec2 uv = viewToScreen(p);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

        float behind = opaqueZ(uv) - p.z; // > 0: the ray is behind what's visible there
        if (behind > 0.0) {
            // Much further behind than one step: the ray passed BEHIND a
            // thin object in front (a tree trunk, a post) - keep going.
            if (behind > stepLength * 2.0 + 0.5) continue;
            vec3 a = prev;
            vec3 b = p;
            for (int j = 0; j < 4; j++) {
                vec3 m = (a + b) * 0.5;
                if (opaqueZ(viewToScreen(m)) - m.z > 0.0) b = m; else a = m;
            }
            uv = viewToScreen(b);
            // Fade out toward the screen border, where the picture ends.
            float edge = smoothstep(0.0, 0.08, uv.x) * (1.0 - smoothstep(0.92, 1.0, uv.x))
                       * smoothstep(0.0, 0.08, uv.y) * (1.0 - smoothstep(0.92, 1.0, uv.y));
            return vec4(texture2D(colortex0, uv).rgb, edge);
        }
    }
    return vec4(0.0);
}
#endif

#ifdef AURORA_LIGHT_SHAFTS
// Light shafts, traced through the shadow map: step from the camera toward
// this pixel and test at every step whether the sun/moon reaches that point
// in the air. The lit stretches of the ray scatter some light toward the
// camera; where trees, hills or buildings shade the air, the gaps form the
// beams. Unlike screen-space "god rays" this never projects the sun onto the
// screen, so it keeps working when the sun is off screen or behind the
// camera (the reason earlier versions of this pack left god rays out).
vec3 lightShafts(vec3 viewPos) {
    float h = sunHeight();

    // Hazy air around sunrise and sunset, a clearer sky at noon, a little
    // moonlight at night; rain washes it all out.
    float strength = 0.12 * dayFactor(h) + 0.45 * twilightFactor(h) + 0.08 * nightFactor(h);
    strength *= (1.0 - rainStrength) * LIGHT_SHAFT_STRENGTH;
    // None underground (going by how much sky the camera has seen lately),
    // under water, or while blinded.
    strength *= smoothstep(0.3, 0.8, float(eyeBrightnessSmooth.y) / 240.0);
    strength *= 1.0 - clamp(max(blindness, darknessFactor), 0.0, 1.0);
    if (isEyeInWater != 0 || strength < 0.001) return vec3(0.0);

    // March only as far as the shadow map reaches with some margin, so every
    // step has real shadow data. A shorter ray (looking at the ground right
    // in front of you) crosses less air and gets less haze.
    vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 sceneStart = gbufferModelViewInverse[3].xyz; // the camera
    float rayLength = length(scenePos - sceneStart);
    float maxLength = shadowDistance * 0.85;
    float marchLength = min(rayLength, maxLength);
    vec3 sceneEnd = sceneStart + (scenePos - sceneStart) * (marchLength / max(rayLength, 0.0001));

    // The shadow projection is orthographic, so a straight line in the world
    // is a straight line in shadow clip space: transform the two ends once
    // and interpolate between them (the distortion is applied per step).
    vec3 shadowStart = (shadowProjection * (shadowModelView * vec4(sceneStart, 1.0))).xyz;
    vec3 shadowEnd   = (shadowProjection * (shadowModelView * vec4(sceneEnd, 1.0))).xyz;

    // Steps bunch up near the camera (t = x^2), where shafts are big and
    // detailed; each step is weighted by the stretch of ray it stands for
    // (dt/dx = 2x), so lit ends up as the lit FRACTION of the ray. The
    // per-pixel dither offset turns the remaining stepping into fine noise
    // instead of visible bands.
    float dither = effectDither(gl_FragCoord.xy);
    float lit = 0.0;
    float weightSum = 0.0;
    for (int i = 0; i < LIGHT_SHAFT_SAMPLES; i++) {
        float x = (float(i) + dither) / float(LIGHT_SHAFT_SAMPLES);
        float weight = 2.0 * x;
        weightSum += weight;
        vec3 s = distortShadowClip(mix(shadowStart, shadowEnd, x * x)) * 0.5 + 0.5;
        // A step outside the shadow map counts as unlit rather than lit:
        // no data there must never turn into bright fog.
        if (s.x > 0.0 && s.x < 1.0 && s.y > 0.0 && s.y < 1.0 && s.z < 1.0) {
            lit += shadow2D(shadowtex0, vec3(s.xy, s.z - 0.0005)).r * weight;
        }
    }
    lit /= max(weightSum, 0.0001);

    // Henyey-Greenstein phase function (g = 0.55): the haze glows most when
    // looking toward the light, much less to the side.
    const float g = 0.55;
    float cosAngle = dot(normalize(viewPos), normalize(shadowLightPosition));
    float phase = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosAngle, 1.5);

    vec3 lightColor = getDayNightSunColor(h) * moonDimming(h);
    return lightColor * (lit * (marchLength / maxLength) * phase * strength * 0.1);
}
#endif

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;
    vec3 viewPos = getViewPos(depth);

    // Water, shiny blocks and puddles, seen from above water (from below,
    // vanilla's underwater fog already covers everything).
    vec4 surface = texture2D(colortex2, texcoord);
    int material = materialOf(surface);
    if (isEyeInWater == 0 && depth < 1.0) {
        float reflectivity = 0.0; // how strongly this pixel mirrors at most
        float f0 = 0.02;          // how much it mirrors looking straight at it
        float roughness = 0.0;    // 0 = sharp mirror image
        vec3 tint = vec3(1.0);    // metals color what they reflect

        if (material == MAT_WATER) {
#ifdef AURORA_WATER_FOG
            // The further the view ray travels through the water before it
            // hits the ground, the more of the picture behind is replaced by
            // the water's own deep color: clear shallows, dark blue-green depths.
            float opaqueDepth = texture2D(depthtex1, texcoord).r;
            float thickness = opaqueDepth >= 1.0 ? 64.0 : max(length(getViewPos(opaqueDepth)) - length(viewPos), 0.0);
            float fog = 1.0 - exp(-thickness * WATER_FOG_DENSITY);
            color = mix(color, waterFogColor(surface.b), fog);
#endif
#if defined AURORA_WATER_FOG || defined AURORA_SSR
            // Otherwise (Potato) gbuffers_water mirrors the sky itself.
            reflectivity = 0.9;
#endif
        }
#ifdef AURORA_SHINY_BLOCKS
        else if (material >= MAT_SHINY) {
            float shine = shineOf(surface);
            reflectivity = shine;
            roughness = 1.0 - shine;
            if (material >= MAT_METAL) {
                // Metal: mirrors a lot even straight on, in its own color -
                // the hue of the lit surface underneath.
                f0 = 0.65;
                tint = mix(vec3(1.0), color / max(max(color.r, max(color.g, color.b)), 0.001), 0.85);
            } else {
                // Stone, ice, gems and puddles: a weak reflection straight on
                // that grows strongly toward grazing angles.
                f0 = 0.04 + 0.12 * shine * shine;
            }
        }
#endif

        if (reflectivity > 0.0) {
            // Reflection, strongest at a low angle (Fresnel). For water it
            // comes AFTER the depth color - done earlier (in gbuffers_water),
            // distant water would get its mirror painted over by the fog. The
            // sky stands in wherever the screen-space trace finds nothing (or
            // is off), and without open sky above (caves, indoors) just the
            // surface's own color.
            vec3 N = decodeNormal(surface.rg);
            vec3 viewDir = normalize(viewPos);
            vec3 reflDir = reflect(viewDir, N);
#ifdef AURORA_TAA
            // Rough surfaces (polished stone, ...) scatter their reflection:
            // tilt the ray randomly by a different amount every frame, and
            // TAA averages that into a soft, blurry mirror image.
            if (roughness > 0.0) {
                vec3 scatter = vec3(effectDither(gl_FragCoord.xy), effectDither(gl_FragCoord.yx + 17.0), effectDither(gl_FragCoord.xy + 41.0)) - 0.5;
                reflDir = normalize(reflDir + scatter * (roughness * 0.35));
                if (dot(reflDir, N) < 0.0) reflDir = reflect(reflDir, N); // keep it above the surface
            }
#endif
            float fresnel = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(N, -viewDir), 0.0, 1.0), 5.0);

            vec3 reflection = mix(color, reflectedSky(reflDir), smoothstep(0.15, 0.55, surface.b));
#ifdef AURORA_SSR
            vec4 hit = traceReflection(viewPos + N * 0.05, reflDir);
            reflection = mix(reflection, hit.rgb, hit.a);
#endif
            color = mix(color, reflection * tint, fresnel * reflectivity);
        }
    }

#ifdef AURORA_LIGHT_SHAFTS
    color += lightShafts(viewPos);
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
