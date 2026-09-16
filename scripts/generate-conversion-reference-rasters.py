#!/usr/bin/env python3
"""Generate analytical sRGB reference rasters without Apple image APIs.

These references are independent of Dropshot's Image I/O/Core Graphics conversion
path. They are deterministic mathematical oracles for synthetic fixtures; they
were independently reviewed for this synthetic corpus (see Fixtures/README.md).
They are not photographic or HDR references, and no human signoff is claimed.

Display P3 conversion follows W3C CSS Color 4 sections 10.4 and 19:
https://www.w3.org/TR/css-color-4/#predefined-display-p3
https://www.w3.org/TR/css-color-4/#color-conversion-code

The specification defines Display P3 with DCI-P3 primaries, a D65 white point,
and the sRGB transfer function. Its sample code supplies the exact rational
Display-P3-to-XYZ-D65 and XYZ-D65-to-linear-sRGB matrices used below.
"""

from __future__ import annotations

import binascii
import math
from pathlib import Path
import struct
import sys
import zlib


P3_TO_XYZ = (
    (608311 / 1250200, 189793 / 714400, 198249 / 1000160),
    (35783 / 156275, 247089 / 357200, 198249 / 2500400),
    (0, 32229 / 714400, 5220557 / 5000800),
)

XYZ_TO_SRGB = (
    (12831 / 3959, -329 / 214, -1974 / 3959),
    (-851781 / 878810, 1648619 / 878810, 36519 / 878810),
    (705 / 12673, -2585 / 12673, 705 / 667),
)

P3_PATCHES = (
    (0.50, 0.40, 0.30),
    (0.30, 0.55, 0.40),
    (0.30, 0.40, 0.60),
    (0.50, 0.50, 0.50),
)

ORIENTATION_PATCHES = (
    ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)),
    ((0, 255, 0), (255, 0, 0), (255, 255, 0), (0, 0, 255)),
    ((255, 255, 0), (0, 0, 255), (0, 255, 0), (255, 0, 0)),
    ((0, 0, 255), (255, 255, 0), (255, 0, 0), (0, 255, 0)),
    ((255, 0, 0), (0, 0, 255), (0, 255, 0), (255, 255, 0)),
    ((0, 0, 255), (255, 0, 0), (255, 255, 0), (0, 255, 0)),
    ((255, 255, 0), (0, 255, 0), (0, 0, 255), (255, 0, 0)),
    ((0, 255, 0), (255, 255, 0), (255, 0, 0), (0, 0, 255)),
)


def multiply(matrix: tuple[tuple[float, ...], ...], vector: tuple[float, ...]) -> tuple[float, ...]:
    return tuple(sum(coefficient * component for coefficient, component in zip(row, vector)) for row in matrix)


def to_linear(component: float) -> float:
    if component < 0.04045:
        return component / 12.92
    return ((component + 0.055) / 1.055) ** 2.4


def from_linear(component: float) -> float:
    if component > 0.0031308:
        return 1.055 * component ** (1 / 2.4) - 0.055
    return 12.92 * component


def display_p3_to_srgb8(color: tuple[float, float, float]) -> tuple[int, int, int]:
    linear_p3 = tuple(to_linear(component) for component in color)
    xyz = multiply(P3_TO_XYZ, linear_p3)
    linear_srgb = multiply(XYZ_TO_SRGB, xyz)
    if not all(0 <= component <= 1 for component in linear_srgb):
        raise ValueError(f"reference patch is outside the sRGB gamut: {color!r}")
    # The published rational matrices can leave neutral components a few ULPs
    # below an exact half-code boundary. Round half-up with a sub-code epsilon.
    return tuple(math.floor(from_linear(component) * 255 + 0.5000001) for component in linear_srgb)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixels: bytes, *, has_alpha: bool = False) -> None:
    channels = 4 if has_alpha else 3
    if len(pixels) != width * height * channels:
        raise ValueError("pixel buffer has the wrong size")
    rows = b"".join(
        b"\x00" + pixels[row * width * channels : (row + 1) * width * channels]
        for row in range(height)
    )
    header = struct.pack(">IIBBBBB", width, height, 8, 6 if has_alpha else 2, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"sRGB", b"\x00")
        + png_chunk(b"IDAT", zlib.compress(rows, level=9))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def quadrant_pixels(width: int, height: int, colors: tuple[tuple[int, ...], ...]) -> bytes:
    if len(colors) != 4 or width % 2 or height % 2:
        raise ValueError("quadrant references require four colors and even dimensions")
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            quadrant = (2 if y >= height // 2 else 0) + (1 if x >= width // 2 else 0)
            pixels.extend(colors[quadrant])
    return bytes(pixels)


def generate(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)

    p3_srgb = tuple(display_p3_to_srgb8(color) for color in P3_PATCHES)
    expected = ((132, 101, 73), (49, 142, 99), (69, 103, 157), (128, 128, 128))
    if p3_srgb != expected:
        raise AssertionError(f"Display P3 reference values changed: {p3_srgb!r}")
    write_png(directory / "reference-display-p3.png", 32, 24, quadrant_pixels(32, 24, p3_srgb))

    for orientation, colors in enumerate(ORIENTATION_PATCHES, start=1):
        width, height = (64, 96) if orientation >= 5 else (96, 64)
        write_png(
            directory / f"reference-orientation-{orientation}.png",
            width,
            height,
            quadrant_pixels(width, height, colors),
        )

    transparency = (
        (0, 0, 0, 0),
        (255, 0, 0, 128),
        (0, 0, 255, 255),
        (255, 255, 0, 255),
    )
    write_png(
        directory / "reference-transparency.png",
        96,
        64,
        quadrant_pixels(96, 64, transparency),
        has_alpha=True,
    )


if __name__ == "__main__":
    output_directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("DropshotTests/Fixtures")
    generate(output_directory)
