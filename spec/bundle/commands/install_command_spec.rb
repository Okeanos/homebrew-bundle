# frozen_string_literal: true

require "spec_helper"

describe Bundle::Commands::Install do
  before do
    allow_any_instance_of(IO).to receive(:puts)
    allow(Bundle::Locker).to receive(:write_lockfile?).and_return(false)
  end

  context "when a Brewfile is not found" do
    it "raises an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_raise(Errno::ENOENT)
      expect { described_class.run }.to raise_error(RuntimeError)
    end
  end

  context "when a Brewfile is found" do
    let(:brewfile_contents) do
      <<~EOS
        tap 'phinze/cask'
        brew 'mysql', conflicts_with: ['mysql56']
        cask 'phinze/cask/google-chrome', greedy: true
        mas '1Password', id: 443987910
        whalebrew 'whalebrew/wget'
        vscode 'GitHub.codespaces'
        jetbrains 'tanvd.grazi', args { ide: 'idea' }
      EOS
    end

    it "does not raise an error" do
      allow(Bundle::TapInstaller).to receive(:preinstall).and_return(false)
      allow(Bundle::WhalebrewInstaller).to receive(:preinstall).and_return(false)
      allow(Bundle::VscodeExtensionInstaller).to receive(:preinstall).and_return(false)
      allow(Bundle::JetBrainsExtensionInstaller).to receive(:preinstall).and_return(false)
      allow(Bundle::BrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::CaskInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)
      expect { described_class.run }.not_to raise_error
    end

    it "does not raise an error when skippable" do
      expect(Bundle::BrewInstaller).not_to receive(:install)

      allow(Bundle::Skipper).to receive(:skip?).and_return(true)
      allow_any_instance_of(Pathname).to receive(:read)
        .and_return("brew 'mysql'")
      expect { described_class.run }.not_to raise_error
    end

    it "exits on failures" do
      allow(Bundle::BrewInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::CaskInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::TapInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::WhalebrewInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::VscodeExtensionInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::JetBrainsExtensionInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::Locker).to receive(:lockfile).and_return(Pathname(__dir__))
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect { described_class.run }.to raise_error(SystemExit)
    end

    it "skips installs from failed taps" do
      allow(Bundle::CaskInstaller).to receive(:preinstall).and_return(false)
      allow(Bundle::TapInstaller).to receive_messages(preinstall: true, install: false)
      allow(Bundle::BrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::WhalebrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::VscodeExtensionInstaller).to receive_messages(preinstall: true, install: true)
      allow(Bundle::JetBrainsExtensionInstaller).to receive_messages(preinstall: true, install: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect(Bundle).not_to receive(:system)
      expect { described_class.run }.to raise_error(SystemExit)
    end
  end
end
