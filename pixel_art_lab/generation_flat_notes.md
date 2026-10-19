# 简洁平面风格机甲

使用内置 image_gen 工具，以 `sample_mech_anime.png` 为编辑目标，生成 `sample_mech_flat.png`。目标是大幅减少内部细节和体积阴影，保留平视侧面、多足火炮轮廓、蓝橙配色与透明背景。

## 完整提示词

```text
Use case: style-transfer.
Edit target: supplied side profile blue-and-orange artillery walker.
User correction: make it a FLAT TWO-DIMENSIONAL DRAWING with FAR FEWER DETAILS. The previous image is still too volumetric and complicated. This must be a very substantial simplification, not just another cel shading pass.
Redraw as a beautifully designed minimalist 2D side-scroller game illustration, cut-paper-like broad flat shapes and clean consistent dark outlines. Keep the recognizable multi-legged artillery silhouette, horizontal long cannon pointing right, three pairs of mechanical legs, broad hull and turret, blue armor with a few orange accents. Three near legs plus staggered far legs indicated simply in darker flat blue. Entire machine visible, eye-level perfectly side-on orthographic elevation.
Simplification target: remove 85–90 percent of internal detail. Each upper leg and lower leg is one simple solid polygon. Joints are one plain circle each, not concentric rings. Feet are single broad simple shapes without toes or articulated fingers. Hull is two or three large solid shapes. Turret is one simple angular block. Cannon is a plain long narrow rectangle with one simple muzzle. At most one small cyan rectangular sensor and two simple vent slits on the whole machine. No exposed cables, no hydraulic rods, no screws, no rivets, no micro panels, no layered bevels, no mechanical innards, no highlights, no textures, no gradients, no weathering.
Use only approximately 6–8 flat colors total. At most ONE broad flat shadow patch per large part, preferably no shading at all; dark far legs distinguish depth. Absolutely no 3D volume-rendering, no glossy surfaces, no soft lighting, no top faces or perspective foreshortening. Think clean graphic shapes and charming readable game art, carefully balanced proportions, not a detailed anime engineering blueprint. Not pixelated yet: smooth clean raster edges, ready for pixelation in Godot.
True transparent alpha background, clear padding around cannon tip, antenna if present, and every foot. Transparent holes between limbs. No ground, no shadows on ground, no checkerboard, no lettering, labels, logos, watermark. One single static asset only.
```

