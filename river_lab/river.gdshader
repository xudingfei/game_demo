shader_type canvas_item;
render_mode unshaded;

// 高度图是数据，不使用 source_color；黑色低，白色高。
uniform sampler2D height_map : filter_nearest, repeat_disable;
uniform sampler2D noise_map : filter_linear, repeat_enable;
uniform sampler2D caustics_map : filter_linear, repeat_enable;
uniform float water_level : hint_range(0.0, 1.0) = 0.48;
uniform float water_opacity : hint_range(0.0, 1.0) = 0.55;
uniform float outline_size : hint_range(0.0, 5.0, 1.0) = 1.0;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.65;
uniform float distortion_pixels : hint_range(0.0, 5.0) = 1.3;
uniform float caustics_strength : hint_range(0.0, 0.6) = 0.18;
uniform float animation_time = 0.0;
uniform int view_mode = 0;
uniform vec4 shallow_color : source_color = vec4(0.28, 0.66, 0.65, 1.0);
uniform vec4 deep_color : source_color = vec4(0.045, 0.20, 0.31, 1.0);
uniform vec4 foam_color : source_color = vec4(0.83, 0.94, 0.79, 1.0);

float wet(vec2 uv) {
    return step(texture(height_map, uv).r, water_level);
}

void fragment() {
    // 对齐原图像素，防止水纹比地形更细碎。
    vec2 uv = (floor(UV / TEXTURE_PIXEL_SIZE) + 0.5) * TEXTURE_PIXEL_SIZE;
    vec4 ground = texture(TEXTURE, uv);
    float h = texture(height_map, uv).r;
    float mask = step(h, water_level);
    float depth = max(water_level - h, 0.0);
    float d = clamp(depth / 0.45, 0.0, 1.0);
    vec2 flow_uv = uv * vec2(3.0, 2.0) + animation_time * flow_speed * vec2(-0.06, 0.015);

    vec2 offset = (texture(noise_map, flow_uv).rg * 2.0 - 1.0)
        * TEXTURE_PIXEL_SIZE * distortion_pixels * d;
    vec2 sample_uv = clamp(uv + offset, TEXTURE_PIXEL_SIZE * 0.5,
        vec2(1.0) - TEXTURE_PIXEL_SIZE * 0.5);
    // 扭曲后的取色点落上岸时，退回原坐标，避免把岸拉进水里。
    sample_uv = mix(uv, sample_uv, wet(sample_uv));
    vec3 bed = texture(TEXTURE, sample_uv).rgb;
    vec3 tint = mix(shallow_color.rgb, deep_color.rgb, d);
    vec3 water = mix(bed, tint, clamp(water_opacity + d * 0.18, 0.0, 1.0));

    float c1 = texture(caustics_map, flow_uv).r;
    float c2 = texture(caustics_map, uv * vec2(3.0, 2.0)
        + animation_time * flow_speed * vec2(0.025, -0.035)).r;
    water += vec3(0.70, 0.90, 0.80) * min(c1, c2) * caustics_strength * (1.0 - d * 0.6);

    // 水域内描边：中心是水，四邻域中有陆地。
    vec2 e = TEXTURE_PIXEL_SIZE * outline_size;
    float neighbors = min(min(wet(uv + vec2(e.x, 0.0)), wet(uv - vec2(e.x, 0.0))),
                          min(wet(uv + vec2(0.0, e.y)), wet(uv - vec2(0.0, e.y))));
    float shore = mask * (1.0 - neighbors);
    vec3 result = mix(ground.rgb, water, mask);
    result = mix(result, foam_color.rgb, shore * (0.65 + 0.25 * c1));

    if (view_mode == 1) { result = ground.rgb; }
    if (view_mode == 2) { result = vec3(h); }
    if (view_mode == 3) { result = vec3(mask); }
    if (view_mode == 4) { result = vec3(d); }
    if (view_mode == 5) { result = vec3(shore); }
    COLOR = vec4(result, ground.a);
}
