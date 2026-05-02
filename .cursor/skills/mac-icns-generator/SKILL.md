---
name: mac-icns-generator
description: 根据提供的图片生成符合 macOS 规范的 .icns 图标。使用场景包括用户要求制作 Mac app 图标、生成 icns、转换 PNG/JPG/WebP 为 macOS 图标，或要求先移除图片白色背景再生成图标。
---

# macOS ICNS 图标生成

## 使用场景

当用户提供图片并要求生成 Mac app 图标、`.icns`、`iconset`，或提到“去白底”“移除白色背景”“mac 图标规范”时，使用本 skill。

## 工作流

1. 确认输入图片路径和期望输出路径。
2. 先处理图片：仅移除与图片四周连通的白色或近白色背景，保留主体内部白色和主体透明度。
3. 将主体居中放入正方形画布，默认保留 8% 边距。
4. 生成 macOS 标准 iconset 尺寸。
5. 使用 macOS `iconutil` 生成 `.icns`。
6. 验证输出文件存在，并提醒用户检查图标边缘和透明背景效果。

## 标准尺寸

生成以下文件后再打包为 `.icns`：

```text
icon_16x16.png
icon_16x16@2x.png
icon_32x32.png
icon_32x32@2x.png
icon_128x128.png
icon_128x128@2x.png
icon_256x256.png
icon_256x256@2x.png
icon_512x512.png
icon_512x512@2x.png
```

## 快速命令

依赖：

```bash
python3 -m pip install Pillow
```

运行：

```bash
python3 .cursor/skills/mac-icns-generator/scripts/make_icns.py input.png --output AppIcon.icns
```

常用参数：

```bash
python3 .cursor/skills/mac-icns-generator/scripts/make_icns.py input.png \
  --output AppIcon.icns \
  --white-threshold 245 \
  --softness 18 \
  --margin 0.08
```

## 参数建议

- `--white-threshold`：白底判断阈值，默认 `245`。背景偏灰时降低到 `235`。
- `--softness`：透明边缘柔化范围，默认 `18`。主体边缘发白时提高到 `24`。
- `--margin`：图标主体边距，默认 `0.08`。macOS app 图标通常需要留一点呼吸空间。
- `--keep-iconset`：保留中间 `.iconset` 文件夹，方便检查各尺寸 PNG。

白底移除只会处理从图片边缘连通到的白色区域；图标主体中被非白色区域包围的白色元素不会被透明化。

## 验证

生成后检查：

```bash
file AppIcon.icns
ls -lh AppIcon.icns
```

如果图标主体边缘出现白边，重新运行并提高 `--softness` 或降低 `--white-threshold`。如果主体太满或太小，调整 `--margin`。
