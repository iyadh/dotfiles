# Machines are grouped into kinds, not per-Machine setups

Four Machines across three operating systems (macOS, Arch, and Debian) are served by two kinds rather than one setup each. **Workstations** (MacBook Pro, EndeavourOS laptop) get the full setup, including a package list for their OS. **Managed Machines** (homelab, VPS) get the Portable core plus a handful of packages, because what they run is their own concern, not the dotfiles'. Per-Machine setups were rejected: each variant would need its own testing, while kinds keep the differences to the ones that matter.

## Consequences

- Only Workstations are Trusted Machines, so only they may reach the Vault.
- The shell config is split into a portable POSIX layer, a zsh layer, and a macOS layer, because Managed Machines may only have bash and few of the tools.
- Windows is out of scope entirely: neither the corporate Windows 10 machine nor the laptop's Windows 11 partition is a Machine.
