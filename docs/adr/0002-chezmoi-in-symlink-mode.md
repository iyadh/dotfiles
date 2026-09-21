# chezmoi in symlink mode, not stow

Tracked configs are applied with chezmoi in symlink mode on every Machine. GNU stow was the obvious choice and is simpler, but it has no way to vary a JSON or TOML file between macOS and Linux, no built-in way to choose which configs each Machine kind gets, no way to report drift, and nothing for the package installs and system settings that stage 2 needs. Symlink mode keeps stow's main benefit: the file in the home directory is the repo file, so it can be edited in place and cannot drift.

## Consequences

- Files generated from templates are written as real files, not symlinks, so they need `chezmoi diff`/`re-add` discipline.
- An app that saves by replacing its settings file (Zed) can turn its symlink into a regular file and silently detach from the repo. Such configs are decided case by case.
