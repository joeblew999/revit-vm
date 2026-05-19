# revit-vm

Spin up a remote Windows VM that runs Autodesk Revit on Hetzner Cloud, driven entirely by `mise run` tasks. Built on [dockur/windows](https://github.com/dockur/windows) — auto-downloads the Windows ISO, runs unattended setup, exposes a web viewer on port 8006 and RDP on 3389.

## Daily workflow — four commands

```
mise run start            # resume work: provision (from latest snapshot if any), wait for Windows, open RDP
mise run push -- foo.txt  # send a file from Mac → VM, appears in Windows at \\host.lan\Data\foo.txt
mise run pull -- foo.txt  # pull \\host.lan\Data\foo.txt → current dir on Mac
mise run stop             # end work: snapshot, prune older snapshots, destroy VM (cost meter off)
```

That's it. `start` is ~90s when a snapshot exists, ~1hr the very first time (Windows install). `stop` always preserves state — `start` next time picks up where you left off.

### Cost at a glance

| State | Burn rate |
|---|---|
| VM running (`start` → working → no `stop` yet) | **€0.045 / hr** (cpx42 fsn1) |
| VM stopped, snapshot kept (`stop` complete) | **€0.48 / mo** (one ~40 GB snapshot) |
| Whole 30-day trial-eval cycle, realistic use | **~€1 total** |
| Production with paid Revit (~€428/mo subscription dwarfs everything else) | **~€436 / mo** |

Full breakdown + worked examples in the [Costs](#costs) section below.

### First-time setup (once per machine)

```
mise install              # pulls hcloud + fnox via mise
mise run token:set        # paste Hetzner API token at hidden prompt (stashed in macOS keychain)
mise run start            # first run does the ~1hr Windows install; subsequent runs are ~90s
```

**RDP login**: user `Docker`, password `admin` (dockur defaults — `mise run rdp:open` prefills the username; type the password when the client asks).

**Optional local overrides** in `mise.local.toml` (gitignored — copy from `mise.local.toml.example`):
- `REVIT_INSTALLER_URL` — your per-account Autodesk download URL, used by `mise run software:fetch-revit`
- `TRIAL_STARTED` — ISO date, makes `mise run trial:remind` count down to expiry

### Adding software

Public free downloads (RBP, Notepad++, 7-Zip, dev tools):
- Add a line to `installers.txt`, then `mise run software:fetch` — VM downloads them into the shared folder.

Per-account auth'd installers (Revit, AutoCAD, Adobe CC):
- Download to your Mac, then `mise run push -- ~/Downloads/Installer.exe`. Or for Revit specifically, put your account-tied URL in `mise.local.toml` and use `mise run software:fetch-revit` (VM-side download, ~10× faster than home upload).

After installing inside Windows, `mise run stop` snapshots the new state so it survives forever.

### Snapshot retention

`mise run stop` snapshots before destroying the VM, and `snapshot:prune` deletes everything except the newest one. That keeps the bill at ~€0.48/mo idle. The downside: if your *newest* snapshot is broken (e.g. a Windows update corrupted something inside the VM), you've already pruned the previous good copy.

If you want a safety net, pre-set the retention before stopping:

```
SNAPSHOTS_KEEP=3 mise run stop     # keeps newest 3 instead of 1 — costs ~€1.44/mo idle
```

Or run prune standalone whenever:

```
mise run snapshot:list              # see what's there
SNAPSHOTS_KEEP=3 mise run snapshot:prune    # one-shot adjust retention
```

Cost is linear: each retained ~40 GB snapshot is ~€0.48/mo. N=3 is a reasonable default once you have real work that you'd hate to lose.

### Reference — all tasks

`mise tasks` lists them grouped by noun (`vm:*`, `snapshot:*`, `rdp:*`, `software:*`, `files:*`, `token:*`, `trial:*`, `viewer:*`). The four top-level ones (`start`, `stop`, `push`, `pull`) compose them. Granular tasks are there for when you want explicit control (snapshot without destroying, change restart policy, etc.).

## Costs

All prices are Hetzner Cloud retail, EUR, including 19% VAT. Hourly billing, billed only while the resource exists.

### Compute (VM running)

| Server type | vCPU | RAM | Disk | €/hr | €/mo if left running 24×7 |
|---|---|---|---|---|---|
| `cpx42` (current default) | 8 shared AMD | 16 GB | 320 GB | **0.0449** | ~28.04 |
| `cpx52` | 12 | 24 GB | 480 GB | 0.0644 | ~40.14 |
| `cpx62` | 16 | 32 GB | 640 GB | 0.1029 | ~64.21 |

The trial pipeline runs entirely in bursts — `vm:up` → work → `snapshot:create` → `vm:down`. A typical "install Revit, prove the pipeline" session burns ~2 hours of VM time (~€0.09).

### Storage (always-on, even with VM destroyed)

| Resource | Rate | Realistic monthly |
|---|---|---|
| Snapshot (typical Windows + Revit ≈ 40 GB used) | €0.012/GB/mo | ~€0.48 |
| Volume (if used for persistent shared storage instead of host disk) | €0.044/GB/mo | ~€2.20 for 50 GB |
| Outbound traffic | €1/TB after 20 TB free | basically free at this workload |

### Software

| Component | Cost |
|---|---|
| Windows 11 (downloaded by dockur from Microsoft, runs without product key in evaluation mode) | €0 |
| dockur/windows container image | €0 (MIT-licensed, public Docker Hub) |
| Revit Batch Processor (open-source, github.com/bvn-architecture/RevitBatchProcessor) | €0 |
| Autodesk Revit — 30-day trial | €0, single account, no renewal scripting |
| Autodesk Revit — paid subscription after trial | €428/mo or €3,431/yr (1-user, list price; AEC Collection ~€3,400/yr) |

### Worked examples

**Trial evaluation, single 30-day window:**
- Provision + Windows install + Revit install + snapshot: ~3 hr × €0.0449 ≈ **€0.13**
- 10 follow-up sessions of 1 hr each: 10 × €0.0449 ≈ **€0.45**
- Snapshot sitting idle for 30 days: 40 GB × €0.012 ≈ **€0.48**
- **30-day trial total: ~€1.06 + your time + €0 Autodesk**

**Production batch-processing (post-trial, paid Revit):**
- 5 batch sessions/week × 2 hr × €0.0449 = €1.80/week → ~€7.80/mo VM
- Snapshot idle: ~€0.50/mo
- Revit subscription: ~€428/mo
- **Monthly: ~€436** — Revit dwarfs everything else

If batch volume grows past a few sessions a day, look at **Autodesk Platform Services (APS) Design Automation for Revit** — server-side headless Revit billed per cloud-credit. Likely cheaper than running your own VM for production scale.

## Performance reality

The Hetzner cpx VMs **don't expose nested virtualisation**, so dockur runs Windows under QEMU/TCG software emulation. Expect:

- ~10× slower CPU than a native Windows install on equivalent hardware
- No GPU acceleration — Revit falls back to Microsoft's software rasterizer
- Real Revit work on real-size models = not viable here
- Pipeline verification + small-model batch jobs = viable but slow

For real production performance you need either Hetzner Dedicated Root Server (bare-metal, restores KVM, monthly billing), another cloud's bare-metal SKU, or APS Design Automation.

## Files in this repo

| File | Purpose |
|---|---|
| `mise.toml` | All tasks, env, tool pins. Entry point. |
| `mise.local.toml.example` | Template for per-account secrets (Revit installer URL, trial start date). Copy to `mise.local.toml` (gitignored). |
| `fnox.toml` | Maps `HCLOUD_TOKEN` keychain item → env var for mise tasks |
| `cloud-init-qemu.yaml` | Host bootstrap for Hetzner Cloud (KVM disabled, TCG emulation) |
| `cloud-init-kvm.yaml` | Host bootstrap for KVM-capable hosts (Hetzner Dedicated, other clouds, local) |
| `installers.txt` | Declarative list of public Windows installers to stage in the shared folder |
| `windows-scripts/install-revit.bat` | Silent-install template run from inside Windows |
| `oem/install.bat` | Auto-runs ONCE inside Windows at the end of the unattended install on a fresh `vm:up`. Maps Z: → `\\host.lan\Data`, extracts RBP, sets Defender exclusions, disables sleep, silent-installs Revit if `Revit_Installer.exe` is staged. Skipped by `vm:up-snap` (snapshot is past that point) — so daily use never re-runs it. Greenfield rebuilds are turn-key. |

## Don't

- Don't put account-tied URLs or trial start dates in `mise.toml` — those go in `mise.local.toml` (gitignored).
- Don't run `mise run up-kvm` on Hetzner Cloud — it will fail. Hetzner Dedicated and other bare-metal hosts only.
- Don't try to bypass Autodesk's per-trial sign-in by injecting harvested credential stores. Use the trial legitimately, then convert to paid; or skip Revit entirely and use APS.
