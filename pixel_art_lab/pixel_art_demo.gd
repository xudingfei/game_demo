extends Control
## 调色板只在换图或修改颜色数量时由 CPU 提取，显示效果由 shader 实时处理。

const PIXEL_SHADER = preload("res://pixel_art_lab/pixel_art.gdshader")
const DEMO_TEXTURE = preload("res://pixel_art_lab/sample_mech_lineless.png")
const PADDING := 96
var effect: ShaderMaterial
var original: TextureRect
var processed: TextureRect
var palette_row: HFlowContainer
var status: Label
var picker: FileDialog
var palette_delay: Timer
var samples: Array[Vector3] = []
var requested_colors := 16
var current_image_name := "六足火炮机甲"
var current_dimensions := Vector2i.ZERO
var controls: Dictionary = {}

func label_for(value: String, size_px: int = 16) -> Label:
    var result := Label.new()
    result.text = value
    result.add_theme_font_size_override("font_size", size_px)
    return result

func _ready() -> void:
    $EditorHint.hide()
    get_window().title = "PIXEL ART LAB · 六足火炮机甲"
    get_window().size = Vector2i(1220, 820)
    get_window().min_size = Vector2i(980, 680)
    effect = ShaderMaterial.new()
    effect.shader = PIXEL_SHADER
    palette_delay = Timer.new()
    palette_delay.one_shot = true
    palette_delay.wait_time = 0.18
    palette_delay.timeout.connect(rebuild_palette)
    add_child(palette_delay)

    var backdrop := ColorRect.new()
    backdrop.color = Color("101827")
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(backdrop)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    add_child(margin)
    var page := VBoxContainer.new()
    page.add_theme_constant_override("separation", 16)
    margin.add_child(page)
    page.add_child(label_for("PIXEL ART LAB / 六足火炮机甲", 26))
    page.add_child(label_for("像素格 → 限定调色板 → 清晰外轮廓", 16))
    var row := HBoxContainer.new()
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 18)
    page.add_child(row)
    original = make_preview(row, "01 / 原图", false)
    processed = make_preview(row, "02 / 像素画", true)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size.x = 280
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    row.add_child(scroll)
    var settings := VBoxContainer.new()
    settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings.add_theme_constant_override("separation", 12)
    scroll.add_child(settings)
    settings.add_child(label_for("风格调节", 21))
    var choose := Button.new()
    choose.text = "选择自己的图片…"
    choose.pressed.connect(func(): picker.popup_centered(Vector2i(800, 540)))
    settings.add_child(choose)
    add_slider(settings, "像素格边长", "pixel_size", 1, 24, 6, " 原图像素", func(value: float):
        effect.set_shader_parameter("pixel_size", value)
    )
    settings.add_child(label_for("数值越小，细节越多。", 13))
    add_slider(settings, "主体颜色数量", "color_count", 2, 32, 16, " 色", func(value: float):
        requested_colors = int(value)
        palette_delay.start()
    )
    add_slider(settings, "外描边粗细", "outline_width", 0, 3, 1, " 格（0 = 关闭）", func(value: float):
        effect.set_shader_parameter("outline_width", int(value))
    )
    settings.add_child(label_for("描边颜色"))
    var outline_picker := ColorPickerButton.new()
    outline_picker.color = Color(0.075, 0.09, 0.15, 1.0)
    outline_picker.edit_alpha = false
    outline_picker.color_changed.connect(func(color: Color): effect.set_shader_parameter("outline_color", color))
    settings.add_child(outline_picker)
    settings.add_child(label_for("当前主体调色板", 16))
    palette_row = HFlowContainer.new()
    palette_row.add_theme_constant_override("h_separation", 4)
    palette_row.add_theme_constant_override("v_separation", 4)
    settings.add_child(palette_row)
    var restore := Button.new()
    restore.text = "恢复默认参数"
    restore.pressed.connect(func():
        controls["pixel_size"].value = 6
        controls["color_count"].value = 16
        controls["outline_width"].value = 1
        outline_picker.color = Color(0.075, 0.09, 0.15, 1.0)
        effect.set_shader_parameter("outline_color", outline_picker.color)
    )
    settings.add_child(restore)
    var sample_button := Button.new()
    sample_button.text = "换回六足火炮机甲"
    sample_button.pressed.connect(func(): set_source(DEMO_TEXTURE.get_image(), "六足火炮机甲"))
    settings.add_child(sample_button)
    var help := label_for("默认素材不带粗黑外描边，\n外轮廓由 Shader 统一生成。\n推荐使用透明背景 PNG。\n\n主体最多使用指定数量的颜色；\n描边颜色另外计算。\n\n内部关节用色块区分，\n外描边设为 0 可查看原效果。", 13)
    help.modulate = Color("9dacc1")
    settings.add_child(help)
    status = label_for("", 13)
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    page.add_child(status)
    picker = FileDialog.new()
    picker.access = FileDialog.ACCESS_FILESYSTEM
    picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    picker.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片 PNG / JPEG / WebP"])
    picker.title = "选择图片（推荐透明 PNG）"
    picker.file_selected.connect(load_source)
    add_child(picker)
    set_source(DEMO_TEXTURE.get_image(), "六足火炮机甲")

