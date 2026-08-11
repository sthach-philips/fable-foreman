#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
script="$root/.github/skills/fable-foreman/scripts/foreman-init.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local path=$1
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name Test
  git -C "$path" config user.email test@example.test
  printf 'x\n' > "$path/file.txt"
  git -C "$path" add file.txt
  git -C "$path" commit -qm init
}

expect_fail() {
  if "$@" >/dev/null 2>&1; then
    printf 'expected failure: %q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

make_repo "$tmp/default/demo"
first=$(cd "$tmp/default/demo" && HOME="$tmp/home-default" "$script" feature/default)
worktree="$tmp/default/demo.worktrees/feature-default"
store="$tmp/home-default/.foreman/demo/feature-default"
[[ "$first" == *'mode: worktree'* && -L "$worktree/.foreman" ]]
[[ $(readlink "$worktree/.foreman") == "$store" ]]
[[ "$first" == "$(cd "$worktree" && HOME="$tmp/home-default" "$script")" ]]
(cd "$tmp/default/demo" && HOME="$tmp/home-default" "$script" --teardown feature/default >/dev/null)
[[ ! -d "$worktree" && -d "$store" ]]

make_repo "$tmp/in-place/demo"
git -C "$tmp/in-place/demo" switch -qc feature/current
worktree_count=$(git -C "$tmp/in-place/demo" worktree list --porcelain | grep -c '^worktree ')
first=$(cd "$tmp/in-place/demo" && HOME="$tmp/home-in-place" "$script" --in-place)
store="$tmp/home-in-place/.foreman/demo/feature-current"
[[ "$first" == *'mode: in_place'* && -L "$tmp/in-place/demo/.foreman" ]]
[[ $(readlink "$tmp/in-place/demo/.foreman") == "$store" ]]
[[ $(git -C "$tmp/in-place/demo" worktree list --porcelain | grep -c '^worktree ') -eq "$worktree_count" ]]
[[ -z $(git -C "$tmp/in-place/demo" status --porcelain) ]]
[[ "$first" == "$(cd "$tmp/in-place/demo" && HOME="$tmp/home-in-place" "$script" --in-place)" ]]
printf 'user change\n' >> "$tmp/in-place/demo/file.txt"
[[ "$first" == "$(cd "$tmp/in-place/demo" && HOME="$tmp/home-in-place" "$script" --in-place)" ]]
(cd "$tmp/in-place/demo" && HOME="$tmp/home-in-place" "$script" --in-place --teardown >/dev/null)
[[ ! -e "$tmp/in-place/demo/.foreman" && -d "$store" ]]
grep -q 'user change' "$tmp/in-place/demo/file.txt"

make_repo "$tmp/dirty/demo"
printf 'dirty\n' >> "$tmp/dirty/demo/file.txt"
expect_fail env HOME="$tmp/home-dirty" "$script" --in-place
[[ ! -e "$tmp/home-dirty/.foreman" ]]

make_repo "$tmp/fake-resume/demo"
git -C "$tmp/fake-resume/demo" switch -qc feature/current
mkdir -p "$tmp/home-fake/.foreman/demo"
ln -s "$tmp/home-fake/.foreman/demo/feature-current" "$tmp/fake-resume/demo/.foreman"
printf 'dirty\n' >> "$tmp/fake-resume/demo/file.txt"
expect_fail env HOME="$tmp/home-fake" "$script" --in-place
[[ ! -e "$tmp/home-fake/.foreman/demo/feature-current" ]]

make_repo "$tmp/detached/demo"
git -C "$tmp/detached/demo" checkout -q --detach
expect_fail env HOME="$tmp/home-detached" "$script" --in-place main

make_repo "$tmp/mismatch/demo"
expect_fail env HOME="$tmp/home-mismatch" "$script" --in-place other-branch

make_repo "$tmp/nonlink/demo"
mkdir "$tmp/nonlink/demo/.foreman"
expect_fail env HOME="$tmp/home-nonlink" "$script" --in-place

make_repo "$tmp/wronglink/demo"
ln -s /tmp/not-the-foreman-store "$tmp/wronglink/demo/.foreman"
expect_fail env HOME="$tmp/home-wronglink" "$script" --in-place
[[ -L "$tmp/wronglink/demo/.foreman" ]]

printf 'foreman-init tests passed\n'