# From revit-vm to a generic Windows-as-a-service

Forward-looking architecture sketch. Not built yet. Captures the design so the next agent (or you in 6 months) doesn't re-derive it.

**Goal:** turn the manual `mise run start / push / pull / stop` workflow into an on-demand conversion service where:
- Customers submit an input file (any Windows-supported format) + a target format via API.
- A Windows VM spins up on Hetzner only when there's work.
- Inside Windows, the right app runs (Revit, AutoCAD, ImageMagick, ffmpeg-on-Windows, …) and produces the output.
- VM stays warm while jobs are flowing, snapshots and powers down after idle.
- Customers pay per conversion, not per month-of-VM.

Revit is the **first** application, not the only one. The pipeline is app-agnostic; only the in-Windows job runner is app-specific. See [REVIT.md](REVIT.md) for the Revit specifics; future apps would each get their own `<APP>.md` and a small Windows-side runner script.

The mise primitives we already built (`vm:up-snap`, `push`, `pull`, `snapshot:create`, `vm:down`, etc.) **are the verbs the service orchestrator calls.** No rewrite — a thin layer on top.

## Architecture

```
   ┌─────────────────────────────────────────────────────────┐
   │  customer                                               │
   │  POST /jobs  { app, input_url, output_format, params }  │
   │              → 202 + job-id                             │
   │  GET  /jobs/:id  → status, result URL                   │
   │  webhook on completion (optional)                       │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  CF Worker (Rust→WASM, Hono+Zod)         your stack     │
   │  - validates input + checks `app` is supported          │
   │  - signs an R2 upload URL                               │
   │  - writes job row in D1                                 │
   │  - enqueues on CF Queue / Durable Object                │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Orchestrator   (small always-on cax11 ~€3/mo)          │
   │                                                          │
   │  Poll loop, every ~60s:                                 │
   │    queued_jobs?  no VM up?   → mise run vm:up-snap      │
   │                              → mise run rdp:wait        │
   │    job in queue?             → mise run push -- <input> │
   │                              → notify in-VM job runner  │
   │                                 of (app, job-id)        │
   │                              → wait for result file in  │
   │                                 /root/windows_shared/   │
   │                                 output/<job-id>.<ext>   │
   │                              → mise run pull -- <out>   │
   │                              → upload to R2,            │
   │                                 update D1 status        │
   │    idle > IDLE_TIMEOUT?      → mise run snapshot:create │
   │                              → mise run vm:down         │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Hetzner cpx42 / AX41 / Vultr bare-metal                │
   │  Windows + per-app installed software                   │
   │                                                          │
   │  In-Windows job runner (`windows-runner/main.ps1`):     │
   │    watches Z:\jobs\<job-id>.json                        │
   │    dispatches by `app`:                                 │
   │      revit       → RevitBatchProcessor.exe …            │
   │      autocad     → accoreconsole.exe …                  │
   │      imagemagick → magick convert …                     │
   │      <new app>   → add a case statement                 │
   │    writes Z:\output\<job-id>.<ext>                      │
   └─────────────────────────────────────────────────────────┘
```

## Where this lives

**In this repo, not a separate one.** The service code, orchestrator, Worker, schema, and mise tasks for both "personal use" (today) and "service mode" (future) all live in `revit-vm`. One mental model, one deploy story, one place to look. The repo's name predates the realisation that the shape is generic; the name stays for now since Revit is the headline app.

Likely additions to the repo layout when service work begins:

```
revit-vm/
├── README.md / REVIT.md / SERVICE.md / CLAUDE.md   (already here)
├── <APP>.md per supported app (REVIT.md is the first)
├── mise.toml             (gains service:* tasks)
├── cloud-init-*.yaml     (unchanged — VM is still our building block)
├── oem/install.bat       (gains: install the Windows job-runner scheduled task)
├── worker/               (NEW — CF Worker source, Rust→WASM)
├── orchestrator/         (NEW — Bash or small Rust binary for the polling loop)
├── windows-runner/       (NEW — in-Windows .ps1 that dispatches by `app`)
└── schema/               (NEW — D1 migrations)
```

Service mode is additive to personal mode — daily `mise run start/stop` still works the same way for solo use.

## What stays the same (today's repo)

