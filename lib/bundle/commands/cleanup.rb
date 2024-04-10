# frozen_string_literal: true

require "utils/formatter"

module Bundle
  module Commands
    # TODO: refactor into multiple modules
    module Cleanup
      module_function

      def reset!
        @dsl = nil
        @kept_casks = nil
        Bundle::CaskDumper.reset!
        Bundle::BrewDumper.reset!
        Bundle::TapDumper.reset!
        Bundle::VscodeExtensionDumper.reset!
        Bundle::JetBrainsExtensionDumper.reset!
        Bundle::BrewServices.reset!
      end

      def run(global: false, file: nil, force: false, zap: false)
        casks = casks_to_uninstall(global:, file:)
        formulae = formulae_to_uninstall(global:, file:)
        taps = taps_to_untap(global:, file:)
        vscode_extensions = vscode_extensions_to_uninstall(global:, file:)
        jetbrains_extensions = jetbrains_extensions_to_uninstall(global:, file:)
        if force
          if casks.any?
            args = zap ? ["--zap"] : []
            Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--cask", *args, "--force", *casks
            puts "Uninstalled #{casks.size} cask#{(casks.size == 1) ? "" : "s"}"
          end

          if formulae.any?
            Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", *formulae
            puts "Uninstalled #{formulae.size} formula#{(formulae.size == 1) ? "" : "e"}"
          end

          Kernel.system HOMEBREW_BREW_FILE, "untap", *taps if taps.any?

          vscode_extensions.each do |extension|
            Kernel.system "code", "--uninstall-extension", extension
          end

          if jetbrains_extensions.any?
            puts "JetBrains IDEs do not support removing extensions from the CLI. You have to manually remove them:"
            puts Formatter.columns jetbrains_extensions
          end

          cleanup = system_output_no_stderr(HOMEBREW_BREW_FILE, "cleanup")
          puts cleanup unless cleanup.empty?
        else
          if casks.any?
            puts "Would uninstall casks:"
            puts Formatter.columns casks
          end

          if formulae.any?
            puts "Would uninstall formulae:"
            puts Formatter.columns formulae
          end

          if taps.any?
            puts "Would untap:"
            puts Formatter.columns taps
          end

          if vscode_extensions.any?
            puts "Would uninstall VSCode extensions:"
            puts Formatter.columns vscode_extensions
          end

          if jetbrains_extensions.any?
            puts "Would uninstall JetBrains extensions:"
            puts Formatter.columns jetbrains_extensions
          end

          cleanup = system_output_no_stderr(HOMEBREW_BREW_FILE, "cleanup", "--dry-run")
          unless cleanup.empty?
            puts "Would `brew cleanup`:"
            puts cleanup
          end

          if casks.any? || formulae.any? || taps.any? || !cleanup.empty?
            puts "Run `brew bundle cleanup --force` to make these changes."
          end
        end
      end

      def casks_to_uninstall(global: false, file: nil)
        Bundle::CaskDumper.cask_names - kept_casks(global:, file:)
      end

      def formulae_to_uninstall(global: false, file: nil)
        @dsl ||= Bundle::Dsl.new(Brewfile.read(global:, file:))
        kept_formulae = @dsl.entries.select { |e| e.type == :brew }.map(&:name)
        kept_cask_formula_dependencies = Bundle::CaskDumper.formula_dependencies(kept_casks)
        kept_formulae += kept_cask_formula_dependencies
        kept_formulae.map! do |f|
          Bundle::BrewDumper.formula_aliases[f] ||
            Bundle::BrewDumper.formula_oldnames[f] ||
            f
        end

        current_formulae = Bundle::BrewDumper.formulae
        kept_formulae += recursive_dependencies(current_formulae, kept_formulae)
        current_formulae.reject! do |f|
          Bundle::BrewInstaller.formula_in_array?(f[:full_name], kept_formulae)
        end
        current_formulae.map { |f| f[:full_name] }
      end

      def kept_casks(global: false, file: nil)
        return @kept_casks if @kept_casks

        @dsl ||= Bundle::Dsl.new(Brewfile.read(global:, file:))
        @kept_casks = @dsl.entries.select { |e| e.type == :cask }.map(&:name)
      end

      def recursive_dependencies(current_formulae, formulae_names, top_level: true)
        @checked_formulae_names = [] if top_level
        dependencies = []

        formulae_names.each do |name|
          next if @checked_formulae_names.include?(name)

          formula = current_formulae.find { |f| f[:full_name] == name }
          next unless formula

          f_deps = formula[:dependencies]
          unless formula[:poured_from_bottle?]
            f_deps += formula[:build_dependencies]
            f_deps.uniq!
          end
          next unless f_deps
          next if f_deps.empty?

          @checked_formulae_names << name
          f_deps += recursive_dependencies(current_formulae, f_deps, top_level: false)
          dependencies += f_deps
        end

        dependencies.uniq
      end

      IGNORED_TAPS = %w[homebrew/core homebrew/bundle].freeze

      def taps_to_untap(global: false, file: nil)
        @dsl ||= Bundle::Dsl.new(Brewfile.read(global:, file:))
        kept_taps = @dsl.entries.select { |e| e.type == :tap }.map(&:name)
        current_taps = Bundle::TapDumper.tap_names
        current_taps - kept_taps - IGNORED_TAPS
      end

      def vscode_extensions_to_uninstall(global: false, file: nil)
        @dsl ||= Bundle::Dsl.new(Brewfile.read(global:, file:))
        kept_extensions = @dsl.entries.select { |e| e.type == :vscode }.map { |x| x.name.downcase }

        # To provide a graceful migration from `Brewfile`s that don't yet or
        # don't want to use `vscode`: don't remove any extensions if we don't
        # find any in the `Brewfile`.
        return [].freeze if kept_extensions.empty?

        current_extensions = Bundle::VscodeExtensionDumper.extensions
        current_extensions - kept_extensions
      end

      def jetbrains_extensions_to_uninstall(global: false, file: nil)
        @dsl ||= Bundle::Dsl.new(Brewfile.read(global:, file:))
        kept_extensions = @dsl.entries.select { |e| e.type == :jetbrains }.map { |x| "#{x.name.downcase} (#{x.options[:ide]})" }

        # To provide a graceful migration from `Brewfile`s that don't yet or
        # don't want to use `jetbrains`: don't remove any extensions if we don't
        # find any in the `Brewfile`.
        return [].freeze if kept_extensions.empty?

        current_extensions = Bundle::JetBrainsExtensionDumper.extensions
        current_extensions - kept_extensions
      end

      def system_output_no_stderr(cmd, *args)
        IO.popen([cmd, *args], err: :close).read
      end
    end
  end
end
