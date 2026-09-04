#!/usr/bin/env bash
set -euo pipefail

kind=${1:-}
name=${2:-}
parent=${3:-}

case "$kind" in
  file|directory_tar_v1) ;;
  *) echo "unsupported attachment kind" >&2; exit 2 ;;
esac

# Signed meshmsg offers already enforce portable component names. Keep this
# boundary defensive because the resulting value becomes a local path.
stem=${name%%.*}
upper_stem=${stem^^}
if [[ -z "$name" || "$name" == '.' || "$name" == '..' || "$name" == *'/'* || "$name" == *'\\'* \
    || "$name" =~ [[:cntrl:]] || "$name" =~ [\<\>:\"\|\?\*] || "$name" == *'.' || "$name" == *' ' \
    || "$upper_stem" =~ ^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$ ]]; then
  echo "unsafe attachment name" >&2
  exit 2
fi

if [[ -z "$parent" ]]; then
  if command -v xdg-user-dir >/dev/null 2>&1; then
    parent=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
  fi
  [[ -n "$parent" ]] || parent=${HOME:?}/Downloads
  parent=${parent%/}/Meshmsg
  mkdir -p -- "$parent"
fi

[[ "$parent" == /* ]] || { echo "destination folder must be absolute" >&2; exit 2; }
[[ "$parent" =~ [[:cntrl:]] ]] && { echo "destination folder contains a control character" >&2; exit 2; }
[[ -d "$parent" ]] || { echo "destination folder does not exist" >&2; exit 2; }

if [[ "$kind" == directory_tar_v1 ]]; then
  base=${name%.tar}
  [[ -n "$base" ]] || base=attachment
  extension=
else
  base=$name
  extension=
  if [[ "$name" == *.* && "$name" != .* ]]; then
    extension=.${name##*.}
    base=${name%.*}
  fi
fi

candidate=$parent/$base$extension
number=2
while [[ -e "$candidate" || -L "$candidate" ]]; do
  candidate=$parent/$base\ \($number\)$extension
  ((number += 1))
done

printf '%s\n' "$candidate"
