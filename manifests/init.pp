# @summary Detect Xcode on macOS and keep its licence and components in sync.
#
# Detects the installed Xcode toolchain through the `xcode` fact and, when Xcode
# is present, accepts the licence non-interactively and replays the first-launch
# component install after a macOS or Xcode update.
#
# This module deliberately does not install `Xcode.app` itself: the bundle is
# several gigabytes and requires an Apple account, so it is expected to be
# delivered by Jamf/VPP or manually beforehand.
#
# It works unchanged on Intel and Apple Silicon. `Xcode.app` is a universal
# binary and `xcodebuild` behaves identically on both, so no architecture switch
# is needed; portability instead comes from resolving paths at runtime
# (`xcode-select -p`, glob on `/Applications/Xcode*.app`) rather than hardcoding
# them, which is what would break hosts carrying several Xcode versions.
#
# @param manage_license
#   Whether to run `xcodebuild -license accept` when the licence is not accepted.
# @param manage_first_launch
#   Whether to run `xcodebuild -runFirstLaunch` after a macOS or Xcode update.
# @param manage_command_line_tools
#   Whether to install the Xcode Command Line Tools when they are missing.
# @param command_line_tools_adopt_existing
#   On the first run, when Command Line Tools are already present but no stamp
#   exists yet, record the current OS build instead of reinstalling them.
#   Set this on fleets where the tools are a prerequisite of enrolling the
#   Puppet agent, so they are known to be current the first time Puppet runs.
#   It is a declaration of trust, not a check: on a host whose tools were in
#   fact already stale, the reinstall is deferred to the next macOS update.
#   Defaults to false, which reinstalls once and is the safer assumption when
#   nothing is known about how the host was provisioned.
# @param manage_developer_dir
#   Whether to point `xcode-select` at the managed Xcode bundle when it currently
#   points elsewhere, for instance at the Command Line Tools.
# @param app_path
#   Pin a specific Xcode bundle. Defaults to the one resolved by the `xcode` fact.
# @param state_stamp
#   File recording the OS build and Xcode version the components were last
#   provisioned for. Its parent directory must already exist.
# @param command_line_tools_stamp
#   File recording the OS build the Command Line Tools were last installed for,
#   so that a macOS update reinstalls the matching version even when it leaves
#   the previous tools in place. Its parent directory must already exist.
# @param fail_if_absent
#   Fail the catalog when Xcode is not installed, instead of skipping quietly.
# @param license_timeout
#   Timeout in seconds for `xcodebuild -license accept`.
# @param first_launch_timeout
#   Timeout in seconds for `xcodebuild -runFirstLaunch`. It installs packages and
#   can run for several minutes, so Puppet's 300 second default is too short.
# @param command_line_tools_timeout
#   Timeout in seconds for the Command Line Tools install.
#
# @example Accept the licence and replay first launch after an update
#   include xcode
#
# @example Also install the Command Line Tools and select the Xcode bundle
#   class { 'xcode':
#     manage_command_line_tools => true,
#     manage_developer_dir      => true,
#   }
class xcode (
  Boolean $manage_license                        = true,
  Boolean $manage_first_launch                   = true,
  Boolean $manage_command_line_tools             = false,
  Boolean $command_line_tools_adopt_existing     = false,
  Boolean $manage_developer_dir                  = false,
  Optional[Stdlib::Absolutepath] $app_path       = undef,
  Stdlib::Absolutepath $state_stamp              = '/var/db/puppet_xcode_state',
  Stdlib::Absolutepath $command_line_tools_stamp = '/var/db/puppet_xcode_clt_state',
  Boolean $fail_if_absent                        = false,
  Integer[0] $license_timeout                    = 600,
  Integer[0] $first_launch_timeout               = 1800,
  Integer[0] $command_line_tools_timeout         = 1800,
) {
  unless $facts['os']['family'] == 'Darwin' {
    fail('The xcode module works on macOS only!')
  }

  $xcode_facts = $facts['xcode'] ? {
    undef   => {},
    default => $facts['xcode'],
  }

  # Facter turns a Ruby nil inside a structured fact into an empty string, not
  # into undef, so an absent bundle arrives here as ''. Matching String[1]
  # catches both forms; testing for undef alone would let the guard below pass
  # on a host that has no Xcode at all.
  $detected_app_path = $xcode_facts['app_path'] ? {
    String[1] => $xcode_facts['app_path'],
    default   => undef,
  }

  # An explicit pin wins; otherwise follow whatever the fact resolved.
  $real_app_path = $app_path ? {
    undef   => $detected_app_path,
    default => $app_path,
  }

  if $manage_command_line_tools {
    contain xcode::command_line_tools
  }

  if $real_app_path =~ Undef {
    if $fail_if_absent {
      fail('Xcode is not installed and xcode::fail_if_absent is true.')
    }

    notice('Xcode is not installed: licence and first-launch management skipped. This module does not install Xcode.app itself.')
  } else {
    contain xcode::license

    if $manage_command_line_tools {
      Class['xcode::command_line_tools'] -> Class['xcode::license']
    }
  }
}
