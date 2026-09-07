#!/bin/zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/Library/TeX/texbin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly script_dir="${0:A:h}"
readonly config_file="$script_dir/config.zsh"
readonly page_numberer="$script_dir/add-page-numbers.py"
readonly binding_guide="$script_dir/add-binding-guide.py"
readonly temp_root="${TMPDIR:-/tmp}"

typeset printer_name=""
typeset paper_size="Letter"
typeset pdfbook_paper="letterpaper"

if [[ -f "$config_file" ]]; then
  source "$config_file"
fi

if [[ -z "$printer_name" ]]; then
  printer_name="$(/usr/bin/lpstat -d 2>/dev/null | /usr/bin/sed 's/^system default destination: //')"
fi

readonly pdfbook2_bin="${PRINT_BOOKLET_PDFBOOK2:-$(command -v pdfbook2 || true)}"
readonly pdfinfo_bin="${PRINT_BOOKLET_PDFINFO:-$(command -v pdfinfo || true)}"
readonly python_bin="${PRINT_BOOKLET_PYTHON:-$script_dir/.venv/bin/python3}"

typeset -i dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
elif [[ "${PRINT_BOOKLET_DRY_RUN:-0}" == "1" ]]; then
  dry_run=1
fi

if (( $# == 0 )); then
  print -u2 "Select at least one PDF in Finder."
  exit 64
fi

if [[ -z "$pdfbook2_bin" || ! -x "$pdfbook2_bin" ]]; then
  print -u2 "pdfbook2 is not installed. Run: brew install pdfbook2"
  exit 69
fi

if [[ ! -x "$python_bin" || ! -f "$page_numberer" || ! -f "$binding_guide" ]]; then
  print -u2 "The page-numbering environment is unavailable. Run install.sh again."
  exit 69
fi

if [[ -z "$printer_name" ]]; then
  print -u2 "No default printer is configured. Set printer_name in config.zsh."
  exit 69
fi

if (( ! dry_run )) && ! /usr/bin/lpstat -p "$printer_name" >/dev/null 2>&1; then
  print -u2 "Printer $printer_name is not available."
  exit 69
fi

job_temp_dir="$(/usr/bin/mktemp -d "${temp_root%/}/print-booklet.XXXXXX")"

cleanup() {
  if [[ -n "${job_temp_dir:-}" && "$job_temp_dir" == "${temp_root%/}"/print-booklet.* ]]; then
    /bin/rm -rf -- "$job_temp_dir"
  fi
}
trap cleanup EXIT INT TERM

typeset -i submitted_count=0
typeset -i item_number=0

for source_pdf in "$@"; do
  (( item_number += 1 ))

  if [[ ! -f "$source_pdf" || "${source_pdf:e:l}" != "pdf" ]]; then
    print -u2 "Not a PDF file: $source_pdf"
    exit 65
  fi

  working_pdf="$job_temp_dir/input-${item_number}.pdf"
  numbered_pdf="$job_temp_dir/numbered-${item_number}.pdf"
  imposed_pdf="$job_temp_dir/numbered-${item_number}-book.pdf"
  guided_pdf="$job_temp_dir/booklet-${item_number}-with-guide.pdf"
  /bin/cp -- "$source_pdf" "$working_pdf"

  "$python_bin" "$page_numberer" "$working_pdf" "$numbered_pdf"
  "$pdfbook2_bin" --paper="$pdfbook_paper" --no-crop "$numbered_pdf" >/dev/null

  if [[ ! -s "$imposed_pdf" ]]; then
    print -u2 "Booklet preparation failed for: $source_pdf"
    exit 70
  fi

  "$python_bin" "$binding_guide" "$imposed_pdf" "$guided_pdf"
  if [[ ! -s "$guided_pdf" ]]; then
    print -u2 "Binding guide preparation failed for: $source_pdf"
    exit 70
  fi

  if (( dry_run )); then
    if [[ -n "$pdfinfo_bin" ]]; then
      "$pdfinfo_bin" "$guided_pdf" | /usr/bin/grep -E '^(Pages|Page size)'
    else
      print "Prepared: $source_pdf"
    fi
    continue
  fi

  /usr/bin/lp \
    -d "$printer_name" \
    -n 1 \
    -o PageSize="$paper_size" \
    -o landscape \
    -o orientation-requested=4 \
    -o fit-to-page \
    -o sides=two-sided-short-edge \
    -o Duplex=DuplexTumble \
    -o ColorModel=Gray \
    -o cupsPrintQuality=Normal \
    "$guided_pdf"

  (( submitted_count += 1 ))
done

if (( ! dry_run )); then
  /usr/bin/osascript - "$submitted_count" "$printer_name" <<'APPLESCRIPT'
on run argv
  set jobCount to item 1 of argv
  set printerName to item 2 of argv
  display notification (jobCount & " booklet print job(s) submitted to " & printerName) with title "Print as Booklet"
end run
APPLESCRIPT
fi
