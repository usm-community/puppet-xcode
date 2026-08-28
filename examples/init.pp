# Accept the Xcode licence and replay the first-launch component install after a
# macOS or Xcode update. This is the common case.
include xcode

# Fuller example: also install the Command Line Tools, point xcode-select at the
# Xcode bundle, and fail the run when Xcode is missing instead of skipping.
#
# class { 'xcode':
#   manage_command_line_tools => true,
#   manage_developer_dir      => true,
#   fail_if_absent            => true,
# }
#
# Pin a specific bundle on hosts carrying several Xcode versions:
#
# class { 'xcode':
#   app_path => '/Applications/Xcode-16.2.app',
# }
