# revit-vm

Spin up a remote Windows VM that runs Autodesk Revit on Hetzner Cloud, driven entirely by `mise run` tasks. Built on [dockur/windows](https://github.com/dockur/windows) — auto-downloads the Windows ISO, runs unattended setup, exposes a web viewer on port 8006 and RDP on 3389.

## Workflow at a glance

```
mise run token:set              # one-time: stash Hetzner API token in keychain
mise run vm:up                  # provisions cpx42 in fsn1, starts cloud-init
mise run rdp:wait               # blocks until Windows is RDP-ready; macOS notification when done
mise run software:fetch-revit   # VM downloads the Revit installer (set REVIT_INSTALLER_URL in mise.local.toml)
mise run rdp:open               # land in Windows, run \\host.lan\Data\install-revit.bat, sign into trial
mise run snapshot:create        # bake Windows + Revit + signed-in trial state
mise run vm:down                # stop the cost meter

# later sessions in the same 30-day trial
mise run vm:up-snap             # restore — already signed-in, ready to work
```

`mise tasks` lists everything; descriptions explain each step.

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

## Don't

- Don't put account-tied URLs or trial start dates in `mise.toml` — those go in `mise.local.toml` (gitignored).
- Don't run `mise run up-kvm` on Hetzner Cloud — it will fail. Hetzner Dedicated and other bare-metal hosts only.
- Don't try to bypass Autodesk's per-trial sign-in by injecting harvested credential stores. Use the trial legitimately, then convert to paid; or skip Revit entirely and use APS.
