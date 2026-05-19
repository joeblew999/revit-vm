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

## What's new (would live in a separate repo, e.g. `revit-service`)

| Component | Role |
|---|---|
| **CF Worker** (Rust→WASM) | Public API. Job submission, status, R2 URL signing. Stack matches plat-trunk / scrapers-proxy. |
| **D1 schema** | Job state: `(id, customer_id, rvt_url, params, status, started_at, finished_at, result_url, error)`. |
| **R2 buckets** | `revit-service-in/<job-id>.rvt`, `revit-service-out/<job-id>.ifc`. Lifecycle rules to expire old artifacts. |
| **CF Queue or Durable Object** | The orchestrator's input. DO is nicer because it can hold the "last-active timestamp" for the idle-stop decision. |
| **Orchestrator process** | The lifecycle loop above. Bash or small Rust binary. Runs on a `cax11` always-on box (~€3/mo) — simpler than trying to make a CF Worker SSH out. |
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

## When to move from cpx42 (TCG) to AX41 (KVM) for the service

| Stage | Compute |
|---|---|
| Days 1–N: pre-launch, "does this even work" | cpx42 TCG. Slow but cheap. Some jobs may time out — acceptable for proof. |
| First paying customers, bursty usage | cpx42 TCG. Hourly billing matches bursty volume. |
| Predictable daily volume — VM up most of every workday | **Hetzner Dedicated AX41-NVMe**. €39/mo flat. ~10× faster per job → throughput goes way up at almost the same cost as cpx42-24×7. |
| Big enterprise customers / very large models | Per-customer AX41 or Vultr Bare Metal. KVM + better isolation. |
| Volume justifies it | Investigate **Autodesk Platform Services (APS) Design Automation for Revit** as an alternative to running Revit yourself — Autodesk-hosted, per-cloud-credit billing, no VM to manage. Likely cheaper above some threshold. |

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

## What this means for revit-vm

Not much. This repo stays focused on "single VM, single user, manual control" and stays the building block. Don't bake service concerns into `mise.toml` — keep the primitives clean. When `revit-service` exists, it'll import or shell out to this repo; the relationship is one-way.

If something here turns out to make sense in `revit-vm` for the service later (e.g. an `orchestrator:status` task that other automation can call), pull it back. But not before.
