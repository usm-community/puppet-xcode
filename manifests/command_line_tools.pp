# @summary Install or update the Xcode Command Line Tools without user interaction.
#
# @api private
class xcode::command_line_tools {
  assert_private()

  $script = '/var/tmp/puppet_xcode_install_command_line_tools.sh'
  $clang  = '/Library/Developer/CommandLineTools/usr/bin/clang'

  # --no-scan reuses the result of the macOS update daemon's own periodic scan,
  # about a second against several for a round trip to Apple on every agent run.
  $list = $xcode::command_line_tools_full_scan ? {
    true    => '/usr/sbin/softwareupdate -l',
    default => '/usr/sbin/softwareupdate -l --no-scan',
  }

  file { $script:
    ensure => file,
    owner  => 'root',
    group  => 'wheel',
    mode   => '0700',
    source => 'puppet:///modules/xcode/install_command_line_tools.sh',
  }

  # `xcode-select --install` cannot be used here: it opens a GUI dialog and
  # would never complete under an unattended Puppet run.
  #
  # Ask softwareupdate what is on offer rather than inferring it from the OS
  # build. Apple ships Command Line Tools updates on their own cadence -- a
  # "Command Line Tools for Xcode 27.0" lands on hosts whose macOS build has
  # not moved at all -- so keying on the OS build silently misses them. The
  # first test covers the tools being absent outright, which an update check
  # alone would not report.
  exec { 'xcode_install_command_line_tools':
    onlyif    => "! test -x '${clang}' || ${list} 2>/dev/null | grep -q 'Command Line Tools'",
    command   => $script,
    provider  => shell,
    path      => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    logoutput => 'on_failure',
    timeout   => $xcode::command_line_tools_timeout,
    require   => File[$script],
  }
}
