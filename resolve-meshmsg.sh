#!/usr/bin/env bash
set -euo pipefail

candidates=(
  "$HOME/.local/bin/meshmsg"
  "$HOME/.cargo/bin/meshmsg"
)
if resolved="$(command -v meshmsg 2>/dev/null)"; then
  candidates+=("$resolved")
fi

seen=''
for candidate in "${candidates[@]}"; do
  [[ -x "$candidate" ]] || continue
  canonical="$(readlink -f "$candidate")"
  [[ ":$seen:" == *":$canonical:"* ]] && continue
  seen="${seen:+$seen:}$canonical"
  # Attachment downloads carry reusable plaintext capabilities. Require the
  # v0.1.9 command shape so the plugin can keep offers out of argv.
  help_output="$("$canonical" --help 2>&1 || true)"
  download_help="$("$canonical" download --help 2>&1 || true)"
  if grep -qE '^  daemon[[:space:]]' <<<"$help_output" \
    && grep -qE '^  init[[:space:]]' <<<"$help_output" \
    && grep -qE '^  join[[:space:]]' <<<"$help_output" \
    && grep -qE '^  invite[[:space:]]' <<<"$help_output" \
    && grep -qE '^  send[[:space:]]' <<<"$help_output" \
    && grep -qE '^  listen[[:space:]]' <<<"$help_output" \
    && grep -qE '^  status[[:space:]]' <<<"$help_output" \
    && grep -qE '^  stop[[:space:]]' <<<"$help_output" \
    && grep -qE '^  share[[:space:]]' <<<"$help_output" \
    && grep -qE '^  download[[:space:]]' <<<"$help_output" \
    && grep -q -- '--offer-stdin' <<<"$download_help"; then
    printf '%s\n' "$canonical"
    exit 0
  fi
done

echo "meshmsg v0.1.9 or newer with attachment stdin support was not found" >&2
exit 127