- All mise tasks. The service shells out to them via SSH (or a local clone on the orchestrator box).
- The snapshot loop. Snapshot persistence is what makes "spin up on demand" viable — 90s cold start, not 1hr.
- `oem/install.bat`, `installers.txt`, the cloud-init files. The OEM hook gains a step to register the Windows job runner as a startup scheduled task.
- The `/data` shared folder is where the orchestrator drops inputs and picks up outputs.

## What's new in this repo

| Component | Role |
|---|---|
| **CF Worker** (Rust→WASM) | Public API. Job submission, status, R2 URL signing. Validates `app` against the supported list. Stack matches plat-trunk / scrapers-proxy. |
| **D1 schema** | Job state: `(id, customer_id, app, input_url, params, output_format, status, started_at, finished_at, result_url, error)`. |
| **R2 buckets** | `windows-service-in/<job-id>.<ext>`, `windows-service-out/<job-id>.<ext>`. Lifecycle rules to expire artifacts. |
| **CF Queue or Durable Object** | The orchestrator's input. DO is nicer because it can hold the "last-active timestamp" for the idle-stop decision. |
| **Orchestrator process** | Lifecycle loop. Bash or small Rust binary. Lives in `orchestrator/`. Runs on a `cax11` always-on box (~€3/mo) — simpler than trying to make a CF Worker SSH out. |
| **In-Windows job runner** (`windows-runner/main.ps1`) | One PowerShell script with a dispatch table per app. Watches `Z:\jobs\`, picks the right exe + arg shape for each app, writes outputs to `Z:\output\`. Started at boot via a scheduled task installed by `oem/install.bat`. |
| **Per-app installers** | Each app's installer flow lives next to its `<APP>.md`. Free apps go in `installers.txt`. Auth'd ones use the per-app `software:fetch-*` task pattern (`software:fetch-revit` is the template). |
| **Per-customer / per-app auth + licensing** | Out of scope for v1. Single-tenant with a shared bearer token gets you to "service exists" fast. |

## Which apps fit

Not every Windows app makes sense as a converter service. Categories:

| Category | Examples | Service-viable? |
|---|---|---|
| Open-source / freely redistributable CLI | ImageMagick, ffmpeg-on-Windows, Inkscape CLI, 7-Zip | **Yes, easily.** No licensing constraints, can run many concurrent jobs per VM. |
| Free with vendor account (single-user app) | Revit free trial, AutoCAD free trial | **For pipeline testing only.** 30-day expiry, single-account concurrency cap. |
| Paid per-user subscription (CAD, Adobe CC) | Revit paid, AutoCAD, Photoshop | **Yes but constrained.** Each VM session holds one user-license; concurrency = number of subscriptions you own. License pooling is a real engineering problem. |
| Site-licensed / Network License Manager (NLM) | Engineering suites with NLM | **Yes and the cleanest.** Cloud worker checks a seat out on boot, releases on shutdown. Standard CAD-farm pattern. |
| Per-machine activation tied to hardware (rare) | Some legacy software, hardware-keyed installs | **No.** Snapshot reuse breaks the activation. |
| Vendor-hosted API alternatives exist | Revit → Autodesk Platform Services Design Automation | **Often better to use the vendor's API** above some volume. Our service competes with APS only on price/UX/integration. |

Adding a new app to the service:

1. Decide which category above it falls in. If "no", stop.
2. Write `<APP>.md` covering install method, license model, perf reality, costs.
3. Add the installer to `installers.txt` (if public) or a `software:fetch-<app>` task (if account-tied).
4. Add a dispatch case in `windows-runner/main.ps1` for the app's CLI invocation.
5. Add `<app>` to the Worker's accepted-app list and validation.
6. Test end-to-end with one job. Snapshot.

## Cost model — flips from "VM rent" to "per-conversion"

**Today (revit-vm as a personal tool):**
- You pay €0.045/hr while you're working, €0.48/mo for the snapshot when idle.
- ~€1–5/mo for personal evaluation use.

**As a service:**
- VM is hot only while jobs run.
- Idle: just snapshot (~€0.48/mo per app-snapshot), regardless of how many customers exist.
- Per-conversion compute: `job_duration_minutes × €0.00075` on cpx42.
  - A 5-min job ≈ €0.004 in compute.
  - 1000 jobs/mo of 5-min each ≈ €4/mo of compute.
- Orchestrator box: €3/mo flat.
- D1 + R2 + Workers: ~€0–5/mo at this scale.
- **Floor: ~€10/mo to keep the service running with zero customers. Variable: ~€0.004 per 5-min conversion.**

App-specific licensing (Revit subscription €428/mo per seat, etc.) is a separate line and usually dominates everything else. Pricing per conversion has to amortize that across expected volume.

## Compute strategy for service mode

The hourly-billing options matter much more in service mode than they did for personal use:

| Stage | Compute | Why |
|---|---|---|
| Pre-launch — internal test, one customer at a time | `cpx42` (TCG) | Pipeline works, jobs run, price is rounding error. Slow per job but volume is tiny. |
| Early customers, bursty / unpredictable | `cpx42` still — OR `Vultr Bare Metal` hourly KVM if per-job speed matters | Hourly billing matches bursty volume on both sides. Vultr is the "hourly KVM" bridge — €0.12/hr only when work flows. |
| Predictable daily volume (VM up most workdays) | `Hetzner Dedicated AX41-NVMe` | €39/mo flat amortizes across many jobs, native speed. The monthly commit is fine once volume is predictable. |
| Big-enterprise / huge models | Per-customer dedicated host (AX/EX or Vultr) | Isolation + headroom. |
| Volume justifies it (Revit specifically) | **APS Design Automation** | Hand the VM headache to Autodesk. Per-cloud-credit billing. Other vendors have analogues. |

The `vm:up-qemu` / `vm:up-kvm` task split we already have maps directly: the orchestrator picks which one based on the target host. Adding a third (`vm:up-vultr` or a generalised provider switch) is the only mise change needed to support hourly bare-metal.

## Coexistence with personal use

The repo still works for solo work via `mise run start/stop`. Service mode is opt-in via separate tasks (`service:up`, `service:run`, `service:down`). Personal snapshots and service snapshots can share a Hetzner project or split — likely split when production is real, so a dev mistake on solo work can't blow away a customer-loaded snapshot.

## Build order (when you're ready)

1. **One Worker route** that accepts a file via signed R2 URL, writes a D1 row with `app="revit"` hardcoded.
2. **Orchestrator loop** on a `cax11`, in Bash first. Polls D1, calls our existing mise tasks, updates D1.
3. **In-Windows job runner** for Revit — start with the simplest dispatch (one app, one output format). Pre-install via `oem/install.bat` so it's there on every fresh provision and survives snapshots.
4. **Idle-stop timer** in the orchestrator.
5. **One real customer or test scenario end-to-end.** Manual debugging.
6. **Second app** (probably ImageMagick or ffmpeg — free, fast, validates the per-app dispatch shape).
7. **Multi-tenancy + billing** — once 1-6 work cleanly. Don't do this earlier; it'll guide design choices best when there's a real customer relationship.

## Open questions (don't resolve until needed)

- **Per-app licensing concurrency.** A single paid Revit account inside the snapshot can only have one active session. Multi-customer concurrent work needs separate subscriptions, NLM, or APS. Each app has its own version of this problem — bake it into the `<APP>.md` checklist when adding an app.
- **Where the orchestrator lives.** `cax11` is the simple answer. CF Workers can't SSH directly — would need a Cloudflare Tunnel + a small relay on the VM side, more moving parts. Start with cax11.
- **Per-app vs unified snapshot.** Option A: one VM with all installed apps in one snapshot — bigger snapshot, smaller orchestrator. Option B: per-app snapshots, orchestrator picks which one to boot per job — more snapshot $$, but jobs of different apps can run in parallel on separate VMs. Defer until you have >1 app live.
- **Pricing model.** Per-job flat fee? Per-minute? Per-MB-of-input? Per-app? Defer until you have real customer conversations.
- **Failure modes.** App crash on malformed input. License expired mid-job. Disk full. Orchestrator needs retry logic + clear failure surfacing in the job status row.
- **Repo name.** "revit-vm" is misleading once it hosts ImageMagick, ffmpeg, etc. Renaming is cheap — but only do it after the service is real enough to justify the change of public URL.
