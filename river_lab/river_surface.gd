extends Sprite2D
## 可复用节点的动画时钟。编辑器里可直接查看静态材质效果。
var elapsed := 0.0

func _process(delta: float) -> void:
    elapsed += delta
    (material as ShaderMaterial).set_shader_parameter("animation_time", elapsed)
