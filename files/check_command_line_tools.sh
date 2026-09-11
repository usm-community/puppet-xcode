#!/bin/bash
#
# Managed by Puppet -- module: xcode
#
# Exits 0 when the Command Line Tools need installing or updating, 1 otherwise.
# Used as the `onlyif` of the install exec.
#
# Comparing versions is what makes this safe. With the install-on-demand
# sentinel in place, softwareupdate advertises *every* Command Line Tools
# package Apple publishes -- 26.5, 26.6 and 27.0 all at once -- not just newer
# ones. Matching the product name alone therefore stays true forever and the
# install runs on every single agent run.
set -uo pipefail

clang='/Library/Developer/CommandLineTools/usr/bin/clang'
pkg='com.apple.pkg.CLTools_Executables'

list=(/usr/sbin/softwareupdate -l --no-scan)
if [ "${1:-}" = '--full-scan' ]; then
  list=(/usr/sbin/softwareupdate -l)
fi

# Absent outright: nothing to compare against, install.
[ -x "$clang" ] || exit 0

installed=$(/usr/sbin/pkgutil --pkg-info="$pkg" 2>/dev/null \
  | awk '/^version:/{print $2}' | cut -d. -f1,2)
[ -n "$installed" ] || exit 0

latest=$("${list[@]}" 2>/dev/null \
  | sed -n 's/.*Command Line Tools for Xcode \([0-9][0-9.]*\)-.*/\1/p' \
  | sort -V | tail -n 1)

# Nothing on offer at all: up to date as far as we can tell.
[ -n "$latest" ] || exit 1

newest=$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -n 1)
[ "$newest" != "$installed" ] && exit 0
exit 1
