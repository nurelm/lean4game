# repo_root.sh - resolve the repository root.
# Usage:  . "$(dirname "$0")/lib/repo_root.sh"; cd "$(repo_root)"
#
# Prefers git (works from any subdirectory), falls back to this file's
# location (scripts/lib/..) so it also works outside a git checkout.

repo_root() {
    local dir
    if dir="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$dir" ]; then
        printf '%s\n' "$dir"
        return 0
    fi
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    printf '%s\n' "$dir"
}