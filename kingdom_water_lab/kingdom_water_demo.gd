extends Control

const WATER_SHADER = preload("res://kingdom_water_lab/kingdom_water.gdshader")
const SCENERY = preload("res://kingdom_water_lab/scenery.gd")
var water_material: ShaderMaterial
var flow_offset := Vector2.ZERO
var playing := true
var scenery: Node2D

func text_label(value: String, font_size: int = 16) -> Label:
    var item := Label.new()
    item.text = value
    item.add_theme_font_size_override("font_size", font_size)
    return item

func slider(panel: VBoxContainer, title: String, parameter: String, minimum: float, maximum: float, increment: float, initial: float) -> void:
    var title_label := text_label(title + "  " + str(initial))
    panel.add_child(title_label)
    var control := HSlider.new()
    control.min_value = minimum
    control.max_value = maximum
    control.step = increment
    control.value = initial
    water_material.set_shader_parameter(parameter, initial)
    control.value_changed.connect(func(value: float):
        water_material.set_shader_parameter(parameter, value)
        title_label.text = title + "  " + str(snappedf(value, increment))
    )
    panel.add_child(control)

func _ready() -> void:
    get_window().title = "KINGDOM WATER LAB · 像素倒影水面"
    get_window().size = Vector2i(1120, 720)
    get_window().min_size = Vector2i(900, 620)
    var background := ColorRect.new()
    background.color = Color("101d25")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 20)
    add_child(margin)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 14)
    margin.add_child(layout)
    layout.add_child(text_label("KINGDOM WATER LAB / 像素倒影", 25))
    layout.add_child(text_label("场景镜像 → 顺流水纹与倒影晃动 → 水色混合", 16))
    var row := HBoxContainer.new()
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 20)
    layout.add_child(row)

    # 固定内部分辨率，界面缩放不会改变水岸线与反射的位置。
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    scenery = Node2D.new()
    scenery.set_script(SCENERY)
    viewport.add_child(scenery)
    var capture := BackBufferCopy.new()
    capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
    viewport.add_child(capture)
    water_material = ShaderMaterial.new()
    water_material.shader = WATER_SHADER
    var water := ColorRect.new()
    water.position = Vector2(0, 340)
    water.size = Vector2(800, 260)
    water.material = water_material
    viewport.add_child(water)

    var preview := TextureRect.new()
    preview.texture = viewport.get_texture()
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    row.add_child(preview)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size.x = 258
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    row.add_child(scroll)
    var panel := VBoxContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.add_theme_constant_override("separation", 12)
    scroll.add_child(panel)
    panel.add_child(text_label("水面参数", 20))
    slider(panel, "波速", "wave_speed", 0, 3, 0.05, 1)
    slider(panel, "水流方向 / 度", "flow_angle", 0, 360, 1, 0)
    panel.add_child(text_label("0° →   90° ↓   180° ←   270° ↑", 13))
    slider(panel, "波幅 / 像素", "wave_strength", 0, 12, 0.25, 3.5)
    slider(panel, "倒影强度", "reflection_strength", 0, 1, 0.01, 0.78)
    slider(panel, "像素大小", "pixel_size", 1, 6, 1, 2)
    slider(panel, "亮纹强度", "glint_strength", 0, 1, 0.01, 0.25)
    panel.add_child(text_label("水体底色"))
    var tint := ColorPickerButton.new()
    tint.color = Color(0.055, 0.16, 0.20)
    tint.color_changed.connect(func(value: Color): water_material.set_shader_parameter("water_color", value))
    panel.add_child(tint)
    var pause := Button.new()
    pause.text = "暂停动画"
    pause.pressed.connect(func():
        playing = not playing
        scenery.set_process(playing)
        pause.text = "暂停动画" if playing else "继续动画"
    )
    panel.add_child(pause)
    var note := text_label("波幅控制倒影晃动幅度。\n水纹沿所选方向传播，\n倒影在原位置附近摆动。\n\n这是风格原理示例，\n并非原作着色器复刻。", 14)
    note.modulate = Color("9eafb5")
    panel.add_child(note)

func _process(delta: float) -> void:
    if playing and water_material:
        var speed := float(water_material.get_shader_parameter("wave_speed"))
        var angle := deg_to_rad(float(water_material.get_shader_parameter("flow_angle")))
        # 累计位移，使调节速度不再重新缩放整个历史时间。
        flow_offset += Vector2(cos(angle), sin(angle)) * speed * 24.0 * delta
        water_material.set_shader_parameter("flow_offset", flow_offset)
