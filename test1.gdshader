shader_type canvas_item;

// 每个方块的边长，单位是原图片的像素
uniform float pixel_size : hint_range(1.0, 128.0, 1.0) = 2.0;

void fragment() {
    // 一个方块在 UV 坐标中有多大
    vec2 block_size = TEXTURE_PIXEL_SIZE * pixel_size;

    // 同一个方块中的像素，都取方块中心的颜色
    vec2 sample_uv = (floor(UV / block_size) + 0.5) * block_size;

    // 防止图片边缘的采样位置超出范围
    sample_uv = clamp(
        sample_uv,
        TEXTURE_PIXEL_SIZE * 0.5,
        vec2(1.0) - TEXTURE_PIXEL_SIZE * 0.5
    );

    COLOR = texture(TEXTURE, sample_uv);
}