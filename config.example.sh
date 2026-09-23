# macos-base-config - per-machine settings for bootstrap.sh.
#
# Copy to ~/.config/macos-base-config/config.sh (or pass --config <path>) and
# edit. Plain bash, sourced by bootstrap.sh. Every key is optional; an empty
# value means the default. Steps named on the command line replace
# BOOTSTRAP_STEPS; --skip adds to BOOTSTRAP_SKIP.

# Steps to run when none are given, e.g. "keymaps dotfiles".
# Empty = every step. See ./bootstrap.sh --list.
BOOTSTRAP_STEPS=""

# Steps (or aliases) never to run on this machine, e.g. "karabiner".
BOOTSTRAP_SKIP=""

# --- packages (brew step) -----------------------------------------------------

# What to install from the catalog, packages/catalog.txt (see
# ./bootstrap.sh --list-packages): package ids, @category or @all; a leading
# "-" removes one, e.g. "@base -sidebar". Nothing is required: ""
# installs nothing. Without this key: "@base" = Karabiner-Elements, AltTab,
# Sidebar, JetBrains Mono.
PACKAGES="@base"

# --- brew step ----------------------------------------------------------------

# Extra Brewfile for apps outside the catalog, installed after the selected
# packages, e.g. "~/.config/macos-base-config/Brewfile". Empty = none.
BREW_BUNDLE_EXTRA=""

# --- macos step ---------------------------------------------------------------

# 1 = allow apps from anywhere: "sudo spctl --master-disable", then macOS asks
# you to confirm under System Settings > Privacy & Security (the step opens
# it). 0 = leave Gatekeeper as it is.
MACOS_DISABLE_GATEKEEPER=0

# --- extras step --------------------------------------------------------------

# NAS shares for the nas-mount app (package nas-mount in PACKAGES): smb://,
# afp:// or nfs:// URLs, separated by spaces or newlines; a space inside a
# path is %20. No credentials - Finder takes them from the Keychain. Empty =
# nas-mount is skipped. Example: "smb://nas.local/data smb://nas.local/media"
NAS_MOUNT_SHARES=""

# --- apps step ----------------------------------------------------------------

# Private settings directory: the app settings in apps/registry.txt, written
# by "python3 apps/app_settings.py export --dir <dir>". Empty = settings/ next
# to this config file, else this file's directory; a relative path is
# relative to this file. Keep it out of the public repo, e.g. in a private
# config repo cloned to ~/.config/macos-base-config.
SETTINGS_DIR=""

# --- dotfiles step ------------------------------------------------------------

# Checkout to use, cloned there if missing. Empty = next to this repo
# (<parent>/dotfiles). Point it at an existing checkout, e.g. "~/Git/dotfiles".
DOTFILES_DIR=""

# Clone URL when DOTFILES_DIR doesn't exist yet. Empty = the URL in repos.txt.
DOTFILES_URL=""

# 1 = run dotfiles/bootstrap.sh with --yes: repoint stow links that belong to
# another checkout without asking. 0 = ask.
DOTFILES_ASSUME_YES=0

# Extra terminal stow packages, handed to dotfiles/bootstrap.sh.
DOTFILES_TERMINALS=""

# Own omnishell config.toml. Copied to ~/.config/omnishell/config.toml after
# the dotfiles bootstrap (which installs the repo's copy every run), then
# applied with "omnishell apply -y". Empty = keep the dotfiles repo's config.
DOTFILES_OMNISHELL_CONFIG=""

# Shell lines for ~/.zshrc.local and ~/.bashrc.local (the dotfiles' untracked,
# machine-specific rc files, sourced last by both shells). Written after the
# dotfiles bootstrap as one managed block, replaced on every run; the rest of
# those files is left alone. Empty = remove the block. Must be valid for both
# bash and zsh. Example:
#
#   DOTFILES_LOCAL_RC='
#   # Kubernetes dashboard: print a login token for the admin-user service account
#   command -v kubectl >/dev/null 2>&1 &&
#     alias kdash-token="kubectl -n kubernetes-dashboard create token admin-user"
#   '
DOTFILES_LOCAL_RC=""
