#!/usr/bin/env bash
# Lint every shell script in the repo, hooks included. Run: scripts/shellcheck.sh
# Uses shellcheck when installed, otherwise its Docker image.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts=()
while IFS= read -r -d '' path; do
  [[ -f $path ]] || continue
  if [[ $path == *.sh ]] || head -n1 "$path" | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)'; then
    scripts+=("$path")
  fi
done < <(git ls-files -z --cached --others --exclude-standard)

if command -v shellcheck >/dev/null; then
  shellcheck "${scripts[@]}"
else
  docker run --rm -e LANG=C.UTF-8 -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable "${scripts[@]}"
fi
printf 'shellcheck: %d scripts clean\n' "${#scripts[@]}"
