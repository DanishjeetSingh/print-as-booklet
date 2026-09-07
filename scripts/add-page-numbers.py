#!/usr/bin/env python3

import io
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas


FONT_NAME = "Times-Roman"
BINDING_BAND_WIDTH = 0.5 * 72.0 / 2.54
BINDING_BAND_GRAY = 0.91
STAPLE_MARK_GRAY = 0.38


def draw_binding_guide(overlay_canvas: canvas.Canvas, height: float) -> None:
    """Draw a 5 mm binding band and three staple-position marks."""
    overlay_canvas.saveState()
    overlay_canvas.setFillColorRGB(
        BINDING_BAND_GRAY,
        BINDING_BAND_GRAY,
        BINDING_BAND_GRAY,
    )
    overlay_canvas.rect(0, 0, BINDING_BAND_WIDTH, height, stroke=0, fill=1)

    marker_width = BINDING_BAND_WIDTH * 0.64
    marker_height = 1.5
    marker_x = (BINDING_BAND_WIDTH - marker_width) / 2.0
    overlay_canvas.setFillColorRGB(
        STAPLE_MARK_GRAY,
        STAPLE_MARK_GRAY,
        STAPLE_MARK_GRAY,
    )
    for vertical_fraction in (0.25, 0.5, 0.75):
        marker_y = height * vertical_fraction - marker_height / 2.0
        overlay_canvas.roundRect(
            marker_x,
            marker_y,
            marker_width,
            marker_height,
            marker_height / 2.0,
            stroke=0,
            fill=1,
        )
    overlay_canvas.restoreState()


def add_page_numbers(source_path: Path, output_path: Path) -> None:
    reader = PdfReader(source_path)
    writer = PdfWriter()

    for page_number, page in enumerate(reader.pages, start=1):
        if page.rotation:
            page.transfer_rotation_to_content()

        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        label = str(page_number)
        font_size = max(12.0, min(14.0, min(width, height) / 44.0))
        text_width = stringWidth(label, FONT_NAME, font_size)
        horizontal_padding = 5.0
        vertical_padding = 2.5
        baseline = max(20.0, height * 0.03)

        overlay_buffer = io.BytesIO()
        overlay_canvas = canvas.Canvas(overlay_buffer, pagesize=(width, height))
        if page_number == 1:
            draw_binding_guide(overlay_canvas, height)

        overlay_canvas.saveState()
        overlay_canvas.setFillColorRGB(1.0, 1.0, 1.0)
        if hasattr(overlay_canvas, "setFillAlpha"):
            overlay_canvas.setFillAlpha(0.88)
        overlay_canvas.roundRect(
            (width - text_width) / 2.0 - horizontal_padding,
            baseline - vertical_padding,
            text_width + 2.0 * horizontal_padding,
            font_size + 2.0 * vertical_padding,
            3.0,
            stroke=0,
            fill=1,
        )
        overlay_canvas.restoreState()
        overlay_canvas.setFillColorRGB(0.28, 0.28, 0.28)
        overlay_canvas.setFont(FONT_NAME, font_size)
        overlay_canvas.drawCentredString(width / 2.0, baseline, label)
        overlay_canvas.save()

        overlay_buffer.seek(0)
        overlay_page = PdfReader(overlay_buffer).pages[0]
        page.merge_page(overlay_page, over=True)
        writer.add_page(page)

    if reader.metadata:
        safe_metadata = {
            str(key): str(value)
            for key, value in reader.metadata.items()
            if value is not None
        }
        writer.add_metadata(safe_metadata)

    with output_path.open("wb") as output_stream:
        writer.write(output_stream)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: add-page-numbers.py INPUT.pdf OUTPUT.pdf", file=sys.stderr)
        return 64

    add_page_numbers(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
