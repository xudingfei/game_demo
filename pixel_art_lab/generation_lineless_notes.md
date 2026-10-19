# 无粗黑描边机甲

使用内置 image_gen 工具，以 `sample_mech_flat.png` 为编辑目标。输出为 `sample_mech_lineless.png`，保留透明背景与平视侧面结构，移除外轮廓和装甲分界的粗黑线，使用相邻色块表达结构。原始文件保留备用。Shader 仍只负责透明轮廓外描边，不自动生成内部结构线。

## 完整提示词

```text
Use case: precise-object-edit / style-transfer.
Edit target: supplied flat blue and orange side-view multi-legged artillery mech.
Task: produce the SAME simplified flat side-view mech, but REMOVE ALL DRAWN OUTLINES, ALL DARK CONTOUR STROKES. This source image will receive a uniform black outline later from a game shader. It must not contain a baked black/navy silhouette border or black/navy borders around armor panels.
Preserve the right-facing strictly side-on horizontal cannon, long hull, multi-legged stance, joint locations, overall proportions, blue armor, orange accents and small cyan optic. Keep a transparent background.
Critical rendering: lineless cut-paper / flat shape illustration. Fill every existing contour stroke with the neighboring part's fill color, maintaining a solid filled silhouette: DO NOT leave transparent trenches where strokes used to be. Colored flat parts touch directly. For outside boundaries, colored armor goes all the way to alpha transparency without any dark rim. For interior divisions, use adjacent broad flat colors, never a dark line. Joints are plain medium slate-blue circles without rings. Far legs and undercarriage may be broad muted slate-blue shapes, but not near-black. Feet end in their local fill color, not dark soles or contour bands. Cannon muzzle is a simple gray-blue block; a single small dark aperture is okay.
Remove unnecessary dark vents, narrow panel seams and redundant layers. No outlines anywhere, no thin mechanical linework, no rim lighting, no bevel strokes, no gradients, no texture, no dimensional shading except broad flat different-colored parts. Use a small coherent palette of solid medium blue, lighter blue, slate blue, orange and cyan. Clean simple 2D shapes, few details, no 3D effect, no pixelation.
Full mech with safe padding on all sides. Genuine transparent alpha outside and in open gaps between legs. No background, no ground shadow, no checkerboard, no lettering or watermark.
```

