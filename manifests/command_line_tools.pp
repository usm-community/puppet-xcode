# @summary Install the Xcode Command Line Tools without user interaction.
#
# @api private
class xcode::command_line_tools {
  assert_private()

  $script   = '/var/tmp/puppet_xcode_install_command_line_tools.sh'
  $stamp    = $xcode::command_line_tools_stamp
  $clang    = '/Library/Developer/CommandLineTools/usr/bin/clang'
  $os_build = $facts['os']['macosx']['build']

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
  # Reinstall when the tools are missing *or* when the OS build has moved on.
  # A macOS update sometimes deletes /Library/Developer/CommandLineTools, in
  # which case the first test catches it; but when it leaves the directory in
  # place the tools are silently stale -- their SDKs are still the previous
  # OS's -- and only the stamp notices. Puppet ANDs `creates` with `unless`,
  # so the two conditions have to be ORed inside a single shell test rather
  # than expressed as separate attributes.
  #
  # Unlike the Xcode stamp this one is keyed on the OS build alone: the
  # standalone Command Line Tools are independent of Xcode.app, so an Xcode
  # update never invalidates them.
  exec { 'xcode_install_command_line_tools':
    command   => $script,
    unless    => "test -x '${clang}' && grep -qxF '${os_build}' '${stamp}'",
    provider  => shell,
    path      => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    logoutput => 'on_failure',
    timeout   => $xcode::command_line_tools_timeout,
    require   => File[$script],
  }

  # Recorded only once the install succeeded, so a failure is retried on the
  # next run instead of being masked by a stamp written ahead of time.
  file { $stamp:
    ensure  => file,
    owner   => 'root',
    group   => 'wheel',
    mode    => '0644',
    content => "${os_build}\n",
  }

  Exec['xcode_install_command_line_tools'] -> File[$stamp]
}
