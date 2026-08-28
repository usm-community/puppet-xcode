# frozen_string_literal: true

require 'shellwords'

module PuppetX
  module Xcode
    # Resolves the state of the Xcode toolchain on a macOS host.
    #
    # Kept apart from the fact itself so the detection logic can be exercised
    # directly, without Facter's `confine` standing in the way.
    module Detect
      # Where the standalone Command Line Tools live, and the compiler whose
      # presence is taken as proof that they are installed.
      COMMAND_LINE_TOOLS = '/Library/Developer/CommandLineTools'
      COMMAND_LINE_TOOLS_CLANG = '/Library/Developer/CommandLineTools/usr/bin/clang'

      module_function

      # The full `xcode` fact value.
      def facts
        developer_dir = active_developer_dir
        app_path = resolve_app_path(developer_dir)
        type = resolve_type(developer_dir)
        version, build = bundle_version(app_path)

        {
          'developer_dir' => developer_dir,
          'type' => type,
          'installed' => !app_path.nil?,
          'app_path' => app_path,
          'version' => version,
          'build' => build,
          # Left nil unless Xcode is the active toolchain, so that "licence
          # refused" is never confused with "Xcode absent".
          'license_accepted' => (license_accepted? if type == 'xcode'),
          'command_line_tools' => File.executable?(COMMAND_LINE_TOOLS_CLANG),
        }
      end

      # The directory xcode-select currently points at, or nil when unset.
      def active_developer_dir
        value = Facter::Core::Execution.execute('/usr/bin/xcode-select -p', on_fail: nil)&.strip
        value unless value.nil? || value.empty?
      end

      # The bundle xcode-select points at, falling back to the newest Xcode
      # found. The glob is what keeps hosts carrying several Xcode versions
      # working, where a hardcoded /Applications/Xcode.app would not.
      def resolve_app_path(developer_dir)
        candidate = if developer_dir&.end_with?('/Contents/Developer')
                      developer_dir.sub(%r{/Contents/Developer\z}, '')
                    else
                      Dir.glob('/Applications/Xcode*.app').max
                    end

        candidate if candidate && File.directory?(candidate)
      end

      # Which toolchain the developer directory designates.
      def resolve_type(developer_dir)
        return nil if developer_dir.nil?

        if developer_dir.end_with?('/Contents/Developer')
          'xcode'
        elsif developer_dir.start_with?(COMMAND_LINE_TOOLS)
          'command_line_tools'
        end
      end

      # Read from the bundle plists rather than from `xcodebuild -version`,
      # which fails with exit 69 precisely while the licence is unaccepted --
      # exactly when the version is needed to decide whether the components
      # must be reprovisioned.
      def bundle_version(app_path)
        return [nil, nil] if app_path.nil?

        version_plist = File.join(app_path, 'Contents', 'version.plist')
        info_plist = File.join(app_path, 'Contents', 'Info.plist')

        # ProductBuildVersion is the Xcode-specific key; CFBundleVersion from
        # Info.plist is the fallback present on any Apple bundle.
        [
          plist_key(version_plist, 'CFBundleShortVersionString') ||
            plist_key(info_plist, 'CFBundleShortVersionString'),
          plist_key(version_plist, 'ProductBuildVersion') ||
            plist_key(info_plist, 'CFBundleVersion'),
        ]
      end

      # Reads a single key from a plist, returning nil rather than raising when
      # the file or the key is absent: a fact must never blow up.
      def plist_key(path, key)
        return nil unless File.file?(path)

        value = Facter::Core::Execution.execute(
          "/usr/bin/defaults read #{Shellwords.escape(path)} #{Shellwords.escape(key)}",
          on_fail: nil,
        )
        return nil if value.nil?

        value = value.strip
        value.empty? ? nil : value
      end

      # Exit 69 means "You have not agreed to the Xcode license agreements".
      def license_accepted?
        system('/usr/bin/xcodebuild -version >/dev/null 2>&1')
      end
    end
  end
end
