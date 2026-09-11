#!/bin/bash
#
# Managed by Puppet -- module: xcode
#
# Headless install of the Xcode Command Line Tools.
# `xcode-select --install` is unusable from Puppet: it opens a GUI dialog that
# nobody is there to click, so we drive softwareupdate directly instead.
set -euo pipefail

sentinel='/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress'

cleanup() {
  rm -f "${sentinel}"
}
trap cleanup EXIT

# This sentinel is what makes softwareupdate list the Command Line Tools
# products at all; without it the catalogue comes back empty.
touch "${sentinel}"

label=$(/usr/sbin/softwareupdate -l 2>/dev/null \
  | grep -E '^[[:space:]]*\*[[:space:]]*Label:[[:space:]]*Command Line Tools' \
  | sed -e 's/^[[:space:]]*\*[[:space:]]*Label:[[:space:]]*//' \
  | sort -V \
  | tail -n 1)

if [ -z "${label}" ]; then
  echo 'No Command Line Tools package offered by softwareupdate' >&2
  exit 1
fi

echo "Installing Command Line Tools: ${label}"
/usr/sbin/softwareupdate -i "${label}" --verbose

# Drop the sentinel *before* refreshing. While it is in place softwareupdate
# advertises the entire install-on-demand catalogue, so refreshing under it
# would cache every Command Line Tools version Apple publishes and leave the
# next run convinced an update is pending.
cleanup

# Refresh the catalogue so a later --no-scan check sees the post-install state
# rather than the offer we have just satisfied.
/usr/sbin/softwareupdate -l >/dev/null 2>&1 || true
