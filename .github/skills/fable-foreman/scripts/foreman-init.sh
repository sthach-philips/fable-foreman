#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [--in-place] [--teardown] [branch]\n' "$0" >&2
  exit 2
}

teardown=false
in_place=false
branch_arg=
while [[ $# -gt 0 ]]; do
  case $1 in
    --in-place) in_place=true ;;
    --teardown) teardown=true ;;
    -*) usage ;;
    *)
      [[ -z "$branch_arg" ]] || usage
      branch_arg=$1
      ;;
  esac
  shift
done

current_root=$(git rev-parse --show-toplevel)
root=$(git -C "$current_root" worktree list --porcelain | awk '$1 == "worktree" { print $2; exit }')
repo=$(basename "$root")
current_branch=$(git -C "$current_root" branch --show-current)
branch=${branch_arg:-$current_branch}
[[ -n "$branch" ]] || { printf 'detached HEAD: pass a branch name\n' >&2; exit 1; }
feature=$(printf '%s' "$branch" | sed -E 's#[^A-Za-z0-9._-]+#-#g; s#^-+##; s#-+$##')
[[ -n "$feature" ]] || { printf 'branch does not produce a usable feature slug\n' >&2; exit 1; }

parent=$(dirname "$root")
worktree="$parent/$repo.worktrees/$feature"
store_root="$HOME/.foreman/$repo"
store="$store_root/$feature"
mode=worktree
workspace=$worktree

if $in_place; then
  mode=in_place
  workspace=$current_root
  resuming=false
  [[ -n "$current_branch" ]] || { printf 'in-place mode requires a named branch\n' >&2; exit 1; }
  [[ "$branch" == "$current_branch" ]] || {
    printf 'in-place branch %s does not match checked-out branch %s\n' "$branch" "$current_branch" >&2
    exit 1
  }
  if [[ -e "$workspace/.foreman" && ! -L "$workspace/.foreman" ]]; then
    printf '%s exists and is not a symlink\n' "$workspace/.foreman" >&2
    exit 1
  fi
  if [[ -L "$workspace/.foreman" && $(readlink "$workspace/.foreman") != "$store" ]]; then
    printf 'unexpected symlink target: %s\n' "$workspace/.foreman" >&2
    exit 1
  fi
  if [[ -L "$workspace/.foreman" && -f "$store/ledger.jsonl" && -d "$store/scratch" ]]; then
    resuming=true
  fi
  if ! $teardown && ! $resuming; then
    [[ -z $(git -C "$workspace" status --porcelain --untracked-files=all) ]] || {
      printf 'in-place mode requires a clean working tree\n' >&2
      exit 1
    }
  fi
fi

if $teardown; then
  if $in_place; then
    if [[ -L "$workspace/.foreman" ]]; then
      [[ $(readlink "$workspace/.foreman") == "$store" ]] || {
        printf 'refusing to remove unexpected symlink: %s\n' "$workspace/.foreman" >&2
        exit 1
      }
      rm "$workspace/.foreman"
    elif [[ -e "$workspace/.foreman" ]]; then
      printf '%s exists and is not a symlink\n' "$workspace/.foreman" >&2
      exit 1
    fi
    printf 'removed symlink: %s\nretained store: %s\n' "$workspace/.foreman" "$store"
    exit 0
  fi
  if [[ -d "$workspace" ]]; then
    git -C "$root" worktree remove "$workspace" || {
      printf 'worktree removal failed; resolve dirty files or locks, then retry once\n' >&2
      exit 1
    }
  fi
  git -C "$root" worktree prune
  printf 'removed worktree: %s\nretained store: %s\n' "$workspace" "$store"
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

if ! $in_place; then
  if [[ "$root" == "$workspace" ]]; then
    :
  elif [[ -d "$workspace" ]]; then
    registered=$(git -C "$root" worktree list --porcelain | awk -v target="$workspace" '$1 == "worktree" && $2 == target { found=1 } END { print found+0 }')
    [[ "$registered" == 1 ]] || { printf '%s exists but is not a registered worktree\n' "$workspace" >&2; exit 1; }
  else
    mkdir -p "$(dirname "$workspace")"
    checked_out=$(git -C "$root" worktree list --porcelain | awk -v ref="refs/heads/$branch" '$1 == "worktree" { path=$2 } $1 == "branch" && $2 == ref { print path }')
    if [[ -n "$checked_out" ]]; then
      printf 'branch %s is already checked out at %s; open that path or choose another branch\n' "$branch" "$checked_out" >&2
      exit 1
    elif git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$root" worktree add -q "$workspace" "$branch"
    else
      git -C "$root" worktree add -q -b "$branch" "$workspace" HEAD
    fi
  fi
fi

if [[ -L "$workspace/.foreman" ]]; then
  [[ $(readlink "$workspace/.foreman") == "$store" ]] || {
    printf 'unexpected symlink target: %s\n' "$workspace/.foreman" >&2
    exit 1
  }
elif [[ -e "$workspace/.foreman" ]]; then
  printf '%s exists and is not a symlink\n' "$workspace/.foreman" >&2
  exit 1
else
  ln -s "$store" "$workspace/.foreman"
fi

exclude=$(git -C "$workspace" rev-parse --git-path info/exclude)
grep -qxF '/.foreman' "$exclude" 2>/dev/null || printf '/.foreman\n' >> "$exclude"

printf 'mode: %s\nworkspace: %s\nstore: %s\nbranch: %s\nfeature: %s\n' "$mode" "$workspace" "$store" "$branch" "$feature"