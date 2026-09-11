# Changelog

All notable changes to this project will be documented in this file.

## Release 1.0.0

First release.

**Features**

* Structured `xcode` fact reporting the active developer directory, the Xcode
  bundle in use, its version and build, whether the licence has been accepted,
  and whether the Command Line Tools are installed.
* `xcodebuild -license accept`, driven by the real state of the system:
  `xcodebuild -version` exits 69 until the licence is accepted, so no
  undocumented plist key is relied upon.
* `xcodebuild -runFirstLaunch` after a macOS or Xcode update, tracked by a state
  stamp keyed on both the macOS build and the Xcode version, so an Xcode update
  on an unchanged OS is picked up as well.
* Optional headless install and update of the Command Line Tools, triggered by
  asking `softwareupdate` what is on offer. `xcode-select --install` is not
  used: it opens a GUI dialog that never completes under an unattended run.
* Optional management of the active developer directory via `xcode-select -s`.
* Runs unchanged on Intel and Apple Silicon. Paths are resolved at run time
  (`xcode-select -p`, a glob on `/Applications/Xcode*.app`) rather than
  hardcoded, so hosts carrying several Xcode versions keep working.

**Known Issues**

* Does not install `Xcode.app`: the bundle is several gigabytes and requires an
  Apple account, so it is expected to be delivered by Jamf/VPP or manually. On a
  host without Xcode the module logs a notice and does nothing, unless
  `fail_if_absent` is set.
* Requires root: `xcodebuild -license accept` writes to a system-wide preference
  domain.
* Command Line Tools updates are detected through `softwareupdate`, so a host
  that cannot reach Apple's update servers will not see them.
* No automated acceptance tests: the licence and first-launch behaviour cannot
  be reproduced in the Linux containers voxpupuli-acceptance provisions. The
  manual scenarios are documented in the README.
