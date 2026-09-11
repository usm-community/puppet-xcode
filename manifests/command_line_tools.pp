# @summary Install or update the Xcode Command Line Tools without user interaction.
#
# @api private
class xcode::command_line_tools {
  assert_private()

  $script = '/var/tmp/puppet_xcode_install_command_line_tools.sh'
  $check  = '/var/tmp/puppet_xcode_check_command_line_tools.sh'

  $check_command = $xcode::command_line_tools_full_scan ? {
    true    => "${check} --full-scan",
    default => $check,
  }

  file { $script:
    ensure => file,
    owner  => 'root',
    group  => 'wheel',
    mode   => '0700',
    source => 'puppet:///modules/xcode/install_command_line_tools.sh',
  }

  file { $check:
    ensure => file,
    owner  => 'root',
    group  => 'wheel',
    mode   => '0700',
    source => 'puppet:///modules/xcode/check_command_line_tools.sh',
  }

  # `xcode-select --install` cannot be used here: it opens a GUI dialog and
  # would never complete under an unattended Puppet run.
  #
  # The check compares the installed package version against the newest one on
  # offer. Merely asking whether softwareupdate lists "Command Line Tools" is
  # not enough: with the install-on-demand sentinel in place it advertises
  # every version Apple publishes, older ones included, so such a test stays
  # true forever and reinstalls on every agent run.
  exec { 'xcode_install_command_line_tools':
    onlyif    => $check_command,
    command   => $script,
    path      => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    logoutput => 'on_failure',
    timeout   => $xcode::command_line_tools_timeout,
    require   => [File[$script], File[$check]],
  }
}
