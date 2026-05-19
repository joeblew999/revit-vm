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

## Why Revit batch automation is the hard part (not the VM)

Standing up the VM, snapshotting, signing in to the trial — that's all the easy 20%. The 80% is making Revit actually do work unattended without humans clicking dialog boxes. Two layers of pain:

### Journal files

Revit doesn't have a proper headless mode. It runs as a desktop app and records every UI action into a **journal file** (`.txt` in `%LOCALAPPDATA%\Autodesk\Revit\Autodesk Revit <version>\Journals\`). You can technically replay a journal as input — Revit's `/language` flags accept a journal file — but it's a UI-event log, not a script. Brittle, version-specific, breaks with any UI change.

The community workaround is **Revit Batch Processor** (RBP, https://github.com/bvn-architecture/RevitBatchProcessor). RBP:

1. Generates a fresh journal file per Revit launch that opens the target model.
2. Embeds Python (IronPython 2.7, runs inside Revit's process) that does the actual export work via Revit's .NET API.
3. Manages the Revit process lifecycle — launch, wait for completion, kill on timeout, retry.
4. **Has its own built-in dialog/messagebox suppressor** ("Automatic Revit dialog / message box handling" — per the README). Our `revit-side.py` adds extensions on top, it doesn't replace what RBP already does.

That's why our `operations/revit/export-ifc/` has BOTH a Rust binary (drives RBP from outside) AND a `revit-side.py` (the IronPython code RBP runs inside Revit). The Rust binary does:

- Compose a `.rps` settings file with the target model + the path to `revit-side.py`.
- Launch `RevitBatchProcessor.exe -s settings.rps`.
- Tail RBP's log file, parse status, surface failures cleanly to the job runner.
- Apply timeout + retry policy.
- Verify the expected output file appeared in the expected location.

### RBP version pinning + the Revit 2027 cliff

- **Pinned to v1.12.1** (Feb 2026) in `installers.txt`. Supports Revit 2015 through Revit 2026.
- **Maintenance status:** The original author @DanRumery stepped away; the @bvn-architecture org maintains it via community PRs. Last release Feb 2026. Active enough for now — factor in dependency risk if you ever rely heavily on RBP-specific behavior.
- **Revit 2027 will break mainline RBP.** Revit 2027 ships on .NET 10; the IronPython 2.7.12 RBP embeds is incompatible (issue [bvn-architecture/RevitBatchProcessor#147](https://github.com/bvn-architecture/RevitBatchProcessor/issues/147)). A working fork from `@robmintzes` migrates RBP to IronPython 3.4.2 and has verified Revit 2023–2027 end-to-end: https://github.com/robmintzes/RevitBatchProcessor/tree/feature/revit-2027-support — two commits, not yet merged upstream. When we move to Revit 2027, swap `installers.txt` to that fork's release (or to upstream once they merge it).
- **Order of install matters.** RBP scans for already-installed Revit versions and drops per-year addins under `%APPDATA%\Autodesk\Revit\Addins\<year>`. Install Revit first, RBP second. `windows-scripts/install-revit.bat` does this in the right order.

### Personal use doesn't need Rust — RBP runs Python directly

When prototyping, exploring, or just running one-off batch jobs inside RDP, you don't compile anything:

```
BatchRvt.exe -s settings.rps    # settings.rps points at your .py
```

You write IronPython 2.7, edit, re-run. That's the whole loop. Quick.

The Rust operation crates ([SERVICE.md](SERVICE.md)) are **only** needed for service mode — when the orchestrator needs structured args (`--job-id / --input / --output`), structured event emission to Cloudflare, retry semantics, and a stable .exe interface that survives Revit version bumps. None of that matters for "I'm trying to see if Revit can export this model to IFC."

Practical implication: when adding a new Revit operation, write the IronPython first (validate by hand via RDP), commit it, **then** wrap it in a Rust crate for service mode. Don't wrap until the Python is proven on real models.

### Reference: the @jchristel ecosystem

@jchristel (Jan Christel) is the active community lead in the RBP space since @DanRumery stepped away. His repos are the most useful prior art for writing real operations:

| Repo | What it is | How we use it |
|---|---|---|
| [SampleCodeRevitBatchProcessor](https://github.com/jchristel/SampleCodeRevitBatchProcessor) | Curated IronPython sample scripts for RBP, now packaged as a proper Python project (src/test/setup.py, ~50★, last push days ago). | Reference + starting point for our `revit-side.py` files. Don't reinvent. |
| [RBP_Launcher](https://github.com/jchristel/RBP_Launcher) | A JSON-driven flow runner that wraps multiple RBP sessions with pre/post hook scripts. Exactly the shape of what our orchestrator was going to be. | **Prior art for our Rust operation wrappers.** We're still rolling our own (in Rust, for CF event streaming + single-tenant-per-VM); but the JSON-flow-definition shape is a good template. Don't invent a different one without reason. |
| [jchristel/RevitBatchProcessor](https://github.com/jchristel/RevitBatchProcessor) | His own fork of RBP. Currently 1 commit ahead, 34 behind upstream — not a divergent fork, just slightly stale. Worth glancing at his commit when porting changes. | Mostly informational. Stick with upstream `bvn-architecture/RevitBatchProcessor` for the installer. |
| [jchristel/pyRevit](https://github.com/jchristel/pyRevit) | His fork of pyRevit (a major Revit add-in framework). Active March 2026. | Not relevant to batch processing; noted for completeness if we ever extend into interactive Revit add-ins. |

The pattern across his work: small Python packages, focus on IronPython compatibility, idiomatic for the RBP ecosystem. When stuck on a Revit API issue, grep his SampleCode repo before stack-overflowing.

### Popups, modals, "Do you want to upgrade this file?"

Revit's worse problem is modal dialogs that block automation entirely:

| Dialog | Cause | Suppression |
|---|---|---|
| "File needs to be upgraded to this Revit version" | Opening a model saved in an older Revit | Inside `revit-side.py`: subscribe to `DocumentOpening` event, set `OpeningOptions.AllowOpeningLocalByWrongUser = true` and let Revit upgrade silently. |
| Worksharing prompts ("Detach from central?") | Opening a workshared model | Set `OpenOptions.DetachFromCentralOption = DetachAndPreserveWorksets` in `revit-side.py` before opening. |
| "Missing materials/families/links" warnings | Model references files that aren't present | Subscribe to `DialogBoxShowing` event in `revit-side.py`; auto-dismiss known-safe dialogs. |
| Revit "Welcome" / "What's New" screen on first launch after install | First Revit run | Pre-seed `%APPDATA%\Autodesk\Revit\Autodesk Revit <ver>\UIState.dat` via `oem/install.bat` to mark welcome as seen. |
| License sign-in expiry prompt | Trial nearing expiry / paid login expired | Real fix is to sign in fresh (manual). For batch jobs: detect via dialog title, fail the job with `license_expired` error code so the orchestrator can surface it instead of hanging. |
| Worksets selection dialog | Some workshared models | `WorksetConfiguration(WorksetConfigurationOption.OpenAllWorksets)` in `revit-side.py`. |
| Hardware acceleration / GPU complaints | Revit thinks the GPU is unsupported (always true under TCG, sometimes true under KVM without proper drivers) | Set `Options > Graphics > Use hardware acceleration = false` once during the post-install RDP session; baked into the snapshot. |

The general pattern: **subscribe to `DialogBoxShowing` and `MessageBoxShowing` inside the IronPython code RBP runs**, log every dialog ID that fires, auto-dismiss the known-safe ones. Build the suppression list iteratively as you hit each one on real model inputs.

### Implications for the operation

A real Revit operation isn't just "convert RVT to IFC." It's:

1. Open the model with the right `OpenOptions` to avoid the upgrade/detach/worksets dialogs.
2. Subscribe to dialog events, auto-dismiss the known-safe set, log everything else.
3. Run the actual export (`document.Export(...)` for IFC, `document.Print(...)` for PDF, etc.).
4. Close the document cleanly.
5. Exit Revit cleanly (without leaving a zombie process).
6. The Rust outer binary watches all of this, applies timeouts, reports per-step status.

Build this iteratively. First operation = export-ifc on a single known-good test model. Add dialog suppressions as new models break it. Don't try to handle every possible dialog upfront — the list is long and most won't fire on typical inputs.

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
