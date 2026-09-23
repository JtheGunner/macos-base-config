# Apps and fonts for this setup - installed by ./bootstrap.sh brew
# (brew bundle --no-upgrade: the apps update themselves).
# Machine-only extras: BREW_BUNDLE_EXTRA in the config (config.example.sh).

# An app that is already in /Applications but was not installed by Homebrew
# is left alone: brew would refuse to install over it and fail the bundle.
def app_missing?(name)
  !File.exist?("/Applications/#{name}.app")
end

tap "otuerk/sidebar"

# Windows key behaviour (karabiner step)
cask "karabiner-elements" if app_missing?("Karabiner-Elements")
# Windows-style Alt+Tab window switching
cask "alt-tab" if app_missing?("AltTab")
# Windows-style taskbar / Dock replacement
cask "otuerk/sidebar/sidebar" if app_missing?("Sidebar")
# editor font
cask "font-jetbrains-mono"