func make_preview(parent: HBoxContainer, title: String, use_effect: bool) -> TextureRect:
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 12)
    parent.add_child(column)
    column.add_child(label_for(title, 18))
    var frame := PanelContainer.new()
    frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var style := StyleBoxFlat.new()
    style.bg_color = Color("334155")
    style.set_corner_radius_all(8)
    frame.add_theme_stylebox_override("panel", style)
    column.add_child(frame)
    var preview := TextureRect.new()
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if use_effect else CanvasItem.TEXTURE_FILTER_LINEAR
    if use_effect:
        preview.material = effect
    frame.add_child(preview)
    return preview

func add_slider(parent: VBoxContainer, title: String, key: String, low: float, high: float, initial: float, suffix: String, callback: Callable) -> void:
    var caption := label_for(title + "：" + str(int(initial)) + suffix)
    parent.add_child(caption)
    var slider := HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = 1
    slider.value = initial
    slider.value_changed.connect(func(value: float):
        caption.text = title + "：" + str(int(value)) + suffix
        callback.call(value)
    )
    controls[key] = slider
    parent.add_child(slider)

func load_source(path: String) -> void:
    var source: Image = Image.load_from_file(path)
    if source == null or source.is_empty():
        status.text = "无法读取这张图片，请选择 PNG、JPEG 或 WebP。"
        return
    set_source(source, path.get_file())

func set_source(source: Image, image_name: String) -> void:
    if source == null or source.is_empty():
        status.text = "示例图片尚未导入，请让 Godot 完成资源扫描后重新运行。"
        return
    palette_delay.stop()
    var image: Image = source.duplicate()
    if image.is_compressed():
        if image.decompress() != OK:
            status.text = "图片解压失败。"
            return
    image.convert(Image.FORMAT_RGBA8)
    # 大图先等比缩小，防止动态调色板分析和显示占用过多资源。
    var largest := maxi(image.get_width(), image.get_height())
    if largest > 1024:
        var scale_factor := 1024.0 / float(largest)
        image.resize(maxi(1, int(image.get_width() * scale_factor)), maxi(1, int(image.get_height() * scale_factor)), Image.INTERPOLATE_LANCZOS)
    current_dimensions = image.get_size()
    current_image_name = image_name
    var padded := Image.create(image.get_width() + PADDING * 2, image.get_height() + PADDING * 2, false, Image.FORMAT_RGBA8)
    padded.fill(Color.TRANSPARENT)
    padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(PADDING, PADDING))
    var texture := ImageTexture.create_from_image(padded)
    original.texture = texture
    processed.texture = texture
    collect_samples(image)
    rebuild_palette()

func collect_samples(image: Image) -> void:
    samples.clear()
    var thumb: Image = image.duplicate()
    var factor := minf(1.0, 96.0 / float(maxi(image.get_width(), image.get_height())))
    thumb.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_NEAREST)
    for y in range(thumb.get_height()):
        for x in range(thumb.get_width()):
            var color := thumb.get_pixel(x, y)
            if color.a >= 0.5:
                samples.append(Vector3(color.r, color.g, color.b))

func box_extent(box: Array) -> Vector3:
    var minimum := Vector3.ONE
    var maximum := Vector3.ZERO
    for entry in box:
        var value: Vector3 = entry
        minimum = minimum.min(value)
        maximum = maximum.max(value)
    return maximum - minimum

func rebuild_palette() -> void:
    # 中位切分：不断沿颜色跨度最大的通道，将颜色样本分成两组。
    # CPU 只在换图、调整数量后运行一次，shader 每帧仅查找最近颜色。
    var boxes: Array = []
    if not samples.is_empty():
        boxes.append(samples.duplicate())
    while boxes.size() < requested_colors:
        var split_index := -1
        var split_axis := 0
        var best_score := 0.0
        for i in range(boxes.size()):
            var box: Array = boxes[i]
            if box.size() < 2:
                continue
            var extent := box_extent(box)
            var axis := extent.max_axis_index()
            var score: float = extent[axis] * sqrt(float(box.size()))
            if score > best_score:
                best_score = score
                split_index = i
                split_axis = axis
        if split_index < 0:
            break
        var selected: Array = boxes[split_index]
        selected.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a[split_axis] < b[split_axis])
        var middle := int(selected.size() / 2)
        boxes[split_index] = selected.slice(0, middle)
        boxes.append(selected.slice(middle))
    var colors: Array[Color] = []
    for box in boxes:
        var total := Vector3.ZERO
        for sample in box:
            total += sample
        total /= float(box.size())
        colors.append(Color(total.x, total.y, total.z, 1.0))
    if colors.is_empty():
        colors.append(Color.BLACK)
    colors.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
    var palette := Image.create(32, 1, false, Image.FORMAT_RGBA8)
    for i in range(32):
        palette.set_pixel(i, 0, colors[mini(i, colors.size() - 1)])
    effect.set_shader_parameter("palette_texture", ImageTexture.create_from_image(palette))
    effect.set_shader_parameter("color_count", colors.size())
    for child in palette_row.get_children():
        palette_row.remove_child(child)
        child.queue_free()
    for color in colors:
        var swatch := ColorRect.new()
        swatch.color = color
        swatch.custom_minimum_size = Vector2(24, 24)
        swatch.tooltip_text = "#" + color.to_html(false)
        palette_row.add_child(swatch)
    status.text = "%s · 工作尺寸 %d × %d · 主体调色板 %d 色 · 支持本地换图，原图文件不会被修改" % [current_image_name, current_dimensions.x, current_dimensions.y, colors.size()]
