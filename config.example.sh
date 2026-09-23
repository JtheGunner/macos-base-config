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
