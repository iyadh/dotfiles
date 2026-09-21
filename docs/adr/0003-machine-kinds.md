# Machines are grouped into three kinds, not per-Machine setups

Six Machines across five operating systems (macOS, Arch, Debian, and two Windows) are served by three kinds rather than one setup each. **Workstations** (MacBook Pro, EndeavourOS laptop) get the full setup, including a package list for their OS. **Managed Machines** (homelab, VPS) get the Portable core plus a handful of packages, because what they run is their own concern, not the dotfiles'. The **Corporate Machine** (Windows 10, MSYS2) gets only the portable shell layer and git config, sourced from a clone with nothing installed. Per-Machine setups were rejected: six variants would all need testing, while three kinds keep the differences to the ones that matter.

## Consequences

- Only Workstations are Trusted Machines, so only they may reach the Vault. The Corporate Machine never does, whatever its policy allows.
- The shell config is split into a portable POSIX layer, a zsh layer, and a macOS layer, because the Corporate and Managed Machines can only use the first.
- The personal Windows 11 partition is out of scope; the laptop's EndeavourOS side is the Workstation.
