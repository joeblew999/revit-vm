# From revit-vm to a service

Forward-looking architecture sketch. Not built yet. Captures the design so the next agent (or you in 6 months) doesn't re-derive it.

**Goal:** turn the manual `mise run start / push / pull / stop` workflow into an on-demand conversion service where:
- Customers submit a `.rvt` file (or a batch of them) via API.
- A Windows VM spins up on Hetzner only when there's work.
- VM stays warm while jobs are flowing, snapshots and powers down after idle.
- Customers pay per conversion, not per month-of-VM.

The mise primitives we already built (`vm:up-snap`, `push`, `pull`, `snapshot:create`, `vm:down`, etc.) **are the verbs the service orchestrator calls.** No rewrite — a thin layer on top.

## Architecture

```
   ┌─────────────────────────────────────────────────────────┐
   │  customer                                               │
   │  POST /jobs (rvt + params) → 202 + job-id               │
   │  GET  /jobs/:id            → status, result URL         │
   │  webhook on completion (optional)                       │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  CF Worker (Rust→WASM, Hono+Zod)         your stack     │
   │  - validates input, signs an R2 upload URL              │
   │  - writes job row in D1                                 │
   │  - enqueues on CF Queue / Durable Object                │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Orchestrator   (small always-on cax11 ~€3/mo,          │
   │                  OR CF Cron Trigger if SSH can be       │
   │                  proxied through Cloudflare Tunnel)     │
   │                                                          │
   │  Poll loop, every ~60s:                                 │
   │    queued_jobs?  no VM up?   → mise run vm:up-snap      │
   │                              → mise run rdp:wait        │
   │    job in queue?             → mise run push -- <rvt>   │
   │                              → trigger RBP on the VM    │
   │                              → mise run pull -- <out>   │
   │                              → upload to R2,            │
   │                                 update D1 status        │
   │    idle > IDLE_TIMEOUT?      → mise run snapshot:create │
   │                              → mise run vm:down         │
   └────────────────────────┬────────────────────────────────┘
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Hetzner cpx42 (or AX41 dedicated at scale)             │
   │  Windows + Revit + Revit Batch Processor                │
   │  Restored from snapshot in ~90 s, cold-installed        │
   │  only when the snapshot is wiped.                       │
   └─────────────────────────────────────────────────────────┘
```

## What stays the same (this repo)

- All mise tasks. The service shells out to them via SSH (or a local clone on the orchestrator box).
- The snapshot loop. Snapshot persistence is what makes "spin up on demand" viable — 90s cold start, not 1hr.
- `oem/install.bat`, `installers.txt`, the cloud-init files — fresh-provision paths still work, used when snapshot needs rebuilding.
- The `/data` shared folder is where the orchestrator drops `.rvt` files and picks up `.ifc` outputs.

## Where this lives

**In this repo, not a separate one.** The service code, orchestrator, Worker, schema, and mise tasks for both "personal use" (today) and "service mode" (future) all live in `revit-vm`. One mental model, one deploy story, one place to look. The orchestrator and Worker just become more entries in `mise.toml`'s task graph.

Likely additions to the repo layout when service work begins:

```
revit-vm/
├── README.md / REVIT.md / SERVICE.md / CLAUDE.md   (already here)
├── mise.toml             (gains service:* tasks)
├── cloud-init-*.yaml     (unchanged — VM is still our building block)
├── oem/install.bat       (gains: install a Windows job-runner scheduled task)
├── worker/               (NEW — CF Worker source, Rust→WASM)
├── orchestrator/         (NEW — Bash or small Rust binary for the polling loop)
├── windows-runner/       (NEW — the in-Windows .bat/PowerShell that watches Z:\jobs\)
└── schema/               (NEW — D1 migrations)
```

Service mode is additive to personal mode — daily `mise run start/stop` still works the same way for solo use.

## What's new in this repo

