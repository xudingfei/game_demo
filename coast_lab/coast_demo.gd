extends Control
## 独立演示：Shader 负责绘制；此脚本只负责界面和播放时间。

const WATER_MATERIAL = preload("res://coast_lab/coast_material.tres")
var water_material: ShaderMaterial
var ground_material: ShaderMaterial
var elapsed := 0.0
var playing := true
var phase_label: Label
var phase_bar: ProgressBar
var pause_button: Button
var sliders: Dictionary = {}
var playhead: HSlider
var update_playhead := false

func label(text: String, size_px: int, tint := Color("d6e8e2")) -> Label:
    var item := Label.new()
    item.text = text
    item.add_theme_font_size_override("font_size", size_px)
    item.add_theme_color_override("font_color", tint)
    return item

func _ready() -> void:
    get_window().title = "海岸浪花 · 泡沫造型"
    get_window().size = Vector2i(1160, 740)
    get_window().min_size = Vector2i(920, 620)
    $EditorPreview.hide()
    $GroundPreview.hide()
    water_material = WATER_MATERIAL.duplicate() as ShaderMaterial
    ground_material = WATER_MATERIAL.duplicate() as ShaderMaterial
    ground_material.set_shader_parameter("render_ground", true)
    var backdrop := ColorRect.new()
    backdrop.color = Color("101f25")
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 16)
    margin.add_child(column)
    column.add_child(label("COAST LAB  /  像素海岸", 26))
    column.add_child(label("连贯浪尖 · 大小不一的泡孔 · 泡沫原地破碎消散", 15, Color("8aa9ad")))
    var row := HBoxContainer.new()
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 24)
    column.add_child(row)
    var aspect := AspectRatioContainer.new()
    aspect.ratio = 800.0 / 600.0
    aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
    aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
    row.add_child(aspect)
    var container := SubViewportContainer.new()
    container.stretch = true
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    aspect.add_child(container)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    container.add_child(viewport)
    # Node2D 将固定 800×600 世界空间映射到可缩放的预览面板。
    var drawing := Node2D.new()
    viewport.add_child(drawing)
    var ground := ColorRect.new()
    ground.size = Vector2(800, 600)
    ground.material = ground_material
    ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
    drawing.add_child(ground)
    var surface := ColorRect.new()
    surface.size = Vector2(800, 600)
    surface.material = water_material
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    drawing.add_child(surface)
    # 保持 Shader 世界坐标不随面板尺寸变化，使用 viewport 的 canvas_transform。
    viewport.size_changed.connect(func():
        viewport.canvas_transform = Transform2D(0.0, Vector2(viewport.size) / Vector2(800, 600), 0.0, Vector2.ZERO)
    )
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size.x = 272
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    row.add_child(scroll)
    var controls := VBoxContainer.new()
    controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    controls.add_theme_constant_override("separation", 8)
    scroll.add_child(controls)
    controls.add_child(label("浪花参数", 20))
    add_slider(controls, "每组浪花数量", "wave_count", 1.0, 4.0, 1.0, 3.0, " 道")
    add_slider(controls, "浪花推进速度", "wave_speed", 0.5, 2.5, 0.05, 1.0, " 倍")
    controls.add_child(HSeparator.new())
    controls.add_child(label("泡沫造型", 20))
    add_slider(controls, "泡沫纹理大小", "foam_pattern_size", 10.0, 40.0, 1.0, 18.0, "")
    add_slider(controls, "浪头连贯度", "foam_front_solid", 0.0, 1.0, 0.05, 0.9, "")
    add_slider(controls, "泡沫开孔程度", "breakup", 0.0, 1.0, 0.01, 0.55, "")
    add_slider(controls, "浪花宽度", "foam_width", 2.0, 20.0, 0.5, 8.0, "")
    controls.add_child(HSeparator.new())
    controls.add_child(label("水面波光", 20))
    add_slider(controls, "波光亮度", "sparkle_strength", 0.0, 1.0, 0.01, 0.65, "")
    add_slider(controls, "波光密度", "sparkle_density", 0.0, 1.0, 0.01, 0.45, "")
    add_slider(controls, "波光大小", "sparkle_scale", 0.5, 3.0, 0.05, 1.0, "")
    add_slider(controls, "波光变化速度", "sparkle_speed", 0.0, 2.5, 0.05, 0.65, "")
    controls.add_child(HSeparator.new())
    controls.add_child(label("浅水与泡沫", 20))
    add_slider(controls, "上岸距离", "runup", 0.0, 50.0, 1.0, 24.0, "")
    add_slider(controls, "向海退水距离", "backwash_distance", 0.0, 80.0, 1.0, 38.0, "")
    add_slider(controls, "薄水消退速度", "drain_speed", 0.5, 2.0, 0.05, 1.0, "")
    add_slider(controls, "浪后碎泡沫", "foam_residue", 0.0, 1.0, 0.05, 0.65, "")
    add_slider(controls, "浅水不透明度", "shallow_opacity", 0.0, 1.0, 0.01, 0.32, "")
    add_slider(controls, "深水不透明度", "deep_opacity", 0.0, 1.0, 0.01, 0.94, "")
    add_slider(controls, "每组时长", "wave_period", 2.0, 10.0, 0.1, 5.5, " s")
    add_slider(controls, "水边随机幅度", "shore_randomness", 0.0, 32.0, 1.0, 24.0, "")
    add_slider(controls, "过渡带半宽", "transition_width", 24.0, 120.0, 1.0, 64.0, "")
    add_slider(controls, "像素大小", "pixel_size", 1.0, 6.0, 1.0, 2.0, "")
    controls.add_child(HSeparator.new())
    var views := OptionButton.new()
    for text in ["完整画面", "海岸距离", "泡沫遮罩", "动态水深（黑干 / 亮深）", "原地消散的碎泡沫", "水面高光"]:
        views.add_item(text)
    views.item_selected.connect(func(index: int): water_material.set_shader_parameter("debug_view", index))
    controls.add_child(views)
    var buttons := HBoxContainer.new()
    controls.add_child(buttons)
    pause_button = Button.new()
    pause_button.text = "暂停"
    pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pause_button.pressed.connect(toggle_play)
    buttons.add_child(pause_button)
    var reset := Button.new()
    reset.text = "重置"
    reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reset.pressed.connect(func():
        for key in sliders:
            sliders[key][0].value = sliders[key][1]
        elapsed = 0.0
        views.select(0)
        water_material.set_shader_parameter("debug_view", 0)
    )
    buttons.add_child(reset)
    phase_label = label("向岸推进", 16, Color("b6dfc5"))
    controls.add_child(phase_label)
    phase_bar = ProgressBar.new()
    phase_bar.show_percentage = false
    phase_bar.custom_minimum_size.y = 5
    controls.add_child(phase_bar)
    controls.add_child(label("拖动时间轴可暂停观察", 13, Color("8aa9ad")))
    playhead = HSlider.new()
    playhead.min_value = 0.0
    playhead.max_value = 1.0
    playhead.step = 0.001
    playhead.value_changed.connect(func(value: float):
        if not update_playhead:
            playing = false
            pause_button.text = "播放"
            var period := float(water_material.get_shader_parameter("wave_period"))
            elapsed = (floor(elapsed / period) + min(value, 0.999)) * period
    )
    controls.add_child(playhead)
    column.add_child(label("空格：播放 / 暂停     R：重新播放     F6：在编辑器中运行本场景", 13, Color("8aa9ad")))

