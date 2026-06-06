# vm-servers

> ⚠️ **Superseded by [vm-uncloud](https://github.com/joeblew999/vm-uncloud).**
> Hetzner deployments are consolidating onto one tool (uncloud). The Windows
> desktop now runs there as the `windows` recipe on a dedicated, teardownable
> node (`mise run win:up` / `win:deploy` / `win:down`), with the RDP/viewer
> helpers and a web status board ported over. This repo stays as the reference
> for the bespoke lifecycle + the Vultr-BM/KVM path (a future vm-uncloud node
> class) until that migration completes.

**The recommended way to run this is the browser GUI.** It surfaces every system function (start, stop, snapshot, status, run history, cost ledger, live event bus) as buttons and live-updating tables. The CLI and the MCP/AI driver call the exact same mise tasks underneath — they're alternate surfaces, not parallel implementations.

Built on [dockur/windows](https://github.com/dockur/windows) (auto-downloads Windows ISO + runs unattended setup) on top of Hetzner Cloud (TCG, cheap) or Vultr Bare Metal (KVM, fast). Every tool installs via mise — no compilers, no curl-piped installers. Cross-platform: lifecycle + RDP layer dispatch on `$nu.os-info.name` (macOS via Homebrew + `open`; Linux via xfreerdp/remmina + `xdg-open`; Windows via the built-in `mstsc.exe`). Generic — any Windows software fits. Sibling [vm-software](https://github.com/joeblew999/vm-software) holds per-app install recipes.

## Quick start → the GUI

```sh
mise install                 # tools: hcloud, vultr-cli, aws, fnox, nushell, pitchfork, http-nu, xs, yoke
mise run token:set           # paste your Hetzner API token (one-time per machine)
mise run up                  # pitchfork starts xs + gui → http://127.0.0.1:8080
```

`mise run up` brings both daemons (xs event bus, gui web server) under pitchfork supervision. They survive your shell, restart on crash, log to pitchfork's store. `mise run down` stops both. `mise run jobs` shows what's running (same as `pitchfork list`).

Each Start/Stop/Snapshot button POSTs to a mise task that itself runs as a pitchfork daemon — they appear in the **Jobs** section of the gui (and in `pitchfork list`) until they complete. So you always know what's happening, and `pitchfork logs <name>` tails any of them.

Then in the browser at **http://127.0.0.1:8080**:

| Section | What you see | Live? |
|---|---|---|
| **VMs** | Current state of every VM the lifecycle has touched (label, provider, last action, IP, installs count) | yes — Datastar polls every 5 s |
| **Actions** | **Start**, **Stop**, **Snapshot**, **Refresh status** buttons. Each POSTs to a mise task spawned as a pitchfork daemon | response shown inline in the action pane |
| **Jobs** | Live `pitchfork list` — every running daemon (gui, xs, and per-action vm-action-*) | yes — Datastar polls every 5 s |
| **Snapshots** | Live list from the active provider's API (id, description, size, created) | on page load (no API hammer) |
| **Runs** | One row per provision→destroy pair, with duration_hr and sku — derived from `vms.jsonl` | on page load |
| **Costs** | Provider/SKU pricing reference from `state/costs.jsonl` so you know what an action costs before clicking | static |
| **Live events** | Documents the `xs cat --follow` command for tailing the event bus | (v1 todo: Datastar SSE merge) |
| **Recent installs** | Joined from sibling vm-software's `state/installs.jsonl` | on page load |

Buttons fire-and-forget; the lifecycle runs in the background (output appended to `/tmp/gui-action.log`) and progress lands in `state/vms.jsonl` which the VMs table re-renders within seconds.

## CLI (the same surface, for scripting + power users)

Every button is also a mise task — call them from a terminal, a script, or CI:

```sh
mise run start            # provision (from snapshot if any) → wait for RDP → open client
mise run push -- <path>   # copy a local file into the VM at \\host.lan\Data
mise run pull -- <name>   # copy a file out
mise run stop             # snapshot → prune older → destroy VM
mise run vm:status        # what's running right now (live from provider)
mise tasks                # ~50 more (vm:*, snapshot:*, debug:*, vultr:*, rdp:*, ci:*, runs:*, ai:ask, ...)
```

## AI driver (yoke + MCP)

```sh
mise run ai:ask -- "is my vm running? if not, start it from the latest snapshot"
mise run mcp:serve        # stdio MCP server — point Claude Desktop / Claude Code at it
```

Both invoke the same mise tasks the buttons and CLI do. **Three surfaces, one execution layer.**

## Providers

`VM_PROVIDER` env (`"hetzner"` default, `"vultr"`) routes every dispatch. To switch to Vultr Bare Metal, set `VM_PROVIDER = "vultr"` in `mise.local.toml`, run `mise run vultr:setup`, then `mise run r2:bootstrap` (R2 is the snapshot transit bucket since Vultr has no hot-snapshot).

## Layout

```
mise.toml                   # all tasks (single surface — same for gui / CLI / MCP / yoke)
fnox.toml                   # secret pointer table (keychain-backed)
cloud-init/                 # qemu.yaml + kvm.yaml (host bootstrap) + oem.bat (Windows OEM hook)
gui/                        # browser front end (http-nu + Datastar + pico CSS) — the primary UX
providers/{hetzner,vultr}/  # provider-specific .nu implementations (called by lifecycle/dispatch.nu)
lifecycle/                  # start, stop, dispatch (orchestrators behind the Start/Stop buttons)
connect/                    # rdp:* + viewer:open (connect to running VM, cross-platform)
files/                      # push / pull / files:ls
debug/                      # debug:ssh / probe / logs / metrics / version / host-disk
deps/                       # deps:check (provider tools + token sanity)
r2/                         # R2 bootstrap + sanity check (snapshot transit)
mcp/                        # init.nu hook for mcp:serve + ai:ask
ci/                         # syntax / schema / dispatch checks (same as GH Actions)
state/                      # vms.jsonl + vms.schema.json + runs.nu view + costs.jsonl
```

See [CLAUDE.md](CLAUDE.md) for design decisions (including the v1 writes / v2 auth / xs+iroh phases).
