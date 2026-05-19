# Context for Claude Code

For agents (and humans) working on this repo. Read it before answering questions or writing code. **Then read [README.md](README.md)** for the daily-use surface, [REVIT.md](REVIT.md) for the headline app, [SERVICE.md](SERVICE.md) for the convert-on-demand SaaS design that's not built yet.

This file is for *why* and the rules that aren't visible in code. It's the place to capture decisions already made so they don't get re-litigated every session.

## What this repo is

A `mise`-driven toolchain that stands up a Hetzner Cloud VM running Windows inside [dockur/windows](https://github.com/dockur/windows), so arbitrary Windows software can be installed there and used for **batch processing** from a Mac. The Mac is the control plane; everything happens via `mise run <task>`.

The mechanism is generic — any Windows software fits. The headline app is Autodesk Revit (see [REVIT.md](REVIT.md)); a forward-looking service architecture that extends to multiple apps is sketched in [SERVICE.md](SERVICE.md).

Today's owner goals:
- A 30-day **trial-first** Revit evaluation (proof the pipeline works end-to-end).
- A path to convert to a **paid Revit subscription** if/when the pipeline is worth it.
- Minimal cognitive load — daily use is 4 commands (`start`, `stop`, `push`, `pull`).
- A snapshot-based persistence model so each session doesn't redo the ~1 hr Windows install.

## Architectural decisions already made (do not re-litigate without strong reason)

1. **Hetzner Cloud + dockur/windows + TCG software emulation.** Not bare metal (yet), not Forge / Autodesk Platform Services (yet). Hetzner Cloud is the cheapest viable cloud and its hourly billing matches bursty batch use. Cost reality is in README.

2. **No KVM on Hetzner Cloud — verified live 2026-05-18.** `/proc/cpuinfo` exposes neither `vmx` nor `svm`; `modprobe kvm_amd` returns `Operation not supported`; `/dev/kvm` does not exist; dockur container with `--device=/dev/kvm` hangs in `Created` state. **This is platform-wide across shared (cpx*) and dedicated CPU (ccx*) tiers — not a per-SKU thing.** The workaround is `-e KVM=N` (forces QEMU/TCG); dockur maintainer kroese in [dockur/windows#706](https://github.com/dockur/windows/issues/706) describes TCG as "much too slow for any practical purpose" — fine for pipeline validation, not for real Revit work.

3. **Two cloud-init variants, not one.** `cloud-init-qemu.yaml` (TCG, `KVM=N`, no `--device=/dev/kvm`) is the Hetzner Cloud default. `cloud-init-kvm.yaml` exists for when this repo eventually points at a host that DOES expose KVM (Hetzner Dedicated Root via Robot API, other clouds' bare-metal, local KVM box). Never run `vm:up-kvm` against Hetzner Cloud — it will fail at `docker run`.

4. **Snapshot-based persistence, not OEM-only and not session-token replay.**
   - The slow part is the first Windows install (~1 hr in TCG). After that, `snapshot:create` captures the full state (Windows + dockur container with `--restart=always` + shared folder + signed-in Revit if you got that far). `vm:up-snap` restores in ~90 s.
   - Token-injection schemes that copy a harvested `Identity Services` directory across throwaway VMs to extend trials indefinitely are **out of scope**. The user agreed: legitimate 30-day trial → snapshot → convert to paid.

5. **fnox + mise pattern for secrets.** Same as `scrapers-proxy` / `trade-fairs`. `fnox.toml` is a pointer table that maps env-var names (e.g. `HCLOUD_TOKEN`) to keychain item names; `mise run set-token` seeds the keychain; tasks invoke commands via `fnox exec --` so the env vars are injected at run time. **Write secrets via `fnox set -p keychain <KEY>`** — without `-p keychain` they land plaintext in `fnox.toml`.

6. **Per-Hetzner-project isolation.** A dedicated `revit-vm` Hetzner project, separate from other projects on the same account. Standing pattern in [memory: "Cloud project per repo, fnox item per repo"](https://github.com/joeblew999/revit-vm). Blast radius — a script bug or token leak only affects this project's resources.

7. **Per-account vs. public installers split.** `installers.txt` is for PUBLIC free downloads (Revit Batch Processor, eventually 7-Zip / Notepad++ / dev tools). Per-account auth'd installers (Revit, AutoCAD, Adobe CC) are NEVER in `installers.txt` — they go via `mise run push -- <local-path>` after the user downloads them on their Mac, OR via `mise run software:fetch-revit` which reads a per-account URL from `mise.local.toml` (gitignored).

8. **`mise.local.toml` for per-account overrides.** Gitignored. Holds `REVIT_INSTALLER_URL`, `TRIAL_STARTED`, anything else that's machine- or account-specific. `mise.local.toml.example` is the committed template. Don't put these values directly in `mise.toml` and don't put them in fnox (they're configuration, not secrets in the credential sense).

9. **`--restart=always` on the dockur container, not `unless-stopped`.** With `unless-stopped`, a snapshot taken while the container was explicitly stopped won't auto-start on restore. `always` triggers restart on every Docker daemon start (which happens on every VM boot), so `vm:up-snap` boots into a running Windows with no manual intervention.

10. **`oem/install.bat` for first-boot Windows automation.** dockur's documented `/oem` hook: anything mounted at `/oem` is copied to `C:\OEM` and `install.bat` runs as Admin during the LAST step of the unattended Windows install. Fires once, before any human logs in. Greenfield `vm:up` therefore lands on a fully-configured VM (Z: drive mapped, RBP extracted, Defender exclusions set, sleep disabled). **It does NOT re-run on `vm:up-snap`** — the snapshot is already past that point — so daily use never re-runs it. Treat it as the rebuild-from-scratch path.

11. **Four-command daily UX is the target.** `start` / `stop` / `push` / `pull` cover 99% of work. Everything else (`vm:*`, `snapshot:*`, `rdp:*`, `software:*`, `files:*`, `viewer:*`, `token:*`, `trial:*`) is granular control or one-time setup. `debug:*` is for when something's wrong — neither you nor the user types those in normal use.

12. **(Future) Operations are Rust crates, not loose scripts.** When SERVICE.md gets built out, each operation (`<app>/<op>`) is a small Rust crate cross-compiled from Mac to `x86_64-pc-windows-msvc`, producing a `.exe` baked into the VM snapshot. Vendor-side companion scripts (IronPython for Revit's RBP, `.scr` for AutoCAD) live alongside the Rust source. The IronPython case is the only sanctioned exception to the "Rust + Bash, no Python" rule — RBP forces it. See [SERVICE.md](SERVICE.md) → "Three layers per job."

13. **(Future) Observability is mandatory, not optional.** Every operation `.exe` must emit structured `tracing` events to a Cloudflare ingest Worker as it runs. Jobs are slow and async; without per-job event streams, the only way to debug a failed Revit job is RDP-ing into the VM and grepping by hand — doesn't scale. A shared `obs/` crate lives in the operations workspace; every operation imports it. The ingest Worker writes events to Workers Logs (matches the `scrapers-proxy` observability pattern) and a Durable Object per `job_id` for live status. See [SERVICE.md](SERVICE.md) → "Observability." This is step 1 of the build order, not an afterthought.

## When does Windows reinstall? (the answer is "almost never")

This trips people up because the ~1 hr Windows install is intimidating. The truth is simple:

| Trigger | Windows reinstall? |
|---|---|
| `mise run start` and a snapshot exists | **NO** — `vm:up-snap` restores the snapshot disk-for-disk, ~90s |
| `mise run start` and zero snapshots exist | YES — falls through to `vm:up` (greenfield) |
| Any edit to `cloud-init-*.yaml`, `oem/install.bat`, `mise.toml`, etc. | **NO** — code changes affect only the greenfield path; the snapshot is a frozen disk image and doesn't care |
| `hcloud image delete <id>` or excessive `snapshot:prune` retention | YES on the next `vm:up` |

**Default `snapshot:prune` keeps the newest 1**. The only way to lose the Windows install accidentally is to delete the snapshot manually OR drop retention below the current count. Set `SNAPSHOTS_KEEP=3` once you have real work to preserve.

When in doubt before any destructive-sounding action: `mise run snapshot:list` should show at least one row. If it does, you can't accidentally trigger a reinstall.

## Considered and rejected

- **`docker-compose.yml` instead of inline `docker run` in cloud-init.** Pros: validated YAML schema, profiles (one file replaces both cloud-init variants), healthcheck on port 8006 for "wedged Windows" detection, sidecar headroom. Cons: zero change to daily UX, current snapshot is `docker run`-managed and would either stay that way or need an in-place container swap to migrate. Decision: not worth the churn while the current setup works. Revisit IF/WHEN: (a) we want healthchecks for TCG-hung-Windows auto-recovery, (b) we add a sidecar (Caddy auth in front of 8006, snapshot watcher, etc.), or (c) flag edits on dockur become frequent. Until then, the inline `docker run` is fine.

## Hard-won lessons (live-fire scars from building this)

- **Hetzner deprecates SKUs in specific datacenters.** `cpx41` was retired in `fsn1` mid-2026; `cpx42` is the same-spec successor (8c / 16 GB / 320 GB AMD shared, ~€0.045/hr).
- **Hetzner snapshots bill on `image_size` (used data), not `disk_size` (provisioned).** `snapshot:list` surfaces `image_size`. ~40 GB used for a Windows + RBP install = ~€0.48/mo per retained snapshot.
- **Hetzner reuses project-allocated IPv4 across `vm:up`/`vm:down` cycles**, but each fresh VM has new SSH host keys → `StrictHostKeyChecking` blows up. `vm:up*` tasks now end with `ssh-keygen -R "$IP"` to clear the stale entry. Don't remove this.
- **`mise run task arg` does NOT substitute `$1` in the run block — mise APPENDS args literally to the run line.** To accept positional args, wrap the script in a shell function and call `func "$@"` at the end, then invoke as `mise run task -- arg1 arg2`. The `push`/`pull` tasks follow this pattern.
- **mise renders task scripts through tera templating before execution.** `{{...}}` patterns (e.g. docker's `--format '{{.Status}}'`) are interpreted as tera variables and blow up. Wrap in `{% raw %}...{% endraw %}` to pass them through.
- **dockur defaults for Windows login: user `Docker`, password `admin`.** Not empty (older versions had empty). `mise run rdp:open` prefills the username; type `admin` when the client asks.
- **dockur logs say "Nested KVM virtualization detected" even in TCG mode.** Ignore — it's a misleading log line. The earlier `Warning: KVM acceleration is disabled, this will cause the machine to run about 10 times slower!` is the truth.
- **`docker stop --timeout=120` is the right "clean shutdown" signal**, not 10s (default). dockur translates SIGTERM into ACPI shutdown to Windows; Windows wants up to 60-90s to flush. Use 120s as headroom.
- **Sub-mise processes are fine.** `start` and `stop` invoke `mise run vm:up-snap` etc. inside their run blocks. Slightly slower than inlining but keeps the composition DRY and each step independently invokable + testable. User-confirmed pattern.
- **`set -e` in composite tasks.** Without it, a failed snapshot:create still ran vm:down and destroyed the VM. Now: any mid-pipeline failure aborts the rest. **Don't remove from `start` or `stop`.**
- **The `/oem/install.bat` mechanism has reports of recent flakiness** ([dockur/windows#1433](https://github.com/dockur/windows/issues/1433)) where commands silently get skipped. Log everything to `C:\OEM\install.log` (which is accessible via `Z:\install.log` from the host) so you can see what actually ran. The current `oem/install.bat` does this.
- **`hcloud server create-image` takes the server name POSITIONALLY**, not via `--server`. `--server` worked in older hcloud CLI versions but was removed. Current invocation in `snapshot:create`: `hcloud server create-image --type snapshot --description "..." "$SERVER_NAME"`.
- **`workspace:ls` was renamed to `files:ls`** during the UX collapse to 4 daily commands. `files:ls` now uses `find` instead of listing only 3 hardcoded subdirs, so top-level files (like `install-revit.bat`) show up too.
- **Hot snapshot of running TCG Windows is unbounded.** `mise run stop` previously called `snapshot:create` on a running VM and ate 40+ min when Windows was actively writing dirty pages under QEMU/TCG. Caught live 2026-05-19. Fix: `stop` now does `docker stop --timeout=120 windows_batch_processor` over SSH FIRST, then snapshots a quiescent disk (~60s). Standalone `snapshot:create` stays hot (its docstring already warned to shut Windows down first); `stop` automates the shutdown. **Don't remove the clean-shutdown step from `stop`** — putting it back to hot snapshot is a 40-min landmine.

## Stack details

- **Tools (mise-pinned in `mise.toml`):** `hcloud` 1.64.1, `fnox` 1.19.0.
- **Host VM:** Hetzner `cpx42` in `fsn1` by default (`mise.toml [env]`). Ubuntu 24.04 image. SSH key `gedw99_hetzner` uploaded to the project; private key at `~/.ssh/gedw99_hetzner`.
- **Container:** `dockurr/windows:5.15` — pinned in both cloud-init files. Restart policy `always`. To check what's running vs. what's available, `mise run debug:version`. Bump the tag in both cloud-init files when you want to upgrade (and take a fresh snapshot afterwards so `vm:up-snap` picks up the new version).
- **Windows VM (inside dockur):** Windows 11 (whatever Microsoft serves at first install). 6 vCPU, 12 GB RAM, 64 GB growable virtual disk. Leaves ~2 cores / 4 GB RAM for the host.
- **Ports exposed:** 8006 (dockur web viewer, no auth — fine for evaluation, would need protection for production), 3389 TCP+UDP (RDP).
- **Shared folder:** `/root/windows_shared` on the host = `/data` in the container = `\\host.lan\Data` in Windows (after `oem/install.bat` maps it to `Z:`). Subdirs: `installers/`, `jobs/`, `output/`.
- **OEM folder:** `/root/oem` on the host = `/oem` in the container = `C:\OEM` in Windows. Contains `install.bat`, pulled from this repo's raw GitHub URL at cloud-init time.

## Things to know going in

- **Performance reality:** Hetzner Cloud + TCG runs Windows ~10× slower than native. Revit will launch and a small test model will load. Real-size models will swap to disk and stall. **This setup is for pipeline validation, not production work.** Production paths (Hetzner Dedicated bare metal, GPU clouds, APS Design Automation) are documented in README.
- **First provision ≠ subsequent ones.** Greenfield `vm:up` takes ~1 hr (Windows ISO download + install + `oem/install.bat`). `vm:up-snap` takes ~90 s. Always prefer the snapshot path once one exists.
- **Trial state lives in the snapshot.** Sign into Revit's trial ONCE inside Windows during the first usable session. `snapshot:create` then captures the signed-in state; every future `vm:up-snap` boots into a Revit that's already signed in. **There is no trial-token-refresh trick** — when 30 days are up, convert to a paid account inside the same Windows install (sign in with new account in Revit, re-snapshot).
- **Default snapshot retention is N=1** (set via `SNAPSHOTS_KEEP`). Cheapest but offers no rollback. Set to 3 once you have real work that you'd hate to lose: `SNAPSHOTS_KEEP=3 mise run stop`.
- **`mise.local.toml` is mandatory for some tasks.** Without it, `software:fetch-revit` and `trial:remind` error cleanly with instructions. Copy from `mise.local.toml.example`.

## Don't

- Don't propose Python anywhere — user's standing rule (Rust + Bash only). Single sanctioned exception: IronPython inside a Revit operation crate (RBP only takes Python). Document any new exception, don't widen the rule.
- Don't propose token-injection / trial-cycling / harvested-credential-replay schemes for Autodesk. Refused once, will be refused again.
- Don't put per-account values (Revit installer URL, trial start date) in `mise.toml` — they go in `mise.local.toml` (gitignored).
- Don't put Revit installer download into `cloud-init-*.yaml` — multi-GB downloads in bootstrap turn `vm:up` into a coin-flip. Stage Revit via `software:fetch-revit` (host curl, parallel to Windows install) or `push` (Mac upload).
- Don't change `--restart=always` back to `unless-stopped` — breaks `vm:up-snap`.
- Don't remove `ssh-keygen -R` from the `vm:up*` tasks — breaks every subsequent SSH-using task on a re-provisioned VM.
- Don't remove `set -e` from `start` / `stop` — restores the "VM destroyed without saving state" data-loss risk.
- Don't add a per-installer mise task for every new piece of Windows software. The pattern is: free public → line in `installers.txt` + `software:fetch`; auth'd → `push` from Mac. New ad-hoc tasks are a smell.
- Don't run anything that requires Hetzner Dedicated / bare-metal billing without checking with the user — those are monthly contracts, not hourly.
- Don't `git commit` or `git push` without explicit user approval (standing memory rule).
