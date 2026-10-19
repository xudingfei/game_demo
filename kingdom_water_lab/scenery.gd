@tool
extends Node2D
## 原创程序绘制的示意风景，不使用游戏原作素材。

var elapsed := 0.0

func _process(delta: float) -> void:
    elapsed += delta
    queue_redraw()

func block(x: float, y: float, w: float, h: float, color: Color) -> void:
    draw_rect(Rect2(floor(x / 2.0) * 2.0, floor(y / 2.0) * 2.0, w, h), color)

func pine(x: float, base: float, height: float, tint: Color) -> void:
    block(x - 4, base - height * 0.55, 8, height * 0.55, Color("293b3b"))
    for tier in range(7):
        var k := float(tier) / 6.0
        var y := base - height + k * height * 0.69
        var width := 10.0 + k * height * 0.40
        # 用逐行矩形形成清晰的像素阶梯树冠。
        for row in range(9):
            var half := width * float(row + 1) / 9.0
            block(x - half, y + row * 4, half * 2, 4, tint)
        block(x - width * 0.60, y + 28, width * 0.58, 2, tint.lightened(0.08))

func _draw() -> void:
    for y in range(0, 600, 2):
        var sky := Color("233849").lerp(Color("ac8c77"), clampf(float(y) / 340.0, 0, 1))
        block(0, y, 800, 2, sky)
    # 月亮和缓慢移动的云都会出现在动态倒影里。
    block(572, 66, 28, 4, Color("e5d4aa"))
    block(566, 70, 40, 24, Color("e5d4aa"))
    block(572, 94, 28, 4, Color("e5d4aa"))
    for i in range(9):
        var x := fposmod(float(i * 113) + elapsed * 1.5, 960.0) - 100.0
        block(x, 114 + (i % 3) * 18, 76 + (i % 4) * 12, 4, Color("a18a85"))
    draw_colored_polygon(PackedVector2Array([Vector2(0,250), Vector2(100,170), Vector2(190,222), Vector2(300,140), Vector2(430,245), Vector2(560,176), Vector2(700,234), Vector2(800,180), Vector2(800,340), Vector2(0,340)]), Color("53636a"))
    for i in range(20):
        pine(i * 46 - 16, 330, 72 + (i * 37 % 85), Color("374e53"))
    for i in [0, 1, 2, 3, 12, 14, 15, 17]:
        pine(i * 47 + 12, 336, 115 + (i * 29 % 95), Color("243e40"))
    # 岸边小屋：暖窗与冷水形成容易辨识的反射。
    block(324, 268, 126, 68, Color("584a42"))
    for row in range(13):
        block(312 + row * 4, 268 - row * 4, 150 - row * 8, 4, Color("343e43"))
    for row in range(7):
        block(324, 274 + row * 9, 126, 2, Color("6a5748"))
    var warm := Color("edbb73").lerp(Color("ffe1a0"), 0.25 + sin(elapsed * 2.3) * 0.15)
    for x in [342, 414]:
        block(x, 286, 18, 22, warm)
        block(x + 8, 286, 2, 22, Color("695346"))
        block(x, 296, 18, 2, Color("695346"))
    block(376, 302, 18, 34, Color("302f30"))
    block(0, 336, 800, 4, Color("242f31"))
    block(310, 332, 160, 4, Color("a09067"))
    block(480, 286, 4, 54, Color("283739"))
    block(472, 284, 20, 4, Color("273537"))
    block(476, 290, 12, 14, warm)
