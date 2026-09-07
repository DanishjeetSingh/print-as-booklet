#!/bin/zsh

set -euo pipefail

readonly support_dir="$HOME/Library/Application Support/Print Booklet"
exec "$support_dir/.venv/bin/python3" "$support_dir/print-current-chrome-pdf-host.py" "$@"