| Component | Role |
|---|---|
| **CF Worker** (Rust→WASM) | Public API. Job submission, status, R2 URL signing. Stack matches plat-trunk / scrapers-proxy. |
| **D1 schema** | Job state: `(id, customer_id, rvt_url, params, status, started_at, finished_at, result_url, error)`. |
| **R2 buckets** | `revit-service-in/<job-id>.rvt`, `revit-service-out/<job-id>.ifc`. Lifecycle rules to expire old artifacts. |
| **CF Queue or Durable Object** | The orchestrator's input. DO is nicer because it can hold the "last-active timestamp" for the idle-stop decision. |
| **Orchestrator process** | The lifecycle loop above. Bash or small Rust binary. Lives in `orchestrator/` in this repo. Runs on a `cax11` always-on box (~€3/mo) — simpler than trying to make a CF Worker SSH out. |
| **In-Windows job runner** | A small script inside Windows that watches `Z:\jobs\` (or polls the orchestrator), runs `RevitBatchProcessor.exe -s <job.json>`, drops outputs in `Z:\output\`. Started as a Windows scheduled task at boot via `oem/install.bat`. |
| **Per-customer config / auth** | Out of scope for v1. Single-tenant with a shared bearer token gets you to "service exists" fast. |

## Cost model — flips from "VM rent" to "per-conversion"

**Today (revit-vm as a personal tool):**
- You pay €0.045/hr while you're working, €0.48/mo for the snapshot when idle.
- ~€1–5/mo for personal evaluation use.

**As a service (revit-service):**
- VM is hot only while jobs run.
- Idle: just snapshot (~€0.48/mo), regardless of how many customers exist.
- Per-conversion compute: `job_duration_minutes × €0.00075` (cpx42 hourly / 60).
  - A 5-min job ≈ €0.004 in compute.
  - 1000 jobs/mo of 5-min each ≈ €4/mo of compute.
- Orchestrator box: €3/mo flat.
- D1 + R2 + Workers: ~€0–5/mo at this scale.
- **Floor: ~€10/mo to keep the service running with zero customers. Variable: ~€0.004 per 5-min conversion.**

You'd price conversions at €X per job (or per minute) with margin. The bottleneck is Revit subscription cost (€428/mo) — that has to be amortized across customers regardless of compute.

## Build order (when you're ready)

1. **One Worker route** that accepts a `.rvt` via signed R2 URL and writes a D1 row.
2. **Orchestrator loop** on a `cax11`, in Bash first. Polls D1, calls our mise tasks, updates D1.
3. **In-Windows job runner** — a `.bat` or PowerShell script that watches the shared folder and runs RBP. Pre-install via `oem/install.bat` so it's there on every fresh provision and survives snapshots.
4. **Idle-stop timer** in the orchestrator.
5. **One real customer or test scenario end-to-end.** Manual debugging.
6. **Multi-tenancy + billing** — once 1-5 work cleanly for one customer. Don't do this earlier; it'll guide design choices best when there's a real customer relationship.

## Open questions (don't resolve until needed)

- **Per-customer Revit licensing.** A single paid Revit account inside the snapshot can only have one active session at a time. Multi-customer concurrent work needs either separate Revit subscriptions (one per VM-at-a-time) or APS (which Autodesk licenses for SaaS-style use). Don't promise concurrency before solving this.
- **Where the orchestrator lives.** `cax11` is the simple answer. CF Workers can't SSH directly — would need a Cloudflare Tunnel + a small relay on the VM side, more moving parts. Start with cax11.
- **What "conversion" means.** Just `.rvt → .ifc`? Or `.rvt → .pdf` (sheet export)? Or `.rvt → .nwc` (Navisworks)? Each is a different RBP script. Service API needs a `format` param early.
- **Pricing model.** Per-job flat fee? Per-minute? Per-MB-of-input? Defer until you have real customer conversations.
- **Failure modes.** Revit crash on a malformed input. Trial expired mid-job. VM-side disk full. Orchestrator needs retry logic + clear failure surfacing in the job status row.

## Compute strategy for service mode

The hourly-billing options matter much more in service mode than they did for personal use:

| Stage | Compute | Why |
|---|---|---|
| Pre-launch — internal test, one customer at a time | `cpx42` (TCG) | Pipeline works, jobs run, price is rounding error. Slow per job but volume is tiny. |
| Early customers, bursty / unpredictable | `cpx42` still — OR `Vultr Bare Metal` hourly KVM if speed matters per job | Hourly billing matches bursty volume on both sides. Vultr is the "hourly KVM" bridge — pay €0.12/hr only when work flows. |
| Predictable daily volume (VM up most workdays) | `Hetzner Dedicated AX41-NVMe` | €39/mo flat amortizes across many jobs, native speed. The monthly commit is fine once volume is predictable. |
| Big-enterprise / huge models | Per-customer dedicated host (AX/EX or Vultr) | Isolation + headroom. |
| Volume justifies it | **APS Design Automation for Revit** | Hand the VM headache to Autodesk. Per-cloud-credit billing. |

The `vm:up-qemu` / `vm:up-kvm` task split we already have maps directly: the orchestrator picks which one based on the target host. Adding a third (`vm:up-vultr` or generalised provider switch) is the only mise change needed to support hourly bare-metal.

## Coexistence with personal use

The repo still works for solo work via `mise run start/stop`. Service mode is opt-in via separate tasks (`service:up`, `service:run`, `service:down`). Personal snapshots and service snapshots can share a Hetzner project or split — likely split when production is real, so a dev mistake on solo work can't blow away a customer-loaded snapshot.
