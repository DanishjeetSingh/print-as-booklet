#!/bin/zsh

set -euo pipefail

readonly repo_dir="${0:A:h}"
readonly support_dir="$HOME/Library/Application Support/Print Booklet"
readonly service_parent="$HOME/Library/Services"
readonly service_dir="$service_parent/Print as Booklet.workflow"

export PATH="/opt/homebrew/bin:/usr/local/bin:/Library/TeX/texbin:/usr/bin:/bin:/usr/sbin:/sbin"

if ! command -v pdfbook2 >/dev/null 2>&1; then
  print -u2 "Missing pdfbook2. Install it first with: brew install pdfbook2"
  exit 69
fi

python_source="$(command -v python3 || true)"
if [[ -z "$python_source" ]]; then
  print -u2 "Missing Python 3. Install it first with: brew install python"
  exit 69
fi

/bin/mkdir -p "$support_dir" "$service_parent"
"$python_source" -m venv "$support_dir/.venv"
"$support_dir/.venv/bin/python3" -m pip install --upgrade pip
"$support_dir/.venv/bin/python3" -m pip install -r "$repo_dir/requirements.txt"

/usr/bin/install -m 755 "$repo_dir/scripts/print-booklet.zsh" "$support_dir/print-booklet.zsh"
/usr/bin/install -m 755 "$repo_dir/scripts/add-page-numbers.py" "$support_dir/add-page-numbers.py"

if [[ ! -f "$support_dir/config.zsh" ]]; then
  /bin/cp "$repo_dir/config.example.zsh" "$support_dir/config.zsh"
fi

/usr/bin/ditto "$repo_dir/workflow/Print as Booklet.workflow" "$service_dir"
/System/Library/CoreServices/pbs -flush
/System/Library/CoreServices/pbs -update

print "Installed: Print as Booklet"
print "Use Finder: right-click a PDF, then choose Quick Actions > Print as Booklet."
