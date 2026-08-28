# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/xcode/detect'

describe PuppetX::Xcode::Detect do
  subject(:facts) { described_class.facts }

  let(:xcode_app) { '/Applications/Xcode.app' }
  let(:developer_dir) { "#{xcode_app}/Contents/Developer" }
  let(:clt) { '/Library/Developer/CommandLineTools' }

  before do
    allow(Dir).to receive(:glob).with('/Applications/Xcode*.app').and_return([])
    allow(File).to receive_messages(directory?: false, file?: false, executable?: false)
    allow(Facter::Core::Execution).to receive(:execute).and_return(nil)
    allow(described_class).to receive(:license_accepted?).and_return(true)
  end

  def stub_developer_dir(path)
    allow(Facter::Core::Execution).to receive(:execute)
      .with('/usr/bin/xcode-select -p', on_fail: nil)
      .and_return("#{path}\n")
  end

  def stub_bundle(path: nil, version: '16.2', build: '16C5032a')
    bundle = path || xcode_app
    allow(File).to receive(:directory?).with(bundle).and_return(true)
    allow(File).to receive(:file?).with("#{bundle}/Contents/version.plist").and_return(true)
    {
      'CFBundleShortVersionString' => version,
      'ProductBuildVersion' => build,
    }.each do |key, value|
      allow(Facter::Core::Execution).to receive(:execute)
        .with("/usr/bin/defaults read #{bundle}/Contents/version.plist #{key}", on_fail: nil)
        .and_return("#{value}\n")
    end
  end

  context 'with Xcode selected and the licence accepted' do
    before do
      stub_developer_dir(developer_dir)
      stub_bundle
    end

    it { expect(facts['type']).to eq('xcode') }
    it { expect(facts['installed']).to be true }
    it { expect(facts['app_path']).to eq(xcode_app) }
    it { expect(facts['version']).to eq('16.2') }
    it { expect(facts['build']).to eq('16C5032a') }
    it { expect(facts['license_accepted']).to be true }
  end

  context 'with Xcode selected but the licence not accepted' do
    before do
      stub_developer_dir(developer_dir)
      stub_bundle
      # `xcodebuild -version` exits 69 in this state.
      allow(described_class).to receive(:license_accepted?).and_return(false)
    end

    it { expect(facts['license_accepted']).to be false }

    it 'still reports the version, because it is read from the plist' do
      expect(facts['version']).to eq('16.2')
      expect(facts['build']).to eq('16C5032a')
    end
  end

  context 'when version.plist lacks the Xcode-specific keys' do
    before do
      stub_developer_dir(developer_dir)
      allow(File).to receive(:directory?).with(xcode_app).and_return(true)
      allow(File).to receive(:file?).with("#{xcode_app}/Contents/Info.plist").and_return(true)
      {
        'CFBundleShortVersionString' => '16.2',
        'CFBundleVersion' => '23504',
      }.each do |key, value|
        allow(Facter::Core::Execution).to receive(:execute)
          .with("/usr/bin/defaults read #{xcode_app}/Contents/Info.plist #{key}", on_fail: nil)
          .and_return("#{value}\n")
      end
    end

    it 'falls back to Info.plist' do
      expect(facts['version']).to eq('16.2')
      expect(facts['build']).to eq('23504')
    end
  end

  context 'with only the Command Line Tools' do
    before do
      stub_developer_dir(clt)
      allow(File).to receive(:executable?).with("#{clt}/usr/bin/clang").and_return(true)
    end

    it { expect(facts['type']).to eq('command_line_tools') }
    it { expect(facts['installed']).to be false }
    it { expect(facts['app_path']).to be_nil }
    it { expect(facts['command_line_tools']).to be true }

    it 'leaves license_accepted nil rather than false' do
      expect(facts['license_accepted']).to be_nil
    end
  end

  context 'with no developer directory selected at all' do
    it { expect(facts['developer_dir']).to be_nil }
    it { expect(facts['type']).to be_nil }
    it { expect(facts['installed']).to be false }
    it { expect(facts['license_accepted']).to be_nil }
  end

  context 'with several Xcode versions installed and the CLT selected' do
    before do
      stub_developer_dir(clt)
      allow(Dir).to receive(:glob).with('/Applications/Xcode*.app')
                                  .and_return(['/Applications/Xcode-16.1.app', '/Applications/Xcode-16.2.app'])
      stub_bundle(path: '/Applications/Xcode-16.2.app')
    end

    it 'falls back to the newest bundle rather than a hardcoded path' do
      expect(facts['app_path']).to eq('/Applications/Xcode-16.2.app')
    end
  end

  context 'when a plist read fails' do
    before do
      stub_developer_dir(developer_dir)
      allow(File).to receive(:directory?).with(xcode_app).and_return(true)
      allow(File).to receive(:file?).with("#{xcode_app}/Contents/version.plist").and_return(true)
    end

    it 'reports nil instead of raising' do
      expect(facts['version']).to be_nil
      expect(facts['build']).to be_nil
      expect(facts['installed']).to be true
    end
  end
end
