#!/usr/bin/env python3
"""Render the Klinote Finder icon from SF Pro (same face as the wordmark)."""

from __future__ import annotations

from pathlib import Path

import AppKit
import Quartz

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "apps/Klinote/Assets.xcassets/AppIcon.appiconset"

INK = AppKit.NSColor.colorWithSRGBRed_green_blue_alpha_(0.086, 0.196, 0.310, 1.0)
PAPER = AppKit.NSColor.colorWithSRGBRed_green_blue_alpha_(0.957, 0.945, 0.918, 1.0)

# (filename, pixel size)
SLOTS = [
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


def draw(size: int) -> AppKit.NSImage:
    image = AppKit.NSImage.alloc().initWithSize_(AppKit.NSMakeSize(size, size))
    image.lockFocus()
    INK.setFill()
    AppKit.NSBezierPath.fillRect_(AppKit.NSMakeRect(0, 0, size, size))

    # Full wordmark above 96px; a single k below — Finder 16/32 cannot hold seven letters.
    label = "klinote" if size >= 128 else "k"
    font_size = size * (0.22 if label == "klinote" else 0.62)
    kern = -size * (0.012 if label == "klinote" else 0)
    font = AppKit.NSFont.systemFontOfSize_weight_(font_size, AppKit.NSFontWeightSemibold)
    attrs = {
        AppKit.NSFontAttributeName: font,
        AppKit.NSForegroundColorAttributeName: PAPER,
        AppKit.NSKernAttributeName: kern,
    }
    text = AppKit.NSAttributedString.alloc().initWithString_attributes_(label, attrs)
    rect = text.boundingRectWithSize_options_context_(
        AppKit.NSMakeSize(size, size),
        AppKit.NSStringDrawingUsesLineFragmentOrigin,
        None,
    )
    x = (size - rect.size.width) / 2
    y = (size - rect.size.height) / 2 - size * 0.02
    text.drawAtPoint_(AppKit.NSMakePoint(x, y))
    image.unlockFocus()
    return image


def write_png(image: AppKit.NSImage, path: Path, pixels: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bitmap = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None,
        pixels,
        pixels,
        8,
        4,
        True,
        False,
        AppKit.NSCalibratedRGBColorSpace,
        0,
        0,
    )
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(
        AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(bitmap)
    )
    image.drawInRect_fromRect_operation_fraction_(
        AppKit.NSMakeRect(0, 0, pixels, pixels),
        AppKit.NSZeroRect,
        AppKit.NSCompositingOperationCopy,
        1.0,
    )
    AppKit.NSGraphicsContext.restoreGraphicsState()
    data = bitmap.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    data.writeToFile_atomically_(str(path), True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    cache: dict[int, AppKit.NSImage] = {}
    for name, pixels in SLOTS:
        if pixels not in cache:
            cache[pixels] = draw(pixels)
        write_png(cache[pixels], OUT / name, pixels)
        print("wrote", name)


if __name__ == "__main__":
    main()
