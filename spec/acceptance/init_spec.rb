# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'xcode class' do
  # Acceptance coverage needs a real macOS host carrying Xcode: the licence and
  # first-launch behaviour cannot be reproduced inside a Linux container, which
  # is what voxpupuli-acceptance provisions. The equivalent checks are the
  # manual scenarios documented in the README.
  it 'is verified manually on macOS'
end
