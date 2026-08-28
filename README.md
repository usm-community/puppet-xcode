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
* Writes a state stamp, `/var/db/puppet_xcode_state` by default, plus
  `/var/db/puppet_xcode_clt_state` when the Command Line Tools are managed.
* Optionally runs `xcode-select -s` and installs the Command Line Tools
  through `softwareupdate`.

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

**The Command Line Tools**, when managed, follow a stamp of their own, keyed on
the macOS build alone. A macOS update sometimes deletes
`/Library/Developer/CommandLineTools` outright, and sometimes leaves it in place
while its SDKs stay those of the previous OS — the second case is silent, and
only the stamp catches it. They are keyed on the OS alone because the standalone
tools are independent of `Xcode.app`: an Xcode update never invalidates them.

Two details worth knowing if you modify this module:

* The stamp is written **after** the exec succeeds (`Exec -> File`), never
  through a notify (`File ~> Exec`). With a notify, Puppet would record the new
  state before running the command, and a failure would never be retried.
* The Xcode version is read from the bundle's `version.plist`, not from
  `xcodebuild -version`. That command fails precisely while the licence is
  unaccepted, which is the moment the version is needed.
* Puppet ANDs `creates` with `unless`, so the Command Line Tools exec cannot use
  both: a `creates` on `clang` would veto the stamp and stale tools would never
  be replaced. The two conditions are ORed inside a single shell test instead.

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
* The parent directories of `state_stamp` and `command_line_tools_stamp` must
  already exist. The default, `/var/db`, always does.
* Command Line Tools staleness is inferred from the macOS build, not from the
  installed package version: `pkgutil` receipts carry no value that can be
  compared against the running OS. As a consequence, the first Puppet run on a
  host that has no stamp yet reinstalls the tools once, even if they were
  already current — there is no way to tell "current" from "stale" without a
  previous reference. On hosts you know to be up to date, that one-off install
  can be skipped by seeding the stamp before the first Puppet run:

  ```bash
  sudo sh -c 'sw_vers -buildVersion > /var/db/puppet_xcode_clt_state'
  ```

  Note that this asserts the installed tools match the running OS; it does not
  check it. On a host whose tools were in fact stale, this silences the
  reinstall until the next macOS update.

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

Simulate a macOS update that left stale Command Line Tools behind, rather than
removing them — the case a `creates` guard alone would let through:

```bash
echo "FAUXBUILD" | sudo tee /var/db/puppet_xcode_clt_state
sudo puppet apply … -e "class { 'xcode': manage_command_line_tools => true }"
# must reinstall even though /Library/Developer/CommandLineTools still exists
```

Licence scenario:

```bash
sudo defaults delete /Library/Preferences/com.apple.dt.Xcode IDELastGMLicenseAgreedTo
xcodebuild -version          # exits 69
sudo puppet apply … -e 'include xcode'
xcodebuild -version          # exits 0
```
