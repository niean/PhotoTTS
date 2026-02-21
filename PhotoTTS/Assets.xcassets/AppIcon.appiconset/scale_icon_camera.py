#!/usr/bin/env python3
"""将图标中的相机放大 30%：整图 1.3x 缩放后居中裁剪回原尺寸。"""
import os
from pathlib import Path
from PIL import Image

ICON_DIR = Path(__file__).resolve().parent
SCALE = 1.3

for f in sorted(ICON_DIR.glob("icon_*.png")):
    im = Image.open(f).convert("RGBA")
    w, h = im.size
    new_w, new_h = int(w * SCALE), int(h * SCALE)
    scaled = im.resize((new_w, new_h), Image.Resampling.LANCZOS)
    # 居中裁剪回原尺寸
    left = (new_w - w) // 2
    top = (new_h - h) // 2
    cropped = scaled.crop((left, top, left + w, top + h))
    cropped.save(f)
    print(f.name)
