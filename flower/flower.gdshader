shader_type canvas_item;
render_mode unshaded;

// 世界坐标统一采样，相邻地块共享材质时连续。
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float patch_size : hint_range(24.0, 512.0, 1.0) = 150.0;
uniform float random_seed : hint_range(0.0, 100.0, 1.0) = 7.0;
uniform float color_steps : hint_range(2.0, 12.0, 1.0) = 5.0;
uniform float patch_contrast : hint_range(0.2, 2.0, 0.05) = 1.15;
uniform float detail_strength : hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float grass_density : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float grass_contrast : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform vec4 dark_grass : source_color = vec4(0.32, 0.47, 0.23, 1.0);
uniform vec4 light_grass : source_color = vec4(0.48, 0.62, 0.32, 1.0);
// 0 最终效果，1 大色块，2 草簇，3 连续黑白噪声。
uniform int debug_view : hint_range(0, 3, 1) = 0;
varying vec2 world_position;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// 为每个格点生成单位梯度方向；相邻格子共享角点梯度。
vec2 random_gradient(vec2 p) {
    float angle = hash21(p) * 6.2831853;
    return vec2(cos(angle), sin(angle));
}

// 二维柏林噪声：梯度点积 + 五次平滑插值，输出映射到 0～1。
float perlin_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(random_gradient(cell), f);
    float b = dot(random_gradient(cell + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(random_gradient(cell + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(random_gradient(cell + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
    float n = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    return clamp(n * 0.70710678 + 0.5, 0.0, 1.0);
}

float fbm(vec2 p) {
    return perlin_noise(p) * 0.65
        + perlin_noise(p * 2.03 + vec2(13.7, 8.3)) * 0.25
        + perlin_noise(p * 4.07 + vec2(5.1, 19.4)) * 0.10;
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    float px = max(pixel_size, 1.0);
    vec2 cell = floor(world_position / px);
    vec2 p = (cell + 0.5) * px;
    vec2 seed = vec2(random_seed * 7.13, random_seed * 3.71);

    // 第一层：连续大色块，加少量坐标扰动，避免规则网格感。
    vec2 base = p / max(patch_size, 1.0) + seed;
    vec2 warp = vec2(perlin_noise(base * 1.5 + 3.2), perlin_noise(base * 1.5 + 17.4));
    float n = fbm(base + (warp - 0.5) * 0.9);
    n = clamp((n - 0.5) * patch_contrast + 0.5, 0.0, 1.0);
    float steps = max(floor(color_steps), 2.0);
    float bands = floor(n * (steps - 1.0) + 0.5) / (steps - 1.0);
    vec3 color = mix(dark_grass.rgb, light_grass.rgb, bands);

    // 第二层：低对比局部细节。
    float fine = perlin_noise(p / 7.0 + seed + 81.0);
    if (debug_view == 0) {
        color += vec3((fine - 0.5) * detail_strength);
    }

    // 第三层：成簇草点。按世界坐标定位，跨瓦片不重置。
    vec2 cluster_cell = floor(cell / 8.0);
    vec2 local = cell - cluster_cell * 8.0;
    vec2 anchor = vec2(2.0) + floor(vec2(
        hash21(cluster_cell + seed + 24.0),
        hash21(cluster_cell + seed + 63.0)) * 3.0);
    vec2 d = local - anchor;
    float variation = hash21(cluster_cell + seed + 9.0);
    bool blade = (d.x == 0.0 && (d.y == 0.0 || d.y == -1.0))
        || (d.x == 2.0 && d.y == 0.0)
        || (variation > 0.55 && d.x == 1.0 && d.y == 1.0);
    vec2 cluster_world = (cluster_cell * 8.0 + 4.0) * px;
    float habitat = smoothstep(0.22, 0.72, perlin_noise(cluster_world / 90.0 + seed + 43.0));
    float chance = hash21(cluster_cell + seed + 105.0);
    float tuft = (blade && chance < grass_density * habitat) ? 1.0 : 0.0;
    if (debug_view == 0) {
        vec3 tuft_color = variation > 0.8 ? color * 1.15 : color * 0.62;
        color = mix(color, tuft_color, tuft * grass_contrast);
    }
    if (debug_view == 2) { color = vec3(tuft); }
    if (debug_view == 3) { color = vec3(n); }
    COLOR = vec4(color, COLOR.a);
}
