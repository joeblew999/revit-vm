# Running Autodesk Revit on revit-vm

Revit is the first/main use case for this repo, but the repo itself is generic (Hetzner + dockur/windows + Mac control plane — see [README.md](README.md) for that). This file is **only** the Revit-specific workflow, cost, and constraints.

## Trial workflow (30 days, free)

The legitimate path: sign up for the Autodesk 30-day trial on your own account, install Revit once inside Windows, snapshot, then live off the snapshot for the rest of the trial. **One sign-in event** — never re-injected, never harvested, never rotated.

```
# 1. On manage.autodesk.com → Products & Services → Revit → "Start Trial".
# 2. From the same page, copy the installer download URL.
# 3. Locally:
cp mise.local.toml.example mise.local.toml
# edit: REVIT_INSTALLER_URL = "<that URL>"
# edit: TRIAL_STARTED = "YYYY-MM-DD" (today)
mise run start                    # boots / restores Windows
mise run software:fetch-revit     # VM curls the installer directly (fast — DC bandwidth, not your home upload)
mise run rdp:open                 # land in Windows
# Inside Windows: double-click \\host.lan\Data\install-revit.bat
# Revit installs (silent or interactive depending on the installer flavour)
# Launch Revit from the Start menu → Autodesk sign-in prompt → sign in with your trial account
# Quit Revit cleanly
mise run snapshot:create          # bake Windows + Revit + signed-in trial state
mise run vm:down                  # stop the meter
```

From here on, every `mise run start` boots into a Revit that's already signed in. No re-auth. No clicking through OOBE. ~90s door-to-door.

`mise run trial:remind` prints days remaining based on `TRIAL_STARTED`. There's no Autodesk public API for "days left on trial" — this is just local date math against the 30-day window.

## Conversion to paid

The day before (or after) the trial expires:

1. Sign in to the paid Autodesk account inside Revit (Account → Sign Out, then sign in with the paid creds). One click.
2. `mise run snapshot:create` to bake the paid-licensed state.
3. `mise run snapshot:prune` to drop the old trial snapshot.

That's the whole conversion. The cloud-side pipeline doesn't care which license type Revit is using internally.

## What you can and can't do with this setup

| Activity | Verdict on Hetzner Cloud (TCG, no GPU) |
|---|---|
| Verify Revit installs cleanly and the trial registers | ✓ |
| Open small / medium models, export to IFC via Revit Batch Processor | ✓ but slow (TCG is ~10× slower than native per dockur maintainer) |
| Open real-size architectural project models | ✗ — RAM swap + no GPU = unusable |
| Render 3D views | ✗ — software rasterizer only |
| Production-scale batch throughput | ✗ — see "Production paths" below |
| Confirm a batch script works end-to-end before scaling up | ✓ — pipeline validation is what this setup is FOR |

## Production paths (when the trial proves the pipeline)

When you want batch processing at real throughput, pick one:

1. **Hetzner Dedicated Root Server** (Robot product, not hcloud) — restores native KVM speed. ~€39/mo for an AX41-NVMe. Monthly billing. `mise run vm:up-kvm` against the new host. Same dockur container, same snapshot loop, ~10× the throughput. Recommended first step.
2. **Vultr Bare Metal / OVH bare-metal / other cloud bare-metal** — same architecture, hourly billing if you want bursty access without a monthly contract.
3. **Cloud GPU instance** (Oracle, Linode, Vultr GPU SKUs) — only matters if you need Revit's 3D viewports / rendering; for headless batch IFC export you don't.
4. **Autodesk Platform Services (APS) Design Automation for Revit** — Autodesk's own server-side headless Revit-as-a-service, billed per cloud-credit. Highest scale, but you give up the VM model and your batch scripts have to fit the APS sandbox shape. Worth costing out once you're routinely doing >10 batch jobs per day.

## Revit-specific costs

| Component | Cost |
|---|---|
| Revit — 30-day trial | €0 |
| Revit — paid subscription (1-user, list price) | ~€428/mo or €3,431/yr |
| Revit Batch Processor (free open-source) | €0 |
| AEC Collection (Revit + AutoCAD + Civil 3D + others) | ~€3,400/yr — better deal if you use more than just Revit |
| APS Design Automation cloud credits | usage-based, ~$10 per 1k Revit operations (check current pricing) |

VM/storage costs for running this are in [README.md → Costs](README.md#costs).

**Realistic monthly bills:**

| Scenario | Total |
|---|---|
| 30-day trial proof-of-pipeline on Hetzner Cloud | ~€1 |
| Post-trial production, Hetzner Cloud + paid Revit, ~10 hr/wk | ~€436/mo (Revit is €428 of that) |
| Same workload on Hetzner Dedicated AX41-NVMe + paid Revit | ~€467/mo (Revit €428 + €39 dedicated server) — and ~10× the throughput |

The Revit subscription dominates everything. Optimising the VM tier is rounding error relative to that.

## Files specific to Revit

| File | Purpose |
|---|---|
| `windows-scripts/install-revit.bat` | Silent-install batch run from inside Windows after `software:fetch-revit` stages the installer. Tries `-silent` first, falls back to interactive. |
| `mise.local.toml.example` | Holds `REVIT_INSTALLER_URL` (per-account) and `TRIAL_STARTED`. Copy to `mise.local.toml` (gitignored). |

Mise tasks specific to Revit:

| Task | What it does |
|---|---|
| `mise run software:fetch-revit` | VM curls your Autodesk-signed installer URL into the shared folder; copies install-revit.bat alongside. |
| `mise run trial:remind` | Local date math against `TRIAL_STARTED` — prints days remaining. |

## What we WON'T do (and why)

The repo refuses to wire up **trial-token harvesting / Identity Services replay** schemes — copying `C:\Users\<u>\AppData\Local\Autodesk\Identity Services` from one machine and injecting it into throwaway VMs to extend trials indefinitely. That circumvents Autodesk's technical protection measure on a commercial product (Revit) and runs into the DMCA / EU InfoSoc anti-circumvention rules + plain EULA breach. We use the trial legitimately, convert to paid, or move to APS — same goal (working Revit pipeline), without the cease-and-desist.

This refusal is **load-bearing** — if a future session proposes a similar workaround "to skip the sign-in" or "to keep the trial going past 30 days," the answer is no, regardless of how it's framed.
