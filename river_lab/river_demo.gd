extends Control
## 独立场景：打开 river_demo.tscn，按 F6 运行。

var river_material: ShaderMaterial
var clock := 0.0
var tide_clock := 0.0
var paused := false
var auto_tide := false
var level_slider: HSlider
var status: Label
var explanation: Label
var slider_controls: Dictionary = {}
var tide_button: CheckButton
var pause_button: CheckButton
var mode_select: OptionButton

const NOTES := [
    "最终画面 = 河床 + 深浅水色 + 岸线 + 流动焦散 + 水下扭曲。拖动水位，观察浅滩和岛屿。",
    "河床原图只提供颜色。它不会告诉程序哪里高、哪里低。",
    "高度图：黑色代表低处，白色代表高处。每个像素与河床原图一一对应。",
    "水域遮罩：height ≤ water_level 时为白色，否则为黑色。涨水就是改变这条判断的阈值。",
    "水深 = max(水位 − 地形高度, 0)。越亮代表越深，用它控制颜色和扭曲。",
    "岸线：当前像素是水，但邻居有陆地。与之前学习的透明度描边原理相同。"
]

func _ready() -> void:
    get_window().size = Vector2i(1220, 800)
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
    var ui_theme := Theme.new()
    ui_theme.default_font = font
    ui_theme.default_font_size = 16
    theme = ui_theme

    river_material = preload("res://river_lab/river_material.tres").duplicate() as ShaderMaterial

    var background := ColorRect.new()
    background.color = Color("101c25")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 16)
    margin.add_child(root)
    var title := Label.new()
    title.text = "河流实验室  /  RIVER LAB"
    title.add_theme_font_size_override("font_size", 28)
    root.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "从高度图到动态水位 · Godot 4 着色器学习场景"
    subtitle.modulate = Color("9db5bf")
    root.add_child(subtitle)
    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 24)
    root.add_child(body)

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(left)
    var picture := TextureRect.new()
    picture.texture = preload("res://river_lab/assets/riverbed.png")
    picture.material = river_material
    picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
    picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.add_child(picture)
    explanation = Label.new()
    explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    explanation.custom_minimum_size.y = 72
    explanation.text = NOTES[0]
    left.add_child(explanation)

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size.x = 286
    body.add_child(scroll)
    var panel := VBoxContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.add_theme_constant_override("separation", 13)
    scroll.add_child(panel)
    mode_select = OptionButton.new()
    for text in ["最终效果", "01 · 河床原图", "02 · 高度图", "03 · 水域遮罩", "04 · 水深", "05 · 岸边描线"]:
        mode_select.add_item(text)
    mode_select.item_selected.connect(func(index: int):
        river_material.set_shader_parameter("view_mode", index)
        explanation.text = NOTES[index])
    panel.add_child(mode_select)
    level_slider = _slider(panel, "水位", "water_level", 0.0, 1.0, 0.01, 0.48)
    _slider(panel, "水色浓度", "water_opacity", 0.0, 1.0, 0.01, 0.55)
    _slider(panel, "岸线宽度 / 原图像素", "outline_size", 0.0, 5.0, 1.0, 1.0)
    _slider(panel, "流动速度", "flow_speed", 0.0, 2.0, 0.05, 0.65)
    _slider(panel, "水下扭曲 / 像素", "distortion_pixels", 0.0, 5.0, 0.1, 1.3)
    _slider(panel, "焦散亮度", "caustics_strength", 0.0, 0.6, 0.01, 0.18)
    tide_button = CheckButton.new()
    tide_button.text = "自动涨水 / 退水"
    tide_button.toggled.connect(func(enabled: bool):
        auto_tide = enabled
        level_slider.editable = not enabled)
    panel.add_child(tide_button)
    pause_button = CheckButton.new()
    pause_button.text = "暂停动画"
    pause_button.toggled.connect(func(enabled: bool): paused = enabled)
    panel.add_child(pause_button)
    var reset := Button.new()
    reset.text = "恢复初始参数"
    reset.pressed.connect(_reset)
    panel.add_child(reset)
    status = Label.new()
    status.modulate = Color("a2cfbf")
    root.add_child(status)

func _slider(parent: VBoxContainer, title: String, parameter: String,
        minimum: float, maximum: float, increment: float, initial: float) -> HSlider:
    var label := Label.new()
    label.text = "%s  %.2f" % [title, initial]
    parent.add_child(label)
    var slider := HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = increment
    slider.value = initial
    slider.value_changed.connect(func(value: float):
        river_material.set_shader_parameter(parameter, value)
        label.text = "%s  %.2f" % [title, value])
    parent.add_child(slider)
    river_material.set_shader_parameter(parameter, initial)
    slider_controls[parameter] = [slider, initial]
    return slider

func _reset() -> void:
    tide_button.button_pressed = false
    pause_button.button_pressed = false
    clock = 0.0
    tide_clock = 0.0
    for entry in slider_controls.values():
        entry[0].value = entry[1]
    mode_select.select(0)
    river_material.set_shader_parameter("view_mode", 0)
    explanation.text = NOTES[0]

func _process(delta: float) -> void:
    if not paused:
        clock += delta
        tide_clock += delta
        if auto_tide:
            level_slider.value = 0.48 + sin(tide_clock * 0.30) * 0.26
    river_material.set_shader_parameter("animation_time", clock)
    status.text = "水位 %.2f  ·  原图 480 × 300  ·  %s" % [level_slider.value,
        "动画已暂停" if paused else "动画运行中"]
