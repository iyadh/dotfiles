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

## Contributing

Enable the git hooks once after cloning (Bootstrap does this for `~/.dotfiles`):

```sh
git config core.hooksPath .githooks
```

Branching, commit format, and what the hooks check: [docs/agents/git-workflow.md](docs/agents/git-workflow.md).

Checks, also run on every PR:

- `scripts/test-hooks.sh`: the git hooks.
- `scripts/test-bootstrap.sh`: Bootstrap on fresh Debian containers (needs Docker).
- `scripts/shellcheck.sh`: every shell script, hooks included.
