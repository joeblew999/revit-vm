# vm-servers

Provision a remote Windows VM driven from a Mac via `mise` + `nushell` tasks. Built on [dockur/windows](https://github.com/dockur/windows) (auto-downloads Windows ISO + runs unattended setup) on top of Hetzner Cloud (TCG, cheap) or Vultr Bare Metal (KVM, fast).

Generic — any Windows software fits. Sibling [vm-software](https://github.com/joeblew999/vm-software) holds per-app install recipes; the embedded `gui/` folder is a small http-nu status board.

## Daily

```sh
mise run start            # provision (from snapshot if any) → wait for RDP → open client
mise run push -- <path>   # copy a local file into the VM at \\host.lan\Data
mise run pull -- <name>   # copy a file out
mise run stop             # snapshot → prune older → destroy VM
```

## Setup (per machine)

```sh
mise install              # hcloud, vultr-cli, aws, fnox, nushell, pitchfork
mise run token:set        # paste Hetzner API token
mise run start            # ~1hr first time (Windows install), ~90s thereafter
```

To switch from Hetzner to Vultr Bare Metal, set `VM_PROVIDER = "vultr"` in `mise.local.toml` and follow `mise run vultr:setup`. Snapshot transit on Vultr uses Cloudflare R2 — run `mise run r2:bootstrap` once.

## Layout

```
mise.toml                 # all tasks (single surface)
fnox.toml                 # secret pointer table (keychain-backed)
cloud-init-*.yaml         # host bootstrap for fresh provisions
oem/install.bat           # first-boot Windows setup (Z: mount, defender excludes, no sleep)
providers/{hetzner,vultr}/  # provider-specific .nu implementations
connect/                  # rdp:wait / rdp:open / rdp:install
files/                    # push / pull / files:ls
debug/                    # debug:ssh / probe / logs / metrics / version / host-disk
deps/                     # deps:check (provider tools + token sanity)
viewer/                   # viewer:open (dockur web viewer on :8006)
gui/                      # http-nu status board (read-only)
r2/                       # R2 bootstrap + sanity check (snapshot transit)
state/vms.jsonl           # lifecycle event log; committed to git
state/vms.schema.json     # JSONL contract (writers go through state/append.nu)
```

`mise tasks` lists everything. See [CLAUDE.md](CLAUDE.md) for design decisions.
