# vm-servers

Provision a remote Windows VM driven from your dev box via `mise` + `nushell` tasks. Built on [dockur/windows](https://github.com/dockur/windows) (auto-downloads Windows ISO + runs unattended setup) on top of Hetzner Cloud (TCG, cheap) or Vultr Bare Metal (KVM, fast). Every tool installs via mise — no compilers, no curl-piped installers. Cross-platform: lifecycle + RDP layer dispatch on `$nu.os-info.name` (macOS via Homebrew + `open`; Linux via xfreerdp/remmina + `xdg-open`; Windows via the built-in `mstsc.exe`).

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
mise install              # hcloud, vultr-cli, aws, fnox, nushell, pitchfork, http-nu, xs, yoke
mise run token:set        # paste Hetzner API token
mise run start            # ~1hr first time (Windows install), ~90s thereafter
```


To switch from Hetzner to Vultr Bare Metal, set `VM_PROVIDER = "vultr"` in `mise.local.toml` and follow `mise run vultr:setup`. Snapshot transit on Vultr uses Cloudflare R2 — run `mise run r2:bootstrap` once.

## Layout

```
mise.toml                 # all tasks (single surface)
fnox.toml                 # secret pointer table (keychain-backed)
cloud-init/               # qemu.yaml + kvm.yaml (host bootstrap) + oem.bat (Windows OEM hook)
providers/{hetzner,vultr}/  # provider-specific .nu implementations
lifecycle/                # start, stop, dispatch (orchestrators)
connect/                  # rdp:* + viewer:open (connect to running VM)
files/                    # push / pull / files:ls
debug/                    # debug:ssh / probe / logs / metrics / version / host-disk
deps/                     # deps:check (provider tools + token sanity)
r2/                       # R2 bootstrap + sanity check (snapshot transit)
mcp/                      # init.nu hook for mcp:serve + ai:ask
ci/                       # syntax / schema / dispatch checks (same as GH Actions)
gui/                      # http-nu status board (read-only v0; xs writes coming in v1)
state/                    # vms.jsonl + vms.schema.json + runs.nu view + costs.jsonl
```

`mise tasks` lists everything. See [CLAUDE.md](CLAUDE.md) for design decisions.
