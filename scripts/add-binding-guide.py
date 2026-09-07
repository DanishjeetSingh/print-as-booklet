#!/usr/bin/env python3

import io
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas


CENTIMETER = 72.0 / 2.54
BINDING_BAND_WIDTH = 1.0 * CENTIMETER
BINDING_BAND_GRAY = 0.91
STAPLE_MARK_GRAY = 0.38
STAPLE_MARK_WIDTH = 3.0


def make_guide_overlay(width: float, height: float):
    overlay_buffer = io.BytesIO()
    overlay_canvas = canvas.Canvas(overlay_buffer, pagesize=(width, height))

    # pdfbook2 places source page 1 on the right half of the first sheet side.
    band_x = width / 2.0
    overlay_canvas.setFillColorRGB(
        BINDING_BAND_GRAY,
        BINDING_BAND_GRAY,
        BINDING_BAND_GRAY,
    )
    overlay_canvas.rect(
        band_x,
        0,
        BINDING_BAND_WIDTH,
        height,
        stroke=0,
        fill=1,
    )

    marker_height = BINDING_BAND_WIDTH * 0.64
    marker_x = band_x + (BINDING_BAND_WIDTH - STAPLE_MARK_WIDTH) / 2.0
    overlay_canvas.setFillColorRGB(
        STAPLE_MARK_GRAY,
        STAPLE_MARK_GRAY,
        STAPLE_MARK_GRAY,
    )
    for vertical_fraction in (0.15, 0.5, 0.85):
        marker_y = height * vertical_fraction - marker_height / 2.0
        overlay_canvas.roundRect(
            marker_x,
            marker_y,
            STAPLE_MARK_WIDTH,
            marker_height,
            STAPLE_MARK_WIDTH / 2.0,
            stroke=0,
            fill=1,
        )

    overlay_canvas.save()
    overlay_buffer.seek(0)
    return PdfReader(overlay_buffer).pages[0]


def add_binding_guide(source_path: Path, output_path: Path) -> None:
    reader = PdfReader(source_path)
    writer = PdfWriter()

    for sheet_side_number, page in enumerate(reader.pages, start=1):
        if page.rotation:
            page.transfer_rotation_to_content()

        if sheet_side_number == 1:
            width = float(page.mediabox.width)
            height = float(page.mediabox.height)
            page.merge_page(make_guide_overlay(width, height), over=True)

        writer.add_page(page)

    if reader.metadata:
        writer.add_metadata(
            {
                str(key): str(value)
                for key, value in reader.metadata.items()
                if value is not None
            }
        )

    with output_path.open("wb") as output_stream:
        writer.write(output_stream)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: add-binding-guide.py INPUT.pdf OUTPUT.pdf", file=sys.stderr)
        return 64

    add_binding_guide(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
