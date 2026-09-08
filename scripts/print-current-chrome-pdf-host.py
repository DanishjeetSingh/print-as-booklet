#!/usr/bin/env python3

import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlencode, urlparse, urlunparse

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
  display alert "Print Article or PDF as Booklet" message (item 1 of argv) as critical
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
        raise ValueError("The active tab does not contain a valid article or PDF URL.")

    parsed = urlparse(raw_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Open a Substack article or online PDF first.")
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


def fetch_url(
    url: str,
    cookie_jar: Path,
    output_path: Path,
    *,
    accept: str | None = None,
    referer: str | None = None,
) -> str:
    command = [
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
        "--write-out",
        "%{url_effective}",
    ]
    if accept:
        command.extend(("--header", f"Accept: {accept}"))
    if referer:
        command.extend(("--referer", referer))
    command.append(url)

    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "Unknown download error"
        raise RuntimeError(f"Chrome's page could not be fetched: {detail}")

    return result.stdout.strip() or url


def fetch_json(url: str, cookie_jar: Path, temp_dir: Path, referer: str | None = None) -> dict:
    descriptor, temp_name = tempfile.mkstemp(prefix="substack-metadata-", suffix=".json", dir=temp_dir)
    os.close(descriptor)
    metadata_path = Path(temp_name)
    try:
        fetch_url(
            url,
            cookie_jar,
            metadata_path,
            accept="application/json",
            referer=referer,
        )
        payload = json.loads(metadata_path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Substack returned invalid article metadata.")
        return payload
    finally:
        metadata_path.unlink(missing_ok=True)


def positive_post_id(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, str)):
        try:
            result = int(value)
        except ValueError:
            return None
        return result if result > 0 else None
    return None


def post_details(payload: dict) -> tuple[int | None, str | None]:
    post = payload.get("post")
    records = [post, payload] if isinstance(post, dict) else [payload]
    for record in records:
        for key in ("id", "post_id", "postId"):
            post_id = positive_post_id(record.get(key))
            if post_id:
                canonical = record.get("canonical_url")
                return post_id, canonical if isinstance(canonical, str) else None
    return None, None


def post_id_from_html(html: str) -> int | None:
    candidates = [html]
    decoded = html
    for _ in range(2):
        decoded = (
            decoded.replace(r'\"', '"')
            .replace(r"\u0022", '"')
            .replace("&quot;", '"')
            .replace("%22", '"')
            .replace("%3A", ":")
        )
    if decoded != html:
        candidates.append(decoded)

    patterns = (
        r'["\']postId["\']\s*:\s*["\']?(\d+)',
        r'["\']post_id["\']\s*:\s*["\']?(\d+)',
        r'postId(?:%22|&quot;|\\u0022)?\s*(?::|%3A)\s*(?:%22|&quot;|\\u0022)?(\d+)',
    )
    for candidate in candidates:
        for pattern in patterns:
            match = re.search(pattern, candidate, flags=re.IGNORECASE)
            if match:
                return positive_post_id(match.group(1))
    return None


def pdf_url_for(canonical_url: str, post_id: int) -> str:
    parsed = urlparse(canonical_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise RuntimeError("Substack returned an invalid canonical article URL.")
    return urlunparse(
        (parsed.scheme, parsed.netloc, "/api/v1/post/pdf", "", urlencode({"postId": post_id}), "")
    )


def canonical_post(post_id: int, cookie_jar: Path, temp_dir: Path) -> tuple[int, str]:
    endpoint = f"https://substack.com/api/v1/posts/by-id/{post_id}"
    payload = fetch_json(endpoint, cookie_jar, temp_dir)
    resolved_id, canonical = post_details(payload)
    if not resolved_id or not canonical:
        raise RuntimeError("Substack did not return the article's publication address.")
    return resolved_id, canonical


def resolve_pdf_url(article_or_pdf_url: str, cookie_jar: Path, temp_dir: Path) -> str:
    parsed = urlparse(article_or_pdf_url)
    query_post_id = positive_post_id(parse_qs(parsed.query).get("postId", [None])[0])
    if parsed.path.rstrip("/").lower() == "/api/v1/post/pdf" and query_post_id:
        return article_or_pdf_url

    reader_match = re.match(r"^/home/post/p-(\d+)(?:/|$)", parsed.path, flags=re.IGNORECASE)
    if reader_match:
        post_id, canonical = canonical_post(int(reader_match.group(1)), cookie_jar, temp_dir)
        return pdf_url_for(canonical, post_id)

    article_path = temp_dir / "article.html"
    final_url = fetch_url(
        article_or_pdf_url,
        cookie_jar,
        article_path,
        accept="text/html,application/xhtml+xml,application/pdf",
    )
    final_parsed = urlparse(final_url)
    final_query_post_id = positive_post_id(parse_qs(final_parsed.query).get("postId", [None])[0])
    if final_parsed.path.rstrip("/").lower() == "/api/v1/post/pdf" and final_query_post_id:
        return final_url

    slug_match = re.search(r"/p/([^/?#]+)", final_parsed.path, flags=re.IGNORECASE)
    api_post_id = None
    api_canonical = None
    if slug_match:
        slug = quote(unquote(slug_match.group(1)), safe="")
        metadata_url = urlunparse(
            (final_parsed.scheme, final_parsed.netloc, f"/api/v1/posts/{slug}", "", "", "")
        )
        try:
            api_post_id, api_canonical = post_details(
                fetch_json(metadata_url, cookie_jar, temp_dir, referer=final_url)
            )
        except (RuntimeError, ValueError, json.JSONDecodeError):
            pass

    html = article_path.read_text(encoding="utf-8", errors="replace")
    post_id = api_post_id or post_id_from_html(html)
    if not post_id:
        raise RuntimeError("The Substack post ID could not be found in the active article.")

    try:
        canonical_id, canonical_url = canonical_post(post_id, cookie_jar, temp_dir)
        return pdf_url_for(canonical_url, canonical_id)
    except (RuntimeError, ValueError, json.JSONDecodeError):
        return pdf_url_for(api_canonical or final_url, post_id)


def fetch_pdf(url: str, cookie_jar: Path, output_path: Path, referer: str | None = None) -> None:
    fetch_url(url, cookie_jar, output_path, accept="application/pdf", referer=referer)

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
        pdf_url = resolve_pdf_url(url, cookie_jar, temp_dir)
        fetch_pdf(pdf_url, cookie_jar, source_pdf, referer=url)
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
