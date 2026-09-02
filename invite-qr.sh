#!/usr/bin/env bash
set -euo pipefail

meshmsg_bin="${1:-}"
if [[ -z "$meshmsg_bin" || ! -x "$meshmsg_bin" ]]; then
  echo "meshmsg is not available" >&2
  exit 127
fi
command -v qrencode >/dev/null 2>&1 || {
  echo "qrencode is required to generate invite QR codes" >&2
  exit 127
}

# Keep the invite capability out of argv, temporary files, and this script's
# output. Only the derived 0/1 QR matrix is returned to the shell plugin.
ascii="$({
  "$meshmsg_bin" --json invite |
    python3 -c 'import json, sys; value=json.load(sys.stdin); token=value.get("token", ""); assert token; sys.stdout.write(token)'
} | qrencode --type ASCII --margin 4 --output -)"

while IFS= read -r line; do
  row=""
  for ((column = 0; column < ${#line}; column += 2)); do
    [[ ${line:column:2} == *#* ]] && row+=1 || row+=0
  done
  printf '%s\n' "$row"
done <<<"$ascii"
