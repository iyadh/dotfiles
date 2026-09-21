# chezmoi in symlink mode, not stow

Tracked configs are applied with chezmoi, set to symlink mode on macOS and Linux and file mode on Windows. GNU stow was the expected choice and is simpler, but it cannot run usefully on the Corporate Machine (MSYS2 copies instead of linking), has no way to vary a JSON or TOML file per OS, and offers nothing for the package installs and system settings that stage 2 needs. Symlink mode keeps stow's main benefit: the file in the home directory is the repo file, so it can be edited in place and cannot drift.

## Consequences

- Files generated from templates are written as real files, not symlinks, so they need `chezmoi diff`/`re-add` discipline.
- An app that saves by replacing its settings file (Zed) can turn its symlink into a regular file and silently detach from the repo. Such configs are decided case by case.
- The Corporate Machine does not run chezmoi at all: its `~/.bashrc` sources the portable shell layer straight from the clone.
