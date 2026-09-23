# dotfiles

## Bootstrap

On a fresh Machine with git and curl, no root needed:

```sh
curl -fsSL https://raw.githubusercontent.com/iyadh/dotfiles/master/bootstrap.sh | bash
```

Or from a clone, which must live at `~/.dotfiles`:

```sh
git clone https://github.com/iyadh/dotfiles.git ~/.dotfiles && ~/.dotfiles/bootstrap.sh
```

Bootstrap installs [chezmoi](https://chezmoi.io) into `~/.local/bin`, asks once whether this Machine is a Workstation or a Managed Machine (or reads `DOTFILES_KIND=workstation|managed`), links each Tracked config into `~/.dotfiles`, and turns on the repo's git hooks. Running it again changes nothing. Update later with `chezmoi update`.

It never overwrites a config chezmoi didn't create. If one exists, Bootstrap lists it and stops without changing anything: move it aside and run it again.

Workstations get every Tracked config; Managed Machines get the Portable core only. The shell config is three layers under `~/.config/shell`: a portable one that bash and zsh both read, a zsh one, and a macOS one. Every Machine gets the first two; only a Mac gets the third (`home/.chezmoiignore`).

Tracked configs live in `home/` (chezmoi's source, selected by `.chezmoiroot`). Everything else is repo tooling.

## Local overrides

Identity (real name, email), and anything tied to one Machine or to work, stays on the Machine, never in the repo:

- **git**: `~/.gitconfig.local`, included last by the tracked `~/.gitconfig`. Your identity goes here, and per-client identities as path-based includes pointing at each client folder's own config file:

  ```gitconfig
  [user]
      name = <name>
      email = <email>
  [includeIf "gitdir:~/projects/<client>/"]
      path = ~/projects/<client>/.gitconfig
  ```

- **shell**: one file per layer under `~/.config/shell`, each sourced by its layer when it exists, so an override sits next to the layer it belongs to:

  | Override               | Loaded by                      | For                                          |
  | ---------------------- | ------------------------------ | -------------------------------------------- |
  | `portable.local.sh`    | bash and zsh, every Machine    | environment, PATH and aliases                 |
  | `zsh.local.zsh`        | zsh, every Machine             | zsh-only settings                             |
  | `macos.local.sh`       | bash and zsh, Macs only        | anything that assumes a Mac                   |

  Work credentials, work-only aliases and per-Machine settings live here. Credentials come from the Vault; export them by hand.

## Contributing

Enable the git hooks once after cloning (Bootstrap does this for `~/.dotfiles`):

```sh
git config core.hooksPath .githooks
```

Branching, commit format, and what the hooks check: [docs/agents/git-workflow.md](docs/agents/git-workflow.md).

Checks, also run on every PR:

- `scripts/test-hooks.sh`: the git hooks.
- `scripts/test-bootstrap.sh [debian|arch]`: Bootstrap in a fresh container: Debian as a Managed Machine, Arch as a Workstation (needs Docker).
- `scripts/shellcheck.sh`: every shell script, hooks included.
