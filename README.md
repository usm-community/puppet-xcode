# puppet-xcode

Detect Xcode on macOS and keep its licence and components in sync after a macOS
or Xcode update.

## Table of Contents

1. [Description](#description)
1. [Setup](#setup)
1. [Usage](#usage)
1. [How it decides to act](#how-it-decides-to-act)
1. [Reference](#reference)
1. [Limitations](#limitations)
1. [Development](#development)

## Description

After a macOS update, `xcodebuild` routinely stops working: the Xcode licence
has to be re-accepted as root, and the bundled components have to be
reinstalled. Until that is done every build fails with:

```
You have not agreed to the Xcode license agreements.
```

This module detects the state of the Xcode toolchain through the `xcode` fact
and, when Xcode is present, brings it back into compliance without any user
interaction:

* `xcodebuild -license accept`
* `xcodebuild -runFirstLaunch`
* optionally, a headless install of the Command Line Tools.

It runs unchanged on Intel and Apple Silicon. `Xcode.app` is a universal binary
and `xcodebuild` behaves identically on both, so there is no architecture
switch; portability comes from resolving paths at run time (`xcode-select -p`,
a glob on `/Applications/Xcode*.app`) instead of hardcoding them, which is what
would otherwise break hosts carrying several Xcode versions.

## Setup

### What puppet-xcode affects

* Accepts the Xcode licence, which writes to
  `/Library/Preferences/com.apple.dt.Xcode.plist`.
* Runs the Xcode first-launch component install, which installs packages.
* Writes a state stamp, `/var/db/puppet_xcode_state` by default.
* Optionally runs `xcode-select -s`, and installs or updates the Command Line
  Tools through `softwareupdate`.

### Setup requirements

* macOS, with Puppet running as **root**: `xcodebuild -license accept` writes to
  a system-wide preference domain.
* `puppetlabs/stdlib`.
* `Xcode.app` must already be installed. This module does not download it: the
  bundle is several gigabytes and requires an Apple account, so it is expected
  to be delivered by Jamf/VPP or manually. On a host without Xcode the module
  logs a notice and does nothing, unless `fail_if_absent` is set.

## Usage

Accept the licence and replay the first-launch install after an update:

```puppet
include xcode
```

Also install the Command Line Tools and point `xcode-select` at the bundle:

```puppet
class { 'xcode':
  manage_command_line_tools => true,
  manage_developer_dir      => true,
}
```

Pin a specific bundle on a host carrying several Xcode versions:

```puppet
class { 'xcode':
  app_path => '/Applications/Xcode-16.2.app',
}
```

## How it decides to act

Two independent mechanisms, because they answer two different questions.

**The licence** is driven by the real state of the system. `xcodebuild -version`
exits 69 for as long as the licence has not been accepted, so it is used
directly as the `unless` test. Nothing here depends on the undocumented plist
keys Apple uses to record the agreement, which is why an Xcode update that ships
a new licence ID is picked up automatically, while a minor update that keeps the
same licence ID correctly triggers nothing.

**The component install** is driven by a state stamp holding both the macOS
build and the Xcode version, for example `25G83-16.2-16C5032a`. Either dimension
changing replays `xcodebuild -runFirstLaunch`. Keying the stamp on the OS build
alone would miss "Xcode updated, macOS unchanged" — which is exactly when the
newly bundled components need installing.

**The Command Line Tools**, when managed, keep no state file. Their trigger is
`files/check_command_line_tools.sh`, which compares the installed package
version against the newest one `softwareupdate` offers, and installs when the
tools are missing or genuinely out of date.

The version comparison is the whole point. Asking merely whether softwareupdate
lists "Command Line Tools" does not work, and the module got this wrong twice:

* Keying on the macOS build misses updates entirely. Apple ships Command Line
  Tools updates on their own cadence — "Command Line Tools for Xcode 27.0" lands
  on a host whose macOS build has not moved — so a stamp keyed on the OS build
  reports "nothing to do".
* Matching the product name reinstalls on *every* run. While the
  install-on-demand sentinel is in place, softwareupdate advertises every
  Command Line Tools package Apple publishes — 26.5, 26.6 and 27.0 at once — not
  just newer ones, so the test never goes false.

`--no-scan` reuses the macOS update daemon's own periodic scan, roughly a second
against several for a round trip to Apple on every agent run. Set
`command_line_tools_full_scan` for hosts that are rarely up, or where automatic
checks are disabled, so that cache cannot be relied upon. The install script
drops the sentinel before refreshing the catalogue, so a cached scan never
replays the install-on-demand listing back to the next run.

Two details worth knowing if you modify this module:

* The stamp is written **after** the exec succeeds (`Exec -> File`), never
  through a notify (`File ~> Exec`). With a notify, Puppet would record the new
  state before running the command, and a failure would never be retried.
* The Xcode version is read from the bundle's `version.plist`, not from
  `xcodebuild -version`. That command fails precisely while the licence is
  unaccepted, which is the moment the version is needed.

## Reference

See [REFERENCE.md](REFERENCE.md), generated with `puppet-strings`.

The module also ships a structured fact, `xcode`:

```
$ facter -p xcode
{
  app_path => "/Applications/Xcode.app",
  build => "16C5032a",
  command_line_tools => true,
  developer_dir => "/Applications/Xcode.app/Contents/Developer",
  installed => true,
  license_accepted => true,
  type => "xcode",
  version => "16.2"
}
```

`license_accepted` is left unset when Xcode is not the active toolchain, so that
"licence refused" is never confused with "Xcode absent".

Note that Facter reports an unresolved key inside a structured fact as an empty
string rather than as `undef`; manifests consuming this fact must match
`String[1]` rather than test for `undef`.

## Limitations

* macOS only; the class fails on any other OS family.
* Does not install `Xcode.app` (see [Setup requirements](#setup-requirements)).
* Requires root.
* Rosetta 2 is out of scope. It is unrelated to licence handling, and Apple has
  announced its progressive removal after macOS 27.
* The parent directory of `state_stamp` must already exist. The default,
  `/var/db`, always does.
* Command Line Tools updates are detected through `softwareupdate`, so a host
  that cannot reach Apple's update servers will not see them.

## Development

```bash
bundle install
bundle exec rake validate   # syntax of manifests, metadata and Ruby
bundle exec rake lint       # puppet-lint
bundle exec rubocop         # Ruby style
bundle exec rake spec       # rspec-puppet and fact unit tests
```

Automated acceptance testing is not provided: the licence and first-launch
behaviour cannot be reproduced in the Linux containers voxpupuli-acceptance
provisions. Verify on a real Mac instead — ideally one Intel and one Apple
Silicon.

```bash
bundle exec rake fixtures:prep
sudo puppet apply --modulepath spec/fixtures/modules --noop -e 'include xcode'
sudo puppet apply --modulepath spec/fixtures/modules       -e 'include xcode'
sudo puppet apply --modulepath spec/fixtures/modules       -e 'include xcode'  # 2nd run: no change
```

Simulate a macOS update without reinstalling macOS:

```bash
echo "FAUXBUILD-0.0-0" | sudo tee /var/db/puppet_xcode_state
sudo puppet apply … -e 'include xcode'   # replays -runFirstLaunch
sudo puppet apply … -e 'include xcode'   # idempotent
```

Simulate an Xcode update at constant macOS build — the case a stamp keyed on the
OS alone would let through:

```bash
printf '%s-0.0-0\n' "$(sw_vers -buildVersion)" | sudo tee /var/db/puppet_xcode_state
sudo puppet apply … -e 'include xcode'   # must still replay -runFirstLaunch
sudo puppet apply … -e 'include xcode'   # idempotent
```

Check the Command Line Tools trigger against what Apple is actually offering:

```bash
softwareupdate -l | grep 'Command Line Tools'   # is an update on offer?
sudo puppet apply … -e "class { 'xcode': manage_command_line_tools => true }"
```

Licence scenario:

```bash
sudo defaults delete /Library/Preferences/com.apple.dt.Xcode IDELastGMLicenseAgreedTo
xcodebuild -version          # exits 69
sudo puppet apply … -e 'include xcode'
xcodebuild -version          # exits 0
```
