# revit-vm

Spin up a remote Windows VM on Hetzner Cloud, driven entirely by `mise run` tasks. Built on [dockur/windows](https://github.com/dockur/windows) — auto-downloads the Windows ISO, runs unattended setup, exposes a web viewer on port 8006 and RDP on 3389. Mac is the control plane.

Generic pipeline — any Windows software fits. The first/main target is Autodesk Revit; see **[REVIT.md](REVIT.md)** for that specific workflow, costs, and constraints.

## Daily workflow — four commands

```
mise run start            # resume work: provision (from latest snapshot if any), wait for Windows, open RDP
mise run push -- foo.txt  # send a file from Mac → VM, appears in Windows at \\host.lan\Data\foo.txt
mise run pull -- foo.txt  # pull \\host.lan\Data\foo.txt → current dir on Mac
mise run stop             # end work: snapshot, prune older snapshots, destroy VM (cost meter off)
```

That's it. `start` is ~90s when a snapshot exists, ~1hr the very first time (Windows install). `stop` always preserves state — `start` next time picks up where you left off.

### What it costs — pick by usage

**The current `vm:up` (TCG / no KVM, cpx42):**

| You use it | You pay |
|---|---|
| A few hours total (trying it out, one trial install) | **~€1** |
| ~10 hr / week (couple of sessions, then `stop`) | **~€3 / mo** |
| ~50 hr / week | **~€10 / mo** |
| Left it running 24×7 by accident | **~€28 / mo** (Hetzner caps here) |
| Snapshot kept, VM destroyed | **+€0.48 / mo** flat (add to any row above) |

**If you want native KVM speed (eventual production):**

| Option | Cost | Commitment | Provisioning |
|---|---|---|---|
| **Hetzner Dedicated AX41-NVMe** (`vm:up-kvm`) | **€39 / mo flat**, ~10× faster than cpx42 | 30-day minimum (full-month bill even if you use it briefly) | hours, sometimes manual via Hetzner Robot panel + occasional €39 one-off setup fee |
| **Vultr Bare Metal E2.med** | **€0.12 / hr** (~€83/mo always-on), native KVM | hourly, no minimum | minutes via API — burst alternative to Hetzner Dedicated |
| **Local Linux box** you already own | **€0**, native KVM | n/a | already there; needs a residential IP |

**Rules of thumb:**

- **Under ~20 hr/week, bursty, no commitment** → `cpx42` (TCG), €1–5/mo. Daily use cpx42 wins on price even if you wish it were faster.
- **You need speed AND you'll use it most of a month** → Hetzner Dedicated AX41, €39/mo. The €11 premium over cpx42-24×7 buys ~10× the throughput.
- **You need speed but only for a few days at a time** → Vultr Bare Metal hourly, €0.12/hr. Worse than AX41 if you'll use it most of the month, better if you won't commit.
- **You already own a Linux box** → just use it. €0.

App-specific costs (Revit subscription, etc.) are a separate line — see [REVIT.md](REVIT.md). For Revit specifically, the €428/mo subscription dwarfs every option in the tables above.

Detailed price tables below if you want to do the arithmetic yourself.

### First-time setup (once per machine)

```
mise install              # pulls hcloud + fnox via mise
mise run token:set        # paste Hetzner API token at hidden prompt (stashed in macOS keychain)
mise run start            # first run does the ~1hr Windows install; subsequent runs are ~90s
```

**RDP login**: user `Docker`, password `admin` (dockur defaults — `mise run rdp:open` prefills the username; type the password when the client asks).

**Optional local overrides** in `mise.local.toml` (gitignored — copy from `mise.local.toml.example`). Per-app — see the app's own doc (`REVIT.md`, etc.).

### Adding software

Public free downloads (Revit Batch Processor, Notepad++, 7-Zip, dev tools, …):
- Add a line to `installers.txt`, then `mise run software:fetch` — VM downloads them into the shared folder.

Per-account auth'd installers (Revit, AutoCAD, Adobe CC, …):
- Download to your Mac, then `mise run push -- ~/Downloads/Installer.exe`. For app-specific automation (e.g. fetching directly from a vendor URL), see the app's doc (`REVIT.md` for Revit).

After installing inside Windows, `mise run stop` snapshots the new state so it survives forever.

### Snapshot retention

`mise run stop` snapshots before destroying the VM, and `snapshot:prune` deletes everything except the newest one. That keeps the bill at ~€0.48/mo idle. The downside: if your *newest* snapshot is broken (e.g. a Windows update corrupted something inside the VM), you've already pruned the previous good copy.

If you want a safety net, pre-set the retention before stopping:

```
SNAPSHOTS_KEEP=3 mise run stop     # keeps newest 3 instead of 1 — costs ~€1.44/mo idle
```

Or run prune standalone whenever:

```
mise run snapshot:list                       # see what's there
SNAPSHOTS_KEEP=3 mise run snapshot:prune     # one-shot adjust retention
```

Cost is linear: each retained ~40 GB snapshot is ~€0.48/mo. N=3 is a reasonable default once you have real work that you'd hate to lose.

### Reference — all tasks

`mise tasks` lists them grouped by noun (`vm:*`, `snapshot:*`, `rdp:*`, `software:*`, `files:*`, `token:*`, `trial:*`, `viewer:*`). The four top-level ones (`start`, `stop`, `push`, `pull`) compose them. Granular tasks are there for when you want explicit control (snapshot without destroying, change restart policy, etc.). `debug:*` tasks are for troubleshooting only.

## Costs

All prices are Hetzner Cloud retail, EUR, including 19% VAT. Hourly billing, billed only while the resource exists.

### Compute (VM running)

| Server type | vCPU | RAM | Disk | €/hr | €/mo if left running 24×7 |
|---|---|---|---|---|---|
| `cpx42` (current default) | 8 shared AMD | 16 GB | 320 GB | **0.0449** | ~28.04 |
| `cpx52` | 12 | 24 GB | 480 GB | 0.0644 | ~40.14 |
| `cpx62` | 16 | 32 GB | 640 GB | 0.1029 | ~64.21 |

Bursty use is the intended pattern — `start` → work → `stop`. A typical evaluation session burns ~2 hours of VM time (~€0.09).

### Storage (always-on, even with VM destroyed)

| Resource | Rate | Realistic monthly |
|---|---|---|
| Snapshot (typical Windows install ≈ 40 GB used) | €0.012/GB/mo | ~€0.48 |
| Volume (if used for persistent shared storage instead of host disk) | €0.044/GB/mo | ~€2.20 for 50 GB |
| Outbound traffic | €1/TB after 20 TB free | basically free at this workload |

### Software

| Component | Cost |
|---|---|
| Windows 11 (downloaded by dockur from Microsoft, runs without product key in evaluation mode) | €0 |
| dockur/windows container image | €0 (MIT-licensed, public Docker Hub) |
| Application costs (Revit, AutoCAD, etc.) | see per-app doc (`REVIT.md`, …) |

## Performance reality

The Hetzner cpx VMs **don't expose nested virtualisation**, so dockur runs Windows under QEMU/TCG software emulation. Expect:

- ~10× slower CPU than a native Windows install on equivalent hardware
- No GPU acceleration — apps fall back to Microsoft's software rasterizer (WARP)
- Real graphics-heavy work (CAD viewports, 3D rendering) on real-size projects = not viable here
- Pipeline verification + small-data batch jobs = viable but slow

For real production performance you need either Hetzner Dedicated Root Server (bare-metal, restores KVM, monthly billing) or another cloud's bare-metal SKU. Per-app advice in the app's doc.

## Files in this repo

| File | Purpose |
|---|---|
| `mise.toml` | All tasks, env, tool pins. Entry point. |
| `mise.local.toml.example` | Template for per-account/per-app secrets (gitignored when copied to `mise.local.toml`). |
| `fnox.toml` | Maps `HCLOUD_TOKEN` keychain item → env var for mise tasks |
| `cloud-init-qemu.yaml` | Host bootstrap for Hetzner Cloud (KVM disabled, TCG emulation) |
| `cloud-init-kvm.yaml` | Host bootstrap for KVM-capable hosts (Hetzner Dedicated, other clouds, local) |
| `installers.txt` | Declarative list of public Windows installers to stage in the shared folder |
| `oem/install.bat` | Auto-runs ONCE inside Windows at the end of the unattended install on a fresh `vm:up`. Maps Z: → `\\host.lan\Data`, extracts RBP, sets Defender exclusions, disables sleep. Skipped by `vm:up-snap` (snapshot is past that point). |
| `windows-scripts/install-revit.bat` | Revit-specific helper. See `REVIT.md`. |
| `REVIT.md` | Autodesk Revit specifics: trial workflow, sign-in, conversion, perf, costs. |
| `CLAUDE.md` | Context for Claude Code (and any other agent): decisions made, lessons learned, rules. |

## Don't

- Don't put account-tied URLs or trial dates in `mise.toml` — those go in `mise.local.toml` (gitignored).
- Don't run `mise run vm:up-kvm` on Hetzner Cloud — it will fail. Hetzner Dedicated and other bare-metal hosts only.
- App-specific rules (e.g. Autodesk sign-in handling) live in the app's own doc.
