# @summary Accept the Xcode licence and replay the first-launch component install.
#
# @api private
class xcode::license {
  assert_private()

  $app_path      = $xcode::real_app_path
  $developer_dir = "${app_path}/Contents/Developer"
  $stamp         = $xcode::state_stamp
  $path          = ['/usr/bin', '/bin', '/usr/sbin', '/sbin']

  # Call the binary inside the bundle rather than the /usr/bin shim, so that the
  # licence is accepted for the bundle this class manages even when xcode-select
  # still points at the Command Line Tools.
  $xcodebuild  = "${developer_dir}/usr/bin/xcodebuild"
  $environment = ["DEVELOPER_DIR=${developer_dir}"]

  $xcode_facts = $facts['xcode'] ? {
    undef   => {},
    default => $facts['xcode'],
  }

  # String[1] rather than a test for undef: Facter reports an unresolved value
  # inside a structured fact as an empty string.
  $version = $xcode_facts['version'] ? {
    String[1] => $xcode_facts['version'],
    default   => 'unknown',
  }

  $build = $xcode_facts['build'] ? {
    String[1] => $xcode_facts['build'],
    default   => 'unknown',
  }

  # Keyed on the OS build *and* the Xcode version. A stamp holding only the OS
  # build would let "Xcode updated, OS unchanged" pass unnoticed, which is
  # exactly when the newly bundled components need installing.
  $state = "${facts['os']['macosx']['build']}-${version}-${build}"

  if $xcode::manage_developer_dir {
    # Compared at run time rather than against the fact, so that the catalog
    # keeps the same shape whether or not the host has converged yet.
    exec { 'xcode_select_switch':
      command   => "/usr/bin/xcode-select -s ${developer_dir}",
      unless    => "test \"\$(/usr/bin/xcode-select -p)\" = \"${developer_dir}\"",
      provider  => shell,
      path      => $path,
      logoutput => 'on_failure',
    }
  }

  if $xcode::manage_license {
    # `xcodebuild -version` exits 69 until the licence is accepted, which makes
    # it an idempotency test on the real state, with no reliance on the
    # undocumented plist keys Apple uses to record the agreement.
    exec { 'xcode_license_accept':
      command     => "${xcodebuild} -license accept",
      unless      => "${xcodebuild} -version",
      environment => $environment,
      path        => $path,
      logoutput   => 'on_failure',
      timeout     => $xcode::license_timeout,
    }
  }

  if $xcode::manage_first_launch {
    exec { 'xcode_run_first_launch':
      command     => "${xcodebuild} -runFirstLaunch",
      unless      => "/usr/bin/grep -qxF ${state} ${stamp}",
      environment => $environment,
      path        => $path,
      logoutput   => 'on_failure',
      timeout     => $xcode::first_launch_timeout,
    }

    # Written only once the exec succeeded. With `file ~> exec` the new state
    # would be recorded before the command ran, so a failure would never be
    # retried; this ordering makes the next run pick it up again.
    file { $stamp:
      ensure  => file,
      owner   => 'root',
      group   => 'wheel',
      mode    => '0644',
      content => "${state}\n",
    }

    Exec['xcode_run_first_launch'] -> File[$stamp]
  }

  # Select the toolchain first, then accept its licence, then let the licensed
  # xcodebuild install the components.
  if $xcode::manage_developer_dir and $xcode::manage_license {
    Exec['xcode_select_switch'] -> Exec['xcode_license_accept']
  }

  if $xcode::manage_developer_dir and $xcode::manage_first_launch {
    Exec['xcode_select_switch'] -> Exec['xcode_run_first_launch']
  }

  if $xcode::manage_license and $xcode::manage_first_launch {
    Exec['xcode_license_accept'] -> Exec['xcode_run_first_launch']
  }
}
