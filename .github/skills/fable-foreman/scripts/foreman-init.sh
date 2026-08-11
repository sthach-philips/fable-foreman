#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [--teardown] [branch]\n' "$0" >&2
  exit 2
}

teardown=false
if [[ ${1:-} == "--teardown" ]]; then
  teardown=true
  shift
fi
[[ $# -le 1 ]] || usage

current_root=$(git rev-parse --show-toplevel)
root=$(git -C "$current_root" worktree list --porcelain | awk '$1 == "worktree" { print $2; exit }')
repo=$(basename "$root")
branch=${1:-$(git branch --show-current)}
[[ -n "$branch" ]] || { printf 'detached HEAD: pass a branch name\n' >&2; exit 1; }
feature=$(printf '%s' "$branch" | sed -E 's#[^A-Za-z0-9._-]+#-#g; s#^-+##; s#-+$##')
[[ -n "$feature" ]] || { printf 'branch does not produce a usable feature slug\n' >&2; exit 1; }

parent=$(dirname "$root")
worktree="$parent/$repo.worktrees/$feature"
store_root="$HOME/.foreman/$repo"
store="$store_root/$feature"

if $teardown; then
  if [[ -d "$worktree" ]]; then
    git -C "$root" worktree remove "$worktree" || {
      printf 'worktree removal failed; resolve dirty files or locks, then retry once\n' >&2
      exit 1
    }
  fi
  git -C "$root" worktree prune
  printf 'removed worktree: %s\nretained store: %s\n' "$worktree" "$store"
  exit 0
fi

mkdir -p "$store_root"
if [[ ! -d "$store_root/.git" ]]; then
  git -C "$store_root" init -q
fi

repo_marker="$store_root/.repo-root"
if [[ -f "$repo_marker" ]]; then
  recorded_root=$(cat "$repo_marker")
  if [[ "$recorded_root" != "$root" ]]; then
    printf 'refusing basename collision: %s belongs to %s\n' "$store_root" "$recorded_root" >&2
    exit 1
  fi
else
  printf '%s\n' "$root" > "$repo_marker"
fi
mkdir -p "$store/scratch"
touch "$store/ledger.jsonl"

if [[ "$root" == "$worktree" ]]; then
  :
elif [[ -d "$worktree" ]]; then
  registered=$(git -C "$root" worktree list --porcelain | awk -v target="$worktree" '$1 == "worktree" && $2 == target { found=1 } END { print found+0 }')
  [[ "$registered" == 1 ]] || { printf '%s exists but is not a registered worktree\n' "$worktree" >&2; exit 1; }
else
  mkdir -p "$(dirname "$worktree")"
  checked_out=$(git -C "$root" worktree list --porcelain | awk -v ref="refs/heads/$branch" '$1 == "worktree" { path=$2 } $1 == "branch" && $2 == ref { print path }')
  if [[ -n "$checked_out" ]]; then
    printf 'branch %s is already checked out at %s; open that path or choose another branch\n' "$branch" "$checked_out" >&2
    exit 1
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root" worktree add -q "$worktree" "$branch"
  else
    git -C "$root" worktree add -q -b "$branch" "$worktree" HEAD
  fi
fi

if [[ -e "$worktree/.foreman" && ! -L "$worktree/.foreman" ]]; then
  printf '%s exists and is not a symlink\n' "$worktree/.foreman" >&2
  exit 1
fi
ln -sfn "$store" "$worktree/.foreman"

exclude=$(git -C "$worktree" rev-parse --git-path info/exclude)
grep -qxF '/.foreman' "$exclude" 2>/dev/null || printf '/.foreman\n' >> "$exclude"

printf 'worktree: %s\nstore: %s\nbranch: %s\nfeature: %s\n' "$worktree" "$store" "$branch" "$feature"