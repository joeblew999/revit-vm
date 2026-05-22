# Context for Claude Code — vm-servers

A `mise` + `nushell`-driven toolchain for provisioning a remote Windows VM (Mac control plane → dockur/windows on Hetzner Cloud or Vultr Bare Metal). Sibling [vm-software](../vm-software) is the per-app installer catalog (git-cloned inside the running VM); this repo's `gui/` is a small http-nu status board.

Daily UX is four commands: `start`, `stop`, `push`, `pull`. Everything else is granular.

## Decisions worth knowing (don't relitigate)

1. **Two providers behind one switch.** `VM_PROVIDER` env (`"hetzner"` default, `"vultr"`) routes every dispatcher (`vm:up`, `vm:down`, `vm:ip`, `snapshot:*`). Hetzner-specific tasks (`vm:qemu-up`, `vm:kvm-up`, `token:set`) keep un-namespaced names; Vultr lives under `vultr:*`. Pricing tradeoffs in `state/costs.jsonl` (`mise run costs:show`).

2. **Two cloud-init variants.** `cloud-init/qemu.yaml` (TCG, `KVM=N`) for Hetzner Cloud — no `/dev/kvm` on any tier (verified live 2026-05-18). `cloud-init/kvm.yaml` for anywhere that does expose KVM (Hetzner Dedicated, Vultr Bare Metal).

3. **Snapshot-based persistence.** Fresh Windows install is ~1hr on Hetzner TCG; `stop` snapshots so future `start`s restore in ~90s. Hetzner uses its native snapshot API. Vultr has no hot-snapshot — `providers/vultr/snapshot-create.nu` streams the qcow2 via R2 (dd|gzip|aws s3 cp), registers via `vultr-cli snapshot create-url`, drops the R2 transit object. Expect 30-60 min per Vultr `stop`.

4. **R2 for snapshot transit, not Vultr Object Storage.** Free egress, provider-neutral, already in the CF ecosystem. `mise run r2:bootstrap` walks through one-time setup (manual CF dashboard — no CLI for bucket + token creation).

5. **State is JSONL committed to git.** `state/vms.jsonl` captures every lifecycle event. Sibling vm-software writes `state/installs.jsonl`. The embedded `gui/` reads vm-servers's locally and pulls vm-software's on a timer. `git push` is the persistence story; no separate database.

6. **All task defs in root `mise.toml`.** Subfolder `mise.toml`s don't expose tasks to root without mise's experimental monorepo mode that breaks the 4-command UX. Tried 2026-05-22, rolled back. Encapsulation lives in per-stage folders' `.nu` files instead.

7. **Tools are binary-only, no compilers needed.** `hcloud`, `vultr-cli`, `aws`, `fnox`, `nushell`, `pitchfork`, `http-nu`, `xs`, `yoke`. `http-nu` + `xs` install via mise's `github:` backend from the `joeblew999/*` forks (relay-url branch — adds iroh-relay support for FS sync). `yoke` installs from `cablehead/yoke` directly (ships release binaries). Goal: any clone → `mise install` → working repo, no compilers, no cargo, no curl-piped install scripts.

8. **fnox + mise for secrets.** Pointer table in `fnox.toml` maps env-var names to keychain items; `fnox set -p keychain <KEY>` writes; `fnox exec --if-missing ignore -- <cmd>` injects at runtime. `--if-missing ignore` is mandatory so missing other-provider secrets don't warn on every command.

9. **MCP server via `nu --mcp`.** `mise run mcp:serve` turns vm-servers into an MCP server (stdio) that Claude Desktop / Claude Code can drive directly. The `evaluate` tool gives the client a full nushell REPL with CWD=repo root. Long-running ops (Vultr snapshot, `rdp:wait`) auto-promote to background jobs after 10 s; the client calls `job recv` when ready.

10. **yoke for AI agent turns.** `mise run ai:ask -- 'prompt'` drives one LLM turn to completion via `yoke` (cablehead — same ecosystem as `http-nu` + `xs`). `--tools nu` gives the model an embedded nushell engine; `--config mcp/init.nu` pre-loads `vm-state`, `vm-ip`, `vm-runs` wrappers. Output is JSONL — pipe to `tee { save }` for session replay. Sessions will eventually move to xs. Both `mcp:serve` and `ai:ask` use `job spawn` inside long-running `.nu` scripts so neither blocks the caller.

11. **xs as the event bus between actors.** GUI (`gui:serve`) and MCP (`mcp:serve`) are two actors on the same system — human-facing and AI-facing respectively. Both read `state/vms.jsonl` for durable history. `xs` is the live channel: `state/append.nu` writes every lifecycle event to `xs append $XS_ADDR vm.lifecycle`; `gui:serve` tails it via `xs cat --follow --sse` at `/api/events`. Start the store with `mise run xs:serve:bg`. Set `XS_ADDR` to an iroh relay URL in `mise.local.toml` to sync across machines (the `joeblew999/xs` fork carries the relay-url branch).

