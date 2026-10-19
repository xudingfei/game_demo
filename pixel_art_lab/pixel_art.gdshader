shader_type canvas_item;
render_mode unshaded;

uniform float pixel_size : hint_range(1.0, 24.0, 1.0) = 6.0;
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform int color_count : hint_range(2, 32, 1) = 16;
uniform float alpha_threshold : hint_range(0.01, 1.0) = 0.5;
uniform int outline_width : hint_range(0, 3, 1) = 1;
uniform vec4 outline_color : source_color = vec4(0.075, 0.09, 0.15, 1.0);

vec4 sample_safe(sampler2D source_texture, vec2 uv) {
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
        return vec4(0.0);
    }
    return textureLod(source_texture, uv, 0.0);
}

void fragment() {
    // 把一格中的所有输出像素映射到同一个原图采样点。
    vec2 step_uv = TEXTURE_PIXEL_SIZE * max(pixel_size, 1.0);
    vec2 center_uv = (floor(UV / step_uv) + 0.5) * step_uv;
    vec4 source = sample_safe(TEXTURE, center_uv);
    bool solid = source.a >= alpha_threshold;
    vec4 result = vec4(0.0);
    if (solid) {
        float best_distance = 1000.0;
        vec3 nearest_color = vec3(0.0);
        for (int i = 0; i < 32; i++) {
            if (i >= color_count) { break; }
            vec3 candidate = textureLod(palette_texture, vec2((float(i) + 0.5) / 32.0, 0.5), 0.0).rgb;
            vec3 difference = source.rgb - candidate;
            float distance_squared = dot(difference * difference, vec3(0.299, 0.587, 0.114));
            if (distance_squared < best_distance) {
                best_distance = distance_squared;
                nearest_color = candidate;
            }
        }
        result = vec4(nearest_color, 1.0);
    } else if (outline_width > 0) {
        // 仅检查透明像素周围的实体格，生成外轮廓；不是内部边缘检测。
        bool neighbor = false;
        for (int y = -3; y <= 3; y++) {
            for (int x = -3; x <= 3; x++) {
                if (abs(x) <= outline_width && abs(y) <= outline_width && (x != 0 || y != 0)) {
                    if (sample_safe(TEXTURE, center_uv + vec2(float(x), float(y)) * step_uv).a >= alpha_threshold) {
                        neighbor = true;
                    }
                }
            }
        }
        if (neighbor) { result = outline_color; }
    }
    COLOR = result;
}
