# frozen_string_literal: true

module Bundle
  module Checker
    class JetBrainsExtensionChecker < Bundle::Checker::Base
      PACKAGE_TYPE = :jetbrains
      PACKAGE_TYPE_NAME = "JetBrains Extension"

      def failure_reason(extension, no_upgrade:)
        "#{PACKAGE_TYPE_NAME} #{extension} needs to be installed."
      end

      def installed_and_up_to_date?(extension, no_upgrade: false)
        Bundle::JetBrainsExtensionInstaller.extension_installed?(extension)
      end
    end
  end
end
