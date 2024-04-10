# frozen_string_literal: true

module Bundle
  module JetBrainsExtensionDumper
    module_function

    def reset!
      @extensions = []
    end

    def extensions
      @extensions
    end

    def dump
      extensions.map { |name, options| "jetbrains \"#{name}\" (#{options[:ide]})" }.join("\n")
    end
  end
end
