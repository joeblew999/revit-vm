# vm-servers

Provision a remote Windows VM and drive it from a **browser GUI** (Start / Stop / Snapshot buttons + live status). Built on [dockur/windows](https://github.com/dockur/windows) (auto-downloads Windows ISO + runs unattended setup) on top of Hetzner Cloud (TCG, cheap) or Vultr Bare Metal (KVM, fast). Every tool installs via mise — no compilers, no curl-piped installers. Cross-platform: lifecycle + RDP layer dispatch on `$nu.os-info.name` (macOS via Homebrew + `open`; Linux via xfreerdp/remmina + `xdg-open`; Windows via the built-in `mstsc.exe`).

Generic — any Windows software fits. Sibling [vm-software](https://github.com/joeblew999/vm-software) holds per-app install recipes.

## GUI (the daily UX)

```sh
mise install                 # tools: hcloud, vultr-cli, aws, fnox, nushell, pitchfork, http-nu, xs, yoke
mise run token:set           # paste your Hetzner API token (one-time)
mise run xs:serve:bg         # event bus (one-time, survives shell)
mise run gui:serve           # opens http://127.0.0.1:8080
```

The status board shows:

- **VMs** — current state from `state/vms.jsonl` (live-polled every 5 s via Datastar)
- **Snapshots** — fetched live from the active provider's API
- **Actions** — Start / Stop / Snapshot / Refresh Status buttons that POST to mise tasks
- **Recent installs** — joined from sibling vm-software's `state/installs.jsonl`

Buttons fire-and-forget; the lifecycle runs in the background and progress lands in `state/vms.jsonl` which the gui re-renders within seconds.

## CLI (same surface, power users)

Every button is also a mise task — useful for scripting, CI, or when you don't want to leave the terminal:

```sh
mise run start            # provision (from snapshot if any) → wait for RDP → open client
mise run push -- <path>   # copy a local file into the VM at \\host.lan\Data
mise run pull -- <name>   # copy a file out
mise run stop             # snapshot → prune older → destroy VM
mise run vm:status        # what's running right now (live from provider)
mise tasks                # ~50 more (vm:*, snapshot:*, debug:*, vultr:*, rdp:*, ci:*, ai:ask, ...)
```

## AI driver (yoke + MCP)

```sh
mise run ai:ask -- "is my vm running? if not, start it from the latest snapshot"
mise run mcp:serve        # stdio MCP server — point Claude Desktop / Claude Code at it
```

Both invoke the same underlying mise tasks the buttons and CLI do. Three surfaces, one execution layer.

## Providers

`VM_PROVIDER` env (`"hetzner"` default, `"vultr"`) routes every dispatch. To switch to Vultr Bare Metal, set `VM_PROVIDER = "vultr"` in `mise.local.toml`, run `mise run vultr:setup`, then `mise run r2:bootstrap` (R2 is the snapshot transit bucket since Vultr has no hot-snapshot).

## Layout

```
mise.toml                   # all tasks (single surface — same for gui / CLI / MCP / yoke)
fnox.toml                   # secret pointer table (keychain-backed)
cloud-init/                 # qemu.yaml + kvm.yaml (host bootstrap) + oem.bat (Windows OEM hook)
gui/                        # browser front end (http-nu + Datastar + pico CSS)
providers/{hetzner,vultr}/  # provider-specific .nu implementations
lifecycle/                  # start, stop, dispatch (orchestrators behind start/stop buttons)
connect/                    # rdp:* + viewer:open (connect to running VM, cross-platform)
files/                      # push / pull / files:ls
debug/                      # debug:ssh / probe / logs / metrics / version / host-disk
deps/                       # deps:check (provider tools + token sanity)
r2/                         # R2 bootstrap + sanity check (snapshot transit)
mcp/                        # init.nu hook for mcp:serve + ai:ask
ci/                         # syntax / schema / dispatch checks (same as GH Actions)
state/                      # vms.jsonl + vms.schema.json + runs.nu view + costs.jsonl
```

See [CLAUDE.md](CLAUDE.md) for design decisions and [ROADMAP.md](ROADMAP.md) for what's coming.
