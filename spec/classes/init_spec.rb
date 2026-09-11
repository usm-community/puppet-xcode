# frozen_string_literal: true

require 'spec_helper'

describe 'xcode' do
  let(:xcode_fact) do
    {
      'developer_dir' => '/Applications/Xcode.app/Contents/Developer',
      'type' => 'xcode',
      'installed' => true,
      'app_path' => '/Applications/Xcode.app',
      'version' => '16.2',
      'build' => '16C5032a',
      'license_accepted' => true,
      'command_line_tools' => true,
    }
  end

  let(:facts) do
    {
      kernel: 'Darwin',
      os: {
        'family' => 'Darwin',
        'name' => 'Darwin',
        'architecture' => 'arm64',
        'release' => { 'major' => '25' },
        'macosx' => { 'build' => '25G83', 'version' => { 'major' => '26' } },
      },
      xcode: xcode_fact,
    }
  end

  # The stamp combines both dimensions so that an Xcode update on an unchanged
  # OS still triggers the component reinstall.
  let(:state) { '25G83-16.2-16C5032a' }
  let(:stamp) { '/var/db/puppet_xcode_state' }
  let(:developer_dir) { '/Applications/Xcode.app/Contents/Developer' }
  let(:xcodebuild) { "#{developer_dir}/usr/bin/xcodebuild" }

  context 'with Xcode installed, using defaults' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('xcode::license') }
    it { is_expected.not_to contain_class('xcode::command_line_tools') }

    it 'accepts the licence, testing the real state rather than a plist key' do
      is_expected.to contain_exec('xcode_license_accept')
        .with_command("#{xcodebuild} -license accept")
        .with_unless("#{xcodebuild} -version")
        .with_timeout(600)
        .with_environment(['DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer'])
    end

    it 'replays first launch against the combined OS + Xcode stamp' do
      is_expected.to contain_exec('xcode_run_first_launch')
        .with_command("#{xcodebuild} -runFirstLaunch")
        .with_unless("/usr/bin/grep -qxF #{state} #{stamp}")
        .with_timeout(1800)
    end

    it 'accepts the licence before running first launch' do
      is_expected.to contain_exec('xcode_run_first_launch')
        .that_requires('Exec[xcode_license_accept]')
    end

    it 'writes the stamp only after first launch succeeded, so a failure retries' do
      is_expected.to contain_file(stamp)
        .with_content("#{state}\n")
        .with_mode('0644')
        .that_requires('Exec[xcode_run_first_launch]')
    end

    it { is_expected.not_to contain_exec('xcode_select_switch') }
  end

  context 'when the Xcode build is newer but the OS is unchanged' do
    let(:xcode_fact) { super().merge('version' => '16.3', 'build' => '16E140') }

    it 'keys the stamp on the new Xcode version' do
      is_expected.to contain_exec('xcode_run_first_launch')
        .with_unless("/usr/bin/grep -qxF 25G83-16.3-16E140 #{stamp}")
      is_expected.to contain_file(stamp).with_content("25G83-16.3-16E140\n")
    end
  end

  context 'when the licence is not accepted yet' do
    # `xcodebuild -version` exits 69 here, so the fact cannot report a version.
    # It is read from the bundle plists instead, which is why it stays known.
    let(:xcode_fact) { super().merge('license_accepted' => false) }

    it { is_expected.to compile.with_all_deps }

    it 'still resolves the Xcode version for the stamp' do
      is_expected.to contain_file(stamp).with_content("#{state}\n")
    end
  end

  context 'when the fact could not resolve the Xcode version' do
    # Facter reports an unresolved key inside a structured fact as an empty
    # string, never as undef, so both forms have to be tolerated.
    %w[nil empty].each do |form|
      context "reported as #{form}" do
        let(:absent) { (form == 'nil') ? nil : '' }
        let(:xcode_fact) { super().merge('version' => absent, 'build' => absent) }

        it 'falls back to a placeholder rather than an empty stamp' do
          is_expected.to contain_file(stamp).with_content("25G83-unknown-unknown\n")
        end
      end
    end
  end

  context 'when Xcode is not installed' do
    # Guarding on undef alone is not enough: on a real host Facter hands the
    # absent bundle over as '' and the licence execs would be declared anyway.
    %w[nil empty].each do |form|
      context "with the absent bundle reported as #{form}" do
        let(:absent) { (form == 'nil') ? nil : '' }
        let(:xcode_fact) do
          super().merge(
            'developer_dir' => '/Library/Developer/CommandLineTools',
            'type' => 'command_line_tools',
            'installed' => false,
            'app_path' => absent,
            'version' => absent,
            'build' => absent,
            'license_accepted' => absent,
          )
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('xcode::license') }
        it { is_expected.not_to contain_exec('xcode_license_accept') }
        it { is_expected.not_to contain_exec('xcode_run_first_launch') }
        it { is_expected.not_to contain_file(stamp) }

        context 'with fail_if_absent' do
          let(:params) { { fail_if_absent: true } }

          it { is_expected.to compile.and_raise_error(%r{Xcode is not installed}) }
        end
      end
    end
  end

  context 'with an explicitly pinned bundle' do
    let(:params) { { app_path: '/Applications/Xcode-16.2.app' } }

    it 'uses the pinned bundle over the one the fact resolved' do
      is_expected.to contain_exec('xcode_license_accept')
        .with_command('/Applications/Xcode-16.2.app/Contents/Developer/usr/bin/xcodebuild -license accept')
    end
  end

  context 'with manage_developer_dir' do
    let(:params) { { manage_developer_dir: true } }

    it { is_expected.to compile.with_all_deps }

    it 'tests the live xcode-select target rather than the fact, so the catalog is stable' do
      is_expected.to contain_exec('xcode_select_switch')
        .with_command("/usr/bin/xcode-select -s #{developer_dir}")
        .with_unless("test \"$(/usr/bin/xcode-select -p)\" = \"#{developer_dir}\"")
        .with_provider('shell')
    end

    it 'selects the toolchain before accepting its licence and running first launch' do
      is_expected.to contain_exec('xcode_select_switch')
        .that_comes_before(['Exec[xcode_license_accept]', 'Exec[xcode_run_first_launch]'])
    end

    context 'with the licence and first launch disabled' do
      let(:params) { super().merge(manage_license: false, manage_first_launch: false) }

      it { is_expected.to compile.with_all_deps }
      it { is_expected.to contain_exec('xcode_select_switch') }
    end
  end

  context 'with manage_command_line_tools' do
    let(:params) { { manage_command_line_tools: true } }
    let(:clang) { '/Library/Developer/CommandLineTools/usr/bin/clang' }

    it { is_expected.to compile.with_all_deps }

    # Apple ships Command Line Tools updates independently of macOS releases,
    # so the trigger has to be "softwareupdate offers one", not "the OS build
    # changed" -- the latter silently misses them. The first clause covers the
    # tools being absent, which an update check alone would not report.
    it 'asks softwareupdate what is on offer instead of inferring it from the OS build' do
      is_expected.to contain_exec('xcode_install_command_line_tools')
        .with_onlyif("! test -x '#{clang}' || /usr/sbin/softwareupdate -l --no-scan " \
                     "2>/dev/null | grep -q 'Command Line Tools'")
        .with_provider('shell')
        .with_timeout(1800)
    end

    it 'keeps no state file of its own, the real state being directly observable' do
      is_expected.not_to contain_file('/var/db/puppet_xcode_clt_state')
    end

    it { is_expected.to contain_file('/var/tmp/puppet_xcode_install_command_line_tools.sh').with_mode('0700') }

    it 'installs them before touching the Xcode licence' do
      is_expected.to contain_class('xcode::command_line_tools')
        .that_comes_before('Class[xcode::license]')
    end

    context 'with command_line_tools_full_scan' do
      let(:params) { super().merge(command_line_tools_full_scan: true) }

      it 'drops --no-scan so softwareupdate contacts Apple on every run' do
        is_expected.to contain_exec('xcode_install_command_line_tools')
          .with_onlyif("! test -x '#{clang}' || /usr/sbin/softwareupdate -l " \
                       "2>/dev/null | grep -q 'Command Line Tools'")
      end
    end
  end

  context 'with the licence and first launch both disabled' do
    let(:params) { { manage_license: false, manage_first_launch: false } }

    it { is_expected.to compile.with_all_deps }
    it { is_expected.not_to contain_exec('xcode_license_accept') }
    it { is_expected.not_to contain_exec('xcode_run_first_launch') }
    it { is_expected.not_to contain_file(stamp) }
  end

  context 'on a non-Darwin host' do
    let(:facts) do
      { kernel: 'Linux', os: { 'family' => 'Debian', 'name' => 'Debian' } }
    end

    it { is_expected.to compile.and_raise_error(%r{works on macOS only}) }
  end
end
