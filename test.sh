#!/usr/bin/env bash
# Self-check: syntax, shellcheck (if installed), and the package-line parsing.
# Run before committing:  bash test.sh
cd "$(dirname "$0")" || exit 1
repo=$PWD
fail=0
check() { if "$@"; then echo "ok:   $*"; else echo "FAIL: $*"; fail=1; fi; }
not() { ! "$@"; }

for f in install.sh functions.sh test.sh; do check bash -n "$f"; done
command -v shellcheck > /dev/null && check shellcheck -x install.sh functions.sh test.sh

# install_packages with stubbed sudo/apt/curl: a plain name that contains "http" must go
# to apt-get (not curl), and "name url" must skip the download when name is installed.
tmp=$(mktemp -d)
mkdir "$tmp/bin"
for c in apt-get dpkg dpkg-deb; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$tmp" > "$tmp/bin/$c"; done
printf '#!/bin/sh\necho "curl $*" >> "%s/calls"\nexit 1\n' "$tmp" > "$tmp/bin/curl"
printf '#!/bin/sh\nwhile [ "${1#*=}" != "$1" ]; do shift; done\nexec "$@"\n' > "$tmp/bin/sudo"
printf '#!/bin/sh\n[ "$3" = bash ] && { printf "install ok installed"; exit 0; }\nexit 1\n' > "$tmp/bin/dpkg-query"
chmod +x "$tmp"/bin/*
printf 'httpie\nbash https://example.invalid/bash.deb\n' > "$tmp/list"
(cd "$tmp" && PATH="$tmp/bin:$PATH" bash -c 'source "$1/functions.sh"; install_packages list' _ "$repo" > /dev/null 2>&1)
check grep -q '^apt-get install -y httpie' "$tmp/calls"
check not grep -q '^curl' "$tmp/calls"

# backup_dotfile_conflicts: an existing file that the dotfiles repo tracks must be copied away before checkout -f
src=$tmp/src
git init -q "$src" && mkdir -p "$src/.config/x" && echo NEW > "$src/.config/x/conf"
git -C "$src" add -A && git -C "$src" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$tmp/home/.config/x" && git clone -q --bare "$src" "$tmp/home/.dotfiles"
echo OLD > "$tmp/home/.config/x/conf"
(cd "$tmp" && HOME="$tmp/home" bash -c 'source "$1/functions.sh"; dotfiles() { git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"; }; backup_dotfile_conflicts' _ "$repo" > /dev/null 2>&1)
check grep -qx OLD "$tmp"/home/.dotfiles-backup-*/.config/x/conf

rm -rf "$tmp"

exit $fail
