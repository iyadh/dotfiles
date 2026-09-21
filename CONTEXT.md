# Dotfiles

A public repo that holds one person's working setup and restores it on any of their machines. It starts by tracking config files and grows into rebuilding a Machine from scratch.

## Language

### Machines and setup

**Machine**:
A computer this repo sets up. Machines of the same kind get the same setup; there are no per-Machine roles.
_Avoid_: host, box, computer, laptop, profile, role

**Workstation**:
A Machine you work on: long shell sessions, editing code, running toolchains. Gets the full setup.
_Avoid_: dev machine, main machine, daily driver

**Managed Machine**:
A Machine you work with over SSH: logs, containers, updates. Gets the Portable core only.
_Avoid_: server, remote, box, headless

**Trusted Machine**:
A Machine allowed to reach the Vault. Workstations only.
_Avoid_: personal machine, secure machine

**Portable core**:
The part of the setup that works on every Machine: the shell, prompt, and git.
_Avoid_: minimal setup, base config

**Bootstrap**:
Taking a fresh Machine to the setup its kind calls for, in one step.
_Avoid_: install, provision, setup

### What goes in the repo

**Tracked config**:
A config file that lives in this repo and is put in place on each Machine.
_Avoid_: dotfile (too broad), managed file

**Kept tool**:
A tool you would miss on a new Machine. Only Kept tools get Tracked configs.
_Avoid_: core tool, essential

**Experiment**:
A tool being tried out. Its config stays out of the repo until it becomes a Kept tool.
_Avoid_: trial, candidate

**Local override**:
Configuration that belongs to one Machine or to work (identities, client names, internal hosts) and lives only on that Machine, never in the repo.
_Avoid_: private config, work config, local config

**Secret**:
A credential (password, token, key). Lives only in the Vault; never in the repo or in a Local override.
_Avoid_: credential, sensitive value

**Vault**:
The single source of truth for Secrets, outside the repo and outside every Machine's files.
_Avoid_: keychain, secrets file, password manager

### How configs arrive

**Import**:
Bringing an existing config into the repo unchanged, apart from removing Secrets and Local overrides, as a known-good baseline.
_Avoid_: migration, adoption

**Cleanup**:
A later, separate change that tidies an Imported config.
_Avoid_: refactor (when meaning this), rewrite