12. **Self-evolution via iroh + no compile phase.** All logic is in `.nu` files — no build step. The `joeblew999/*` forks of `http-nu` and `xs` include iroh-relay support, which converges the file systems of all git-cloned instances automatically. An AI actor (MCP or yoke) can modify a `.nu` file and that change propagates to every running instance without restarts or redeployment. The binary tools are pinned in `mise.toml`; the logic layer is fluid. This is intentional — treat it as a capability, not a risk.

13. **`job spawn` for long polling loops.** `rdp-wait.nu` and `providers/vultr/snapshot-create.nu` both had `mut elapsed / sleep 30sec` busy-wait loops. Replaced with `job spawn { ... | job send 0 }` + `job recv --timeout`. The job mailbox pattern is idiomatic nushell 0.112+ and plays well with the MCP server's auto-promotion.

14. **Compose primitives, don't wrap them.** The stack is layered — mise / pitchfork / nushell / http-nu / xs / Datastar / JSONL — and each layer already provides the glue the next would otherwise reinvent. Before writing a helper, parser, or detach wrapper, check the layer below: there's almost always a built-in command, an existing task, or a well-defined contract you can compose with. New abstractions are a tax; primitive composition is free. When in doubt, prefer reading the docs / the sibling repo's serve.nu / the binary's `--help` over inventing.

15. **Parens inside `$"..."` interpolated strings are expression evaluation, even in HTML text.** This bit us three times in one session: `(blank = default)` parsed as nu assignment, `(auto-refresh ...)` as a command call, `(click an action ...)` same. In nushell, `($var)` interpolates and `(expr)` evaluates — that's recursive throughout the string. Rule: only use parens for actual variable refs or expressions; for human prose use em-dashes or brackets. Symptoms: the gui returns HTTP 500 with `Command \`X\` not found` in pitchfork logs.

16. **Datastar v1 needs SSE-shaped responses for `@get`/`@post`, not plain HTML.** Returning raw `<pre>...</pre>` from a handler reaches the browser but never merges into the DOM (click → silent no-op). Wrap responses via `datastar-patch` (gui/server/serve.nu) which formats as `event: datastar-patch-elements` + `data: elements <html>` SSE. ID-based merge happens automatically. http-nu's body is `$in` at closure top — capture before any `let`/`match` shadows it; `"" | from json` errors *outside* try/catch so guard with `str trim | is-empty` first.

17. **AI drives the API, not the browser. No Playwright needed.** The gui carries no business logic — every button is a thin POST/GET to a mise task, and every render is a function over `state/vms.jsonl` + provider APIs. Two surfaces (browser DOM, AI/HTTP client) compose through the same endpoints, so an AI or test harness gets the same outcomes by calling them directly:
    - **Drive**: `curl -X POST http://127.0.0.1:8080/api/vm/start -d '{"label":"vm-x","provider":"hetzner"}'` is the Start button.
    - **Observe (durable)**: `state/vms.jsonl` is the source of truth, queryable any time. `/api/state` and `/api/runs` return it as JSON.
    - **Observe (live)**: `xs cat --follow --sse -T vm.lifecycle $XS_ADDR` streams every event the moment a writer (lifecycle script, MCP, gui POST) emits it.
    - **Confirm**: `/api/vm/status` + `/api/snapshots` hit the provider API directly for ground truth.
    Skipping the browser layer means no headless renderer overhead, no flake from rendering, and AI development loops at the speed of HTTP. The reactive gui you see in a browser is just one of many subscribers to the same streams.

## Don't

- Don't put account-tied URLs (Autodesk installer, etc.) here — they belong in vm-software's `mise.local.toml`.
- Don't run `vm:kvm-up` on Hetzner Cloud — fails at `docker run` (no `/dev/kvm`).
- Don't remove `--restart=always` from the dockur container — breaks `vm:snap-up` (Windows wouldn't auto-start on snapshot restore).
- Don't remove `ssh-keygen -R` from `providers/hetzner/up*.nu` — Hetzner reuses project IPs; stale host keys would break every SSH-using task.
- Don't remove `set -e` from `start` / `stop` — the snapshot-then-destroy ordering prevents data loss.
- Don't bypass the R2 transit on Vultr. Vultr BM has no native hot-snapshot. If R2 isn't configured, `snapshot:create` errors clearly; don't add a "skip and destroy" fallback.
- Don't reintroduce subfolder `mise.toml`s (see decision 6).
- Don't change `VM_PROVIDER` default — switching providers is a per-clone decision via `mise.local.toml`.
- Don't `git commit` or `git push` without explicit user approval.
