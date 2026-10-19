shader_type canvas_item;
render_mode unshaded;

// 水面在独立的 800×600 视口中绘制；只读取先绘制好的岸上风景。
uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float shoreline : hint_range(0.0, 1.0) = 0.5666667;
uniform float pixel_size : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
// 屏幕方向：0°右、90°下、180°左、270°上。
uniform float flow_angle : hint_range(0.0, 360.0, 1.0) = 0.0;
// 脚本逐帧累计的水流位移，单位为内部视口像素。
uniform vec2 flow_offset = vec2(0.0);
uniform float wave_strength : hint_range(0.0, 12.0) = 3.5;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.78;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec4 water_color : source_color = vec4(0.055, 0.16, 0.20, 1.0);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 平滑值噪声：伸展采样坐标后得到横向的细长水纹。
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x), u.y);
}

void fragment() {
    vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 p = (floor(SCREEN_UV * resolution / pixel_size) + 0.5) * pixel_size;
    vec2 uv = p / resolution;
    float depth = clamp((uv.y - shoreline) / (1.0 - shoreline), 0.0, 1.0);
    float angle = radians(flow_angle);
    vec2 flow_dir = vec2(cos(angle), sin(angle));
    vec2 cross_dir = vec2(-flow_dir.y, flow_dir.x);
    // 采样坐标减去位移，噪声图案就会朝位移的正方向传播。
    // 两层都顺流，保留横向细长的水纹，仅让传播方向可调。
    float broad = noise((p - flow_offset) / vec2(110.0, 19.0));
    float fine = noise((p - flow_offset * 1.55) / vec2(37.0, 5.0) + vec2(13.7, 8.3));
    float displacement = ((broad - 0.5) * 1.4 + (fine - 0.5) * 0.6);
    float amplitude = wave_strength * smoothstep(0.0, 0.12, depth) * mix(0.35, 1.0, depth);

    // 沿水岸水平线翻转：水下的位置对应水岸上方等距离的位置。
    vec2 reflected = vec2(uv.x, 2.0 * shoreline - uv.y);
    // 局部倒影沿水流轴来回晃动，少量横向摆动避免过于整齐。
    // 这是有界偏移，倒影不会随着时间无限漂离物体。
    vec2 visual_offset = (flow_dir * displacement + cross_dir * (fine - 0.5) * 0.12) * amplitude;
    // 要让图案向右显示，需向左取样；y 已经过镜像，符号相反。
    reflected += vec2(-visual_offset.x, visual_offset.y) / resolution;
    reflected = (floor(reflected * resolution / pixel_size) + 0.5) * pixel_size / resolution;
    reflected = clamp(reflected, SCREEN_PIXEL_SIZE * 0.5,
        vec2(1.0 - SCREEN_PIXEL_SIZE.x * 0.5, shoreline - SCREEN_PIXEL_SIZE.y * 0.5));
    vec3 reflection = textureLod(scene_texture, reflected, 0.0).rgb;
    float visibility = reflection_strength * mix(1.0, 0.68, depth);
    vec3 result = mix(water_color.rgb, reflection * vec3(0.80, 0.94, 1.0), visibility);

    // 稀疏短亮纹。大部分明暗细节仍来自场景倒影。
    float sparkle = smoothstep(0.79, 0.91, fine) * smoothstep(0.48, 0.70, broad);
    result += vec3(0.30, 0.48, 0.48) * sparkle * glint_strength;
    float edge = 1.0 - smoothstep(0.0, 2.5, p.y - shoreline * resolution.y);
    result = mix(result, vec3(0.32, 0.46, 0.43), edge * 0.28);
    COLOR = vec4(result, 1.0);
}
