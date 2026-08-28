# frozen_string_literal: true

require File.expand_path('../puppet_x/xcode/detect', __dir__)

# Fact: xcode
#
# Purpose: describe the state of the Xcode toolchain.
#
# Resolution:
#   Reads the active developer directory, locates the Xcode application bundle,
#   and reports its version and licence status. See PuppetX::Xcode::Detect.
#   No value set if not on Darwin.
Facter.add(:xcode) do
  confine kernel: 'Darwin'

  setcode do
    PuppetX::Xcode::Detect.facts
  end
end