func add_slider(parent: VBoxContainer, title: String, key: String, minimum: float, maximum: float, increment: float, initial: float, suffix: String) -> void:
    var header := HBoxContainer.new()
    parent.add_child(header)
    var name_label := label(title, 15)
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(name_label)
    var number := label(str(initial) + suffix, 15, Color("8dd0c5"))
    header.add_child(number)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = increment
    slider.value = initial
    slider.value_changed.connect(func(value: float):
        var parameter: Variant = int(value) if key == "wave_count" else value
        water_material.set_shader_parameter(key, parameter)
        ground_material.set_shader_parameter(key, parameter)
        number.text = ("%.2f" % value).trim_suffix("0").trim_suffix(".") + suffix
    )
    parent.add_child(slider)
    sliders[key] = [slider, initial]
    var initial_parameter: Variant = int(initial) if key == "wave_count" else initial
    water_material.set_shader_parameter(key, initial_parameter)
    ground_material.set_shader_parameter(key, initial_parameter)

func toggle_play() -> void:
    playing = not playing
    pause_button.text = "暂停" if playing else "播放"

func _process(delta: float) -> void:
    if not is_instance_valid(water_material):
        return
    if playing:
        elapsed += delta
    water_material.set_shader_parameter("preview_time", elapsed)
    var phase := fposmod(elapsed / float(water_material.get_shader_parameter("wave_period")), 1.0)
    phase_bar.value = phase * 100.0
    var group_index := int(floor(elapsed / float(water_material.get_shader_parameter("wave_period")))) + 1
    var count := int(water_material.get_shader_parameter("wave_count"))
    phase_label.text = "第 %d 组 · 每组 %d 道浪错开推进" % [group_index, count]
    update_playhead = true
    playhead.value = phase
    update_playhead = false

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE:
            toggle_play()
        elif event.keycode == KEY_R:
            elapsed = 0.0
