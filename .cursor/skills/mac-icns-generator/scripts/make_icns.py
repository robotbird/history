#!/usr/bin/env python3
"""Remove a white background from an image and build a macOS .icns file."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from collections import deque
from pathlib import Path

from PIL import Image


ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def alpha_for_pixel(red: int, green: int, blue: int, threshold: int, softness: int) -> int:
    distance_from_white = 255 - min(red, green, blue)
    if distance_from_white <= max(0, threshold - 255):
        return 0

    cutoff = 255 - threshold
    if distance_from_white <= cutoff:
        return 0
    if softness <= 0 or distance_from_white >= cutoff + softness:
        return 255

    return round(255 * (distance_from_white - cutoff) / softness)


def remove_white_background(image: Image.Image, threshold: int, softness: int) -> Image.Image:
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    visited = set()
    queue: deque[tuple[int, int]] = deque()

    def white_alpha_at(x: int, y: int) -> int:
        red, green, blue, _ = pixels[x, y]
        return alpha_for_pixel(red, green, blue, threshold, softness)

    def enqueue_if_background(x: int, y: int) -> None:
        if (x, y) not in visited and white_alpha_at(x, y) < 255:
            visited.add((x, y))
            queue.append((x, y))

    for x in range(width):
        enqueue_if_background(x, 0)
        enqueue_if_background(x, height - 1)
    for y in range(height):
        enqueue_if_background(0, y)
        enqueue_if_background(width - 1, y)

    while queue:
        x, y = queue.popleft()
        red, green, blue, alpha = pixels[x, y]
        pixels[x, y] = (red, green, blue, min(alpha, white_alpha_at(x, y)))

        for neighbor_x, neighbor_y in (
            (x - 1, y),
            (x + 1, y),
            (x, y - 1),
            (x, y + 1),
        ):
            if 0 <= neighbor_x < width and 0 <= neighbor_y < height:
                enqueue_if_background(neighbor_x, neighbor_y)

    return image


def center_on_square(image: Image.Image, size: int, margin: float) -> Image.Image:
    bbox = image.getbbox()
    if bbox is None:
        raise ValueError("处理后的图片为空，可能阈值过高导致主体也被移除。")

    cropped = image.crop(bbox)
    target_size = max(1, round(size * (1 - margin * 2)))
    scale = min(target_size / cropped.width, target_size / cropped.height)
    resized_size = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )

    resized = cropped.resize(resized_size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - resized.width) // 2, (size - resized.height) // 2)
    canvas.alpha_composite(resized, offset)
    return canvas


def build_iconset(image: Image.Image, iconset_dir: Path, margin: float) -> None:
    iconset_dir.mkdir(parents=True, exist_ok=True)
    for filename, size in ICON_SIZES:
        icon = center_on_square(image, size, margin)
        icon.save(iconset_dir / filename)


def run_iconutil(iconset_dir: Path, output_path: Path) -> None:
    if shutil.which("iconutil") is None:
        raise RuntimeError("找不到 macOS iconutil。请在 macOS 上运行此脚本。")

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(output_path)],
        check=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="移除图片白色背景并生成 macOS 标准 .icns 图标。"
    )
    parser.add_argument("input", type=Path, help="输入图片路径，例如 input.png")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("AppIcon.icns"),
        help="输出 .icns 路径，默认 AppIcon.icns",
    )
    parser.add_argument(
        "--white-threshold",
        type=int,
        default=245,
        help="判定为白色背景的阈值，默认 245",
    )
    parser.add_argument(
        "--softness",
        type=int,
        default=18,
        help="白底边缘透明度柔化范围，默认 18",
    )
    parser.add_argument(
        "--margin",
        type=float,
        default=0.08,
        help="图标主体边距比例，默认 0.08",
    )
    parser.add_argument(
        "--keep-iconset",
        action="store_true",
        help="保留中间 .iconset 目录",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = args.input.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    iconset_dir = output_path.with_suffix(".iconset")

    if not input_path.exists():
        raise FileNotFoundError(f"输入图片不存在：{input_path}")
    if not 0 <= args.margin < 0.5:
        raise ValueError("--margin 必须在 0 到 0.5 之间。")
    if not 0 <= args.white_threshold <= 255:
        raise ValueError("--white-threshold 必须在 0 到 255 之间。")

    source = Image.open(input_path)
    transparent = remove_white_background(source, args.white_threshold, args.softness)
    build_iconset(transparent, iconset_dir, args.margin)
    run_iconutil(iconset_dir, output_path)

    if not args.keep_iconset:
        shutil.rmtree(iconset_dir)

    print(f"已生成：{output_path}")


if __name__ == "__main__":
    main()
