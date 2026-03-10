#!/usr/bin/env python3
"""
gen-docs-icon.py
从 asset catalog 的 APP 图标生成 docs/ 用的圆角图标。
圆角比例 22.37%（iOS 标准），输出 180x180 PNG。

用法:
  python3 scripts/gen-docs-icon.py
"""

import os
from PIL import Image, ImageDraw

# 路径配置（相对项目根目录）
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SOURCE_ICON = os.path.join(PROJECT_ROOT, "PhotoTTS", "Assets.xcassets", "AppIcon.appiconset", "icon_180x180.png")
OUTPUT_ICON = os.path.join(PROJECT_ROOT, "docs", "icon_180x180.png")

# iOS 标准圆角比例
CORNER_RATIO = 0.2237
SIZE = 180


def add_rounded_corners(img, radius):
    """为图片添加圆角，透明背景。"""
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
    result = img.copy().convert("RGBA")
    result.putalpha(mask)
    return result


def main():
    if not os.path.exists(SOURCE_ICON):
        print(f"error: source icon not found: {SOURCE_ICON}")
        raise SystemExit(1)

    img = Image.open(SOURCE_ICON).convert("RGBA")
    img = img.resize((SIZE, SIZE), Image.LANCZOS)

    radius = int(SIZE * CORNER_RATIO)
    result = add_rounded_corners(img, radius)

    os.makedirs(os.path.dirname(OUTPUT_ICON), exist_ok=True)
    result.save(OUTPUT_ICON, "PNG")
    print(f"ok: {OUTPUT_ICON} ({SIZE}x{SIZE}, radius={radius}px)")


if __name__ == "__main__":
    main()
