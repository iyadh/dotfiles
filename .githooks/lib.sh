# Shared by the hooks in this directory. Keep in sync with docs/agents/git-workflow.md.
# Written for macOS's bash 3.2: no associative arrays, no ${var,,}.

PROTECTED_BRANCH=master

# type:emoji pairs. Emoji are stored without the U+FE0F variation selector,
# which the commit-msg hook strips before comparing.
COMMIT_TYPES="feat:✨ fix:🐛 docs:📝 style:🎨 refactor:♻ perf:⚡ test:✅ build:📦 ci:👷 chore:🔧 revert:⏪"
BREAKING_EMOJI="💥"
TYPE_PATTERN="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

BRANCH_RE="^(${TYPE_PATTERN})/([0-9]+-)?[a-z0-9]+(-[a-z0-9]+)*$"

emoji_for() {
  local pair
  for pair in $COMMIT_TYPES; do
    if [[ ${pair%%:*} == "$1" ]]; then
      printf '%s' "${pair#*:}"
      return
    fi
  done
}

if [ -t 2 ]; then
  RED=$'\033[31m' DIM=$'\033[2m' RESET=$'\033[0m'
else
  RED='' DIM='' RESET=''
fi

err() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; }
hint() { printf '%s  %s%s\n' "$DIM" "$*" "$RESET" >&2; }
