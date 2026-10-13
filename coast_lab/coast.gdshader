shader_type canvas_item;
render_mode unshaded;
uniform float pixel_size : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float wave_period : hint_range(2.0, 10.0, 0.1) = 5.5;
// 同一组时长内错开发出的浪数；数量不会改变单道浪的传播速度。
uniform int wave_count : hint_range(1, 4, 1) = 3;
// 只改变浪头的传播时间，不改变每组的发射数量、间隔或排水速度。
uniform float wave_speed : hint_range(0.5, 2.5, 0.05) = 1.0;
uniform float runup : hint_range(0.0, 50.0, 1.0) = 24.0;
// 水边允许退入参考岸线海侧，近岸因此会真正露出沙底。
uniform float backwash_distance : hint_range(0.0, 80.0, 1.0) = 38.0;
uniform float shore_randomness : hint_range(0.0, 32.0, 1.0) = 24.0;
uniform float transition_width : hint_range(24.0, 120.0, 1.0) = 64.0;
uniform float random_seed : hint_range(0.0, 100.0, 1.0) = 7.0;
uniform float wave_reach : hint_range(60.0, 240.0, 5.0) = 150.0;
uniform bool use_distance_map = false;
uniform sampler2D distance_map : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform vec2 map_size = vec2(800.0, 600.0);
uniform float distance_range = 256.0;
uniform bool render_ground = false;
uniform float drain_speed : hint_range(0.5, 2.0, 0.05) = 1.0;
uniform float foam_residue : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float foam_width : hint_range(2.0, 20.0, 0.5) = 8.0;
uniform float foam_pattern_size : hint_range(10.0, 40.0, 1.0) = 18.0;
uniform float foam_front_solid : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform float breakup : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform vec4 water_color : source_color = vec4(0.075, 0.39, 0.46, 1.0);
uniform float shallow_opacity : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float deep_opacity : hint_range(0.0, 1.0, 0.01) = 0.94;
uniform float sparkle_scale : hint_range(0.5, 3.0, 0.05) = 1.0;
uniform float sparkle_speed : hint_range(0.0, 2.5, 0.05) = 0.65;
uniform float sparkle_density : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float sparkle_strength : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform vec4 foam_color : source_color = vec4(0.93, 0.97, 0.96, 1.0);
uniform float preview_time = -1.0;
uniform int debug_view : hint_enum("完整画面", "海岸距离", "泡沫遮罩", "动态水深", "原地消散的碎泡沫", "水面高光") = 0;
varying vec2 world_position;
float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
vec2 gradient(vec2 p) {
    float a = hash21(p) * 6.2831853;
    return vec2(cos(a), sin(a));
}
float perlin(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(gradient(i), f);
    float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(gradient(i + vec2(1.0)), f - vec2(1.0));
    return 0.5 + 0.70710678 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
// 单纯形的一个角点：同时返回高度和解析导数 (height, dh/dx, dh/dy)。
// h = w^4 * dot(g, r)，因此 dh/dr = w^4*g - 8*w^3*dot(g,r)*r。
vec3 simplex_corner(vec2 r, vec2 lattice) {
    vec2 g = gradient(lattice);
    float w = max(0.5 - dot(r, r), 0.0);
    float w2 = w * w;
    float w3 = w2 * w;
    float w4 = w2 * w2;
    float projection = dot(g, r);
    return vec3(w4 * projection, w4 * g - 8.0 * w3 * projection * r);
}
// 二维 Simplex：每点只受所在三角形的三个角点影响。
// 使用现有 hash 生成单位梯度，无贴图、无 RT。
vec3 simplex_height_gradient(vec2 p) {
    const float F2 = 0.3660254038;
    const float G2 = 0.2113248654;
    vec2 lattice = floor(p + dot(p, vec2(F2)));
    vec2 r0 = p - lattice + dot(lattice, vec2(G2));
    vec2 corner = r0.x > r0.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec2 r1 = r0 - corner + G2;
    vec2 r2 = r0 - 1.0 + 2.0 * G2;
    return 70.0 * (simplex_corner(r0, lattice)
        + simplex_corner(r1, lattice + corner)
        + simplex_corner(r2, lattice + 1.0));
}
float max_wave_age() {
    // 最慢 0.5 倍速：0.10 延迟 + 0.56/0.5 传播 + 0.80 消退 = 2.02。
    return 0.10 + 0.56 / clamp(wave_speed, 0.5, 2.5) + 0.80;
}
// Cellular 风格泡孔：每个格子放一个随机中心和半径，取最近的椭圆孔。
// 返回归一化的距离平方；小于 1 位于孔内，大于 1 是孔外的泡沫。
float foam_hole_field(vec2 p, vec2 seed, float coarse) {
    vec2 q = p / (max(foam_pattern_size, 10.0) * vec2(1.0, 0.85)) + seed;
    // 小幅、静止的坐标扭曲让孔洞成为不规则圆钝形状。
    q += (vec2(coarse, perlin(p / 17.0 + seed + 51.3)) - 0.5) * 0.90;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float nearest = 100.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 id = cell + offset;
            vec2 center = 0.15 + 0.70 * vec2(hash21(id + 17.3), hash21(id + 53.1));
            float radius = mix(0.24, 0.46, hash21(id + 91.7));
            vec2 delta = offset + center - f;
            nearest = min(nearest, dot(delta, delta) / (radius * radius));
        }
    }
    return nearest;
}
float shore_x(float y) {
    return 248.0 + 48.0 * sin(y * 0.010 - 0.9)
        + 23.0 * sin(y * 0.023 + 0.8) + 0.075 * (y - 300.0);
}
float shore_distance(vec2 p) {
    if (use_distance_map) {
        vec2 uv = (p - map_origin) / max(map_size, vec2(1.0));
        return (texture(distance_map, clamp(uv, vec2(0.0), vec2(1.0))).r * 2.0 - 1.0) * distance_range;
    }
    // 曲线隐式函数除以梯度长度，只是岸边近似距离，非全局精确 SDF。
    float slope = 0.48 * cos(p.y * 0.010 - 0.9)
        + 0.529 * cos(p.y * 0.023 + 0.8) + 0.075;
    return (p.x - shore_x(p.y)) / sqrt(1.0 + slope * slope);
}
// 每轮是独立事件，种子固定。返回：薄水厚度、总泡沫、前缘泡沫、残留泡沫。
// age 是浪经过当前像素的时间；没有从岸上反向传播的前缘。
vec4 wave_event(vec2 p, float d, float clock, float event_id, float launch_time) {
    float event_age = clock - launch_time;
    if (event_age < 0.0 || event_age > max_wave_age()) { return vec4(0.0); }
    vec2 seed = vec2(hash21(vec2(event_id, random_seed + 3.1)),
        hash21(vec2(event_id, random_seed + 57.8))) * 200.0;
    float resting_line = max(backwash_distance, 0.0);
    float reach = max(wave_reach, resting_line + 24.0);
    float band_width = max(transition_width, max(runup, resting_line) + 24.0);
    float band = 1.0 - smoothstep(band_width, band_width + 60.0, abs(d));
    float shape = (perlin(vec2(p.y / 90.0, 4.7) + seed) - 0.5) * 2.0;
    float sample_d = d - shape * min(shore_randomness, band_width * 0.30) * band;
    // 延迟非负，无需预先计算尚未发射的浪。
    float delay = 0.02 + perlin(vec2(p.y / 145.0, 21.3) + seed) * 0.075;
    float beach_progress = clamp((resting_line - sample_d) / max(resting_line + runup, 1.0), 0.0, 1.0);
    float arrival;
    if (sample_d >= resting_line) {
        arrival = 0.22 * clamp((reach - sample_d) / max(reach - resting_line, 1.0), 0.0, 1.0);
    } else {
        arrival = 0.22 + 0.34 * (1.0 - sqrt(max(1.0 - beach_progress, 0.0)));
    }
    float speed = clamp(wave_speed, 0.5, 2.5);
    float age = event_age - delay - arrival / speed;
    float crest_age = age * speed;
    float coverage = smoothstep(-runup - 1.0, -runup + 7.0, sample_d)
        * (1.0 - smoothstep(reach - 8.0, reach + 16.0, sample_d));
    float coarse = perlin(p / 13.0 + seed + vec2(8.4, 19.2));
    // 陆侧先变薄，海侧停留更久；每个像素独立计时，不平移一条退水边界。
    float lifetime = clamp(mix(0.58, 0.12, beach_progress)
        * mix(0.84, 1.16, coarse) / max(drain_speed, 0.1), 0.07, 0.80);
    float rise = smoothstep(0.0, 0.025, crest_age);
    float drain = 1.0 - smoothstep(0.045, lifetime, age);
    float shoaling = 1.0 - smoothstep(resting_line + 25.0, reach + 1.0, sample_d);
    float peak_depth = mix(0.75, mix(3.0, 0.65, beach_progress), shoaling);
    float film = peak_depth * rise * drain * coverage;

    // 前缘是一条较连贯的亮带；后方泡孔逐渐打开，最后剩下孤立泡沫块。
    float crest_duration = 0.012 + foam_width * 0.002;
    float crest_time = smoothstep(0.0, 0.012, crest_age)
        * (1.0 - smoothstep(0.018, crest_duration + 0.025, crest_age));
    float residue_lifetime = max(0.055, min(0.34, lifetime * 0.80));
    float residue_time = smoothstep(0.018, 0.055, age)
        * (1.0 - smoothstep(0.045, residue_lifetime, age));
    // 泡沫消失后不再计算九邻格，薄水继续按原寿命消退。
    if (coverage <= 0.0 || film <= 0.015 || max(crest_time, residue_time) <= 0.0) {
        return vec4(film, 0.0, 0.0, 0.0);
    }
    float hole_field = foam_hole_field(p, seed, coarse);
    float erosion = clamp(max(age, 0.0) / residue_lifetime, 0.0, 1.0);
    float hole_radius = mix(0.72, 1.12, clamp(breakup, 0.0, 1.0)) + erosion * 0.62;
    float edge = clamp(max(pixel_size, 1.0) / max(foam_pattern_size, 10.0), 0.04, 0.20);
    float body = smoothstep(hole_radius * hole_radius,
        (hole_radius + edge) * (hole_radius + edge), hole_field);
    // 刚到达的浪尖先连起来，孔洞在它经过之后才打开。
    float leading_fill = (1.0 - smoothstep(0.012, 0.036, crest_age))
        * clamp(foam_front_solid, 0.0, 1.0);
    float crest = crest_time * max(leading_fill, body) * mix(0.88, 1.0, coarse);
    float residue = residue_time * body * foam_residue;
    float wet_film = smoothstep(0.015, 0.12, film);
    float foam_gain = mix(0.12, 1.0, shoaling) * coverage * wet_film;
    crest *= foam_gain;
    residue *= foam_gain;
    return vec4(film, max(crest, residue), crest, residue);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
    float px = max(pixel_size, 1.0);
    vec2 p = (floor(world_position / px) + 0.5) * px;
    float t = preview_time >= 0.0 ? preview_time : TIME;
    float d = shore_distance(p);
    float period = max(wave_period, 0.1);
    float clock = t / period;
    int count = clamp(wave_count, 1, 4);
    float latest_event = floor(clock * float(count));
    // 慢速浪需要保留更久的历史，避免还在岸边的泡沫突然消失。
    int active_count = int(ceil(max_wave_age() * float(count)));
    vec4 waves = vec4(0.0);
    for (int i = 0; i < 9; i++) {
        if (i >= active_count) { break; }
        float id = latest_event - float(i);
        vec4 wave = wave_event(p, d, clock, id, id / float(count));
        // 薄水取较厚的一层，增加浪数不会把整片浅水无限抬高。
        waves.x = max(waves.x, wave.x);
        // 合并覆盖率：1 - (1-a)(1-b)，多个泡沫不会相加溢出成过曝白带。
        waves.yzw = vec3(1.0) - (vec3(1.0) - waves.yzw) * (vec3(1.0) - wave.yzw);
    }
    float band_width = max(transition_width, max(runup, backwash_distance) + 24.0);
    // 常驻海水固定不涨缩；其上只叠加浪经过该位置后产生的局部薄水。
    float resting_offset = backwash_distance * (1.0 - smoothstep(
        backwash_distance + 40.0, backwash_distance + 180.0, max(d, 0.0)));
    float base_depth = max((d - resting_offset) * 0.08, 0.0);
    float water_depth = base_depth + waves.x;
    float water_mask = smoothstep(0.0, 0.08 * px * 0.8, water_depth);
    float foam = waves.y * water_mask;

    // 沙滩底色；湿沙留在最大上冲范围内，模拟退水后的深色痕迹。
    float sand_n = perlin(p / 58.0) * 0.65 + perlin(p / 13.0) * 0.35;
    vec3 sand = mix(vec3(0.69, 0.60, 0.39), vec3(0.83, 0.76, 0.51), floor(sand_n * 5.0) / 4.0);
    float wet = smoothstep(-runup - min(shore_randomness, band_width * 0.35) - 15.0, -runup + 1.0, d);
    sand = mix(sand, vec3(0.48, 0.53, 0.40), wet * 0.67);
    float grain = hash21(floor(p / px));
    sand += vec3((grain - 0.5) * 0.034);
    // 少量静态沙砾，只在干沙显示。
    vec2 stone_grid = floor(p / 30.0);
    vec2 stone_local = p - stone_grid * 30.0;
    vec2 stone_center = 8.0 + vec2(hash21(stone_grid + 4.0), hash21(stone_grid + 9.0)) * 14.0;
    float pebble = step(length((stone_local - stone_center) / vec2(2.7, 1.7)), 1.0)
        * step(0.83, hash21(stone_grid + 33.0)) * (1.0 - wet);
    sand = mix(sand, vec3(0.46, 0.45, 0.34), pebble * 0.65);

    // 很薄的水从 Alpha 0 起步，增厚到浅水不透明度，再连续趋近深水不透明度。
    float thin_alpha = shallow_opacity * smoothstep(0.0, 1.4, water_depth);
    float depth = smoothstep(1.4, 21.6, water_depth);
    float water_alpha = mix(thin_alpha, deep_opacity, depth) * water_color.a * water_mask;
    vec3 water = water_color.rgb;
    // 两层不同方向的 Simplex 微波叠加，让坡度随时间变化。
    // X 向尺度稍大，高光呈短横片；p 仍按世界像素格采样。
    vec2 q = p / (vec2(60.0, 20.0) * max(sparkle_scale, 0.5))
        + vec2(random_seed * 3.17, random_seed * 1.91);
    float surface_time = t * max(sparkle_speed, 0.0);
    vec3 ripple_a = simplex_height_gradient(q + vec2(surface_time * 0.24, -surface_time * 0.18));
    vec3 ripple_b = simplex_height_gradient(q * 1.73 + vec2(23.7, 9.4)
        + vec2(-surface_time * 0.19, -surface_time * 0.27));
    float ripple_height = ripple_a.x * 0.68 + ripple_b.x * 0.32;
    vec2 slope = (ripple_a.yz * 0.68 + ripple_b.yz * (0.32 * 1.73)) * vec2(1.0 / 3.0, 1.0);
    vec3 surface_normal = normalize(vec3(-slope * 0.55, 1.0));
    vec3 light_direction = normalize(vec3(-0.30, -0.55, 0.78));
    vec3 half_direction = normalize(light_direction + vec3(0.0, 0.0, 1.0));
    float facing = max(dot(surface_normal, half_direction), 0.0);
    float density = clamp(sparkle_density, 0.0, 1.0);
    float specular = pow(facing, mix(160.0, 28.0, density));
    float glint = smoothstep(0.25, 0.80, specular) * smoothstep(0.0, 0.06, density);
    glint *= water_mask * smoothstep(0.10, 0.80, water_depth);
    water += vec3(0.012, 0.026, 0.030) * ripple_height;
    // 水层不预先混入沙色，交给 Alpha 混合显示后面的真实沙底节点。

    // 浪头后局部微亮的碎水，只由本地经过时间决定，不画退水 rim。
    water = mix(water, vec3(0.53, 0.79, 0.73), waves.w * 0.16);
    // 反射高光有独立覆盖率：透明浅水也能反光，干沙不会发亮。
    float glint_alpha = glint * clamp(sparkle_strength, 0.0, 1.0) * water_color.a;
    vec3 water_premultiplied = vec3(0.83, 0.97, 1.0) * glint_alpha
        + water * water_alpha * (1.0 - glint_alpha);
    float surface_alpha = glint_alpha + water_alpha * (1.0 - glint_alpha);
    // 先合成泡沫和水，再转为 Godot 默认混合所需的 straight alpha。
    // 泡沫有独立 Alpha，水很透明时浪头依然可见。
    float foam_alpha = clamp(foam, 0.0, 1.0) * foam_color.a;
    float alpha = foam_alpha + surface_alpha * (1.0 - foam_alpha);
    vec3 color = (foam_color.rgb * foam_alpha
        + water_premultiplied * (1.0 - foam_alpha)) / max(alpha, 0.00001);
    if (debug_view == 1) {
        color = d >= 0.0 ? mix(vec3(0.15, 0.40, 0.45), vec3(0.8), clamp(d / 200.0, 0.0, 1.0))
            : vec3(0.55, 0.38, 0.22);
        color *= 0.72 + 0.28 * step(2.0, mod(abs(d), 20.0));
    }
    if (debug_view == 2) { color = vec3(foam); }
    if (debug_view == 3) { color = vec3(clamp(water_depth / 6.0, 0.0, 1.0)); }
    if (debug_view == 4) { color = vec3(waves.w); }
    if (debug_view == 5) { color = vec3(glint); }
    if (debug_view != 0) { alpha = 1.0; }
    COLOR = render_ground ? vec4(sand, 1.0) : vec4(color, alpha);
}
