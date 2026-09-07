#!/bin/zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly script_dir="${0:A:h}"
readonly booklet_printer="$script_dir/print-booklet.zsh"
readonly temp_root="${TMPDIR:-/tmp}"

show_error() {
  local message="$1"
  /usr/bin/osascript - "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display alert "Print Copied PDF URL as Booklet" message (item 1 of argv) as critical
end run
APPLESCRIPT
  print -u2 -- "$message"
}

clipboard_text="${PRINT_BOOKLET_URL:-$(/usr/bin/pbpaste)}"
copied_url="$(print -rn -- "$clipboard_text" | /usr/bin/tr -d '\r' | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

case "$copied_url" in
  http://*|https://*) ;;
  *)
    show_error "Copy a direct PDF URL beginning with http:// or https://, then run the action again."
    exit 65
    ;;
esac

if [[ ! -x "$booklet_printer" ]]; then
  show_error "The Print as Booklet support files are missing. Run install.sh again."
  exit 69
fi

download_temp_dir="$(/usr/bin/mktemp -d "${temp_root%/}/print-booklet-url.XXXXXX")"
downloaded_pdf="$download_temp_dir/copied-url.pdf"

cleanup() {
  if [[ -n "${download_temp_dir:-}" && "$download_temp_dir" == "${temp_root%/}"/print-booklet-url.* ]]; then
    /bin/rm -rf -- "$download_temp_dir"
  fi
}
trap cleanup EXIT INT TERM

if ! /usr/bin/curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --connect-timeout 15 \
  --max-time 180 \
  --retry 2 \
  --user-agent "Mozilla/5.0 (Macintosh; Print Booklet Quick Action)" \
  --output "$downloaded_pdf" \
  "$copied_url"; then
  show_error "The copied URL could not be downloaded. It may require a browser login or may no longer be available."
  exit 69
fi

if [[ ! -s "$downloaded_pdf" ]] || ! LC_ALL=C /usr/bin/head -c 1024 "$downloaded_pdf" | /usr/bin/grep -a -q '%PDF-'; then
  show_error "The copied URL did not return a PDF file. Copy the PDF's direct URL rather than the surrounding webpage."
  exit 65
fi

"$booklet_printer" "$downloaded_pdf"
