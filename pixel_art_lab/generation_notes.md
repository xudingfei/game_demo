# 平视火炮机甲生成记录

- 方式：内置 image_gen 工具（imagegen 技能），非 CLI。
- 时间：2026-10-19。
- 输出：`sample_mech_side.png`，1774×887，RGBA。原始透明度保留。
- 用途：普通 2D 插画作为着色器输入，由项目实时像素化、限色和描边。
- 新图从头生成，不以之前的 SVG 作为参考。

## 完整提示词

```text
Use case: stylized-concept.
Asset type: transparent-background source illustration for a Godot 2D sprite pixel-art conversion demo.
Primary request: A beautifully designed six-legged artillery mech in STRICT EYE-LEVEL ORTHOGRAPHIC SIDE PROFILE, facing right. Replace a crude placeholder with professional game concept art.
Subject: one complete compact, heavyweight mobile artillery walker with exactly three pairs of articulated mechanical legs (six total), a low sloped armored hull and a substantial turret carrying one long horizontally aimed cannon. Three near legs readable separately front/middle/rear; opposite-side legs subtly staggered to reveal their feet, rendered darker. Mechanically convincing hip joints, hydraulic pistons, broad segmented feet, sensible weight distribution. All feet share a horizontal ground level. Handsome cohesive industrial design, purposeful large armor shapes and restrained details, a few vents, bolts and protected cables, no humanoid face. Strong silhouette legible when reduced to a small sprite.
Style: premium hand-painted 2D science-fiction game asset, confident clean edges, controlled cel-shaded volumes with a little smooth shading, tasteful wear, NOT pixel art yet (the engine shader will pixelate it), not a vector icon, not a toy, no sketch lines. Muted blue-grey and desaturated teal armor, dark graphite joints, restrained burnt-orange safety panels, tiny cyan optics. Maintain broad areas of simple color to support a 16-color conversion.
Composition: landscape canvas, full machine centered with safe transparent padding on every side; cannon tip and all six feet entirely visible. Camera perfectly level at hull height, looking square-on at the SIDE, no three-quarter view, no isometric view, no top-down view, no visible roof planes from above. Cannon parallel to ground. A single asset, not a concept sheet.
Background: actual transparent alpha, including gaps between legs and under the hull. No ground plane, no cast shadow, no scenery, no gradient backdrop, no checkerboard drawn into image.
No text, no logos, no labels, no watermark.
```

