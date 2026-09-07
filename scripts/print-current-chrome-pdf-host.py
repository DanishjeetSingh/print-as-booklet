#!/usr/bin/env python3

import json
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

from pypdf import PdfReader


EXPECTED_ORIGIN = "chrome-extension://cdkefockfbcpgognldnfoihdcbmgdjab/"
MAX_MESSAGE_BYTES = 8 * 1024 * 1024
MAX_COOKIES = 1000


def read_message() -> dict:
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) != 4:
        raise ValueError("The Chrome extension sent an incomplete message.")

    message_length = struct.unpack("=I", raw_length)[0]
    if message_length <= 0 or message_length > MAX_MESSAGE_BYTES:
        raise ValueError("The Chrome extension message was an invalid size.")

    payload = sys.stdin.buffer.read(message_length)
    if len(payload) != message_length:
        raise ValueError("The Chrome extension message ended unexpectedly.")

    message = json.loads(payload.decode("utf-8"))
    if not isinstance(message, dict):
        raise ValueError("The Chrome extension message was invalid.")
    return message


def send_message(message: dict) -> None:
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("=I", len(payload)))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()


def show_error(message: str) -> None:
    script = """
on run argv
  display alert "Print Current PDF as Booklet" message (item 1 of argv) as critical
end run
"""
    subprocess.run(
        ["/usr/bin/osascript", "-", message],
        input=script,
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def validate_url(raw_url: object) -> str:
    if not isinstance(raw_url, str) or len(raw_url) > 8192:
        raise ValueError("The active tab does not contain a valid PDF URL.")

    parsed = urlparse(raw_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Open a PDF from an http:// or https:// address first.")
    return raw_url


def write_cookie_jar(cookies: object, output_path: Path) -> None:
    if not isinstance(cookies, list) or len(cookies) > MAX_COOKIES:
        raise ValueError("Chrome returned an invalid cookie set.")

    lines = ["# Netscape HTTP Cookie File"]
    for cookie in cookies:
        if not isinstance(cookie, dict):
            continue

        domain = cookie.get("domain")
        path = cookie.get("path", "/")
        name = cookie.get("name")
        value = cookie.get("value")
        if not all(isinstance(item, str) for item in (domain, path, name, value)):
            continue
        if any("\t" in item or "\n" in item or "\r" in item for item in (domain, path, name, value)):
            continue

        include_subdomains = "TRUE" if domain.startswith(".") else "FALSE"
        secure = "TRUE" if cookie.get("secure") else "FALSE"
        expiration = cookie.get("expirationDate")
        expiration_value = int(expiration) if isinstance(expiration, (int, float)) else 0
        jar_domain = f"#HttpOnly_{domain}" if cookie.get("httpOnly") else domain
        lines.append(
            "\t".join(
                (
                    jar_domain,
                    include_subdomains,
                    path,
                    secure,
                    str(expiration_value),
                    name,
                    value,
                )
            )
        )

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    output_path.chmod(0o600)


def fetch_pdf(url: str, cookie_jar: Path, output_path: Path) -> None:
    result = subprocess.run(
        [
            "/usr/bin/curl",
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--connect-timeout",
            "15",
            "--max-time",
            "300",
            "--retry",
            "2",
            "--cookie",
            str(cookie_jar),
            "--user-agent",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/140 Safari/537.36",
            "--output",
            str(output_path),
            url,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "Unknown download error"
        raise RuntimeError(f"Chrome's PDF could not be fetched: {detail}")

    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError("The active tab returned an empty file.")
    if b"%PDF-" not in output_path.read_bytes()[:1024]:
        raise RuntimeError("The active tab did not return a PDF file.")


def process_message(message: dict, support_dir: Path) -> dict:
    url = validate_url(message.get("url"))
    booklet_printer = support_dir / "print-booklet.zsh"
    if not booklet_printer.is_file():
        raise RuntimeError("The local Print as Booklet workflow is not installed.")

    with tempfile.TemporaryDirectory(prefix="print-booklet-chrome-") as temp_dir_name:
        temp_dir = Path(temp_dir_name)
        cookie_jar = temp_dir / "cookies.txt"
        source_pdf = temp_dir / "source.pdf"

        write_cookie_jar(message.get("cookies"), cookie_jar)
        fetch_pdf(url, cookie_jar, source_pdf)
        page_count = len(PdfReader(source_pdf).pages)
        if page_count < 1:
            raise RuntimeError("The downloaded PDF contains no pages.")

        environment = os.environ.copy()
        if message.get("dryRun") is True:
            environment["PRINT_BOOKLET_DRY_RUN"] = "1"

        result = subprocess.run(
            [str(booklet_printer), str(source_pdf)],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or "Unknown booklet error"
            raise RuntimeError(f"The booklet could not be prepared: {detail}")

        return {"ok": True, "pageCount": page_count}


def main() -> int:
    try:
        caller_origin = sys.argv[1] if len(sys.argv) > 1 else ""
        if caller_origin and caller_origin != EXPECTED_ORIGIN:
            raise PermissionError("The native helper rejected an unknown Chrome extension.")

        message = read_message()
        support_dir = Path.home() / "Library/Application Support/Print Booklet"
        response = process_message(message, support_dir)
    except Exception as error:
        message = str(error)
        show_error(message)
        response = {"ok": False, "error": message}

    send_message(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
