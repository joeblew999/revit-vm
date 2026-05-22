# ROADMAP

## Done — v0

- Core lifecycle: `start` / `stop` / `push` / `pull`
- Two providers: Hetzner Cloud (TCG) + Vultr Bare Metal (KVM) behind `VM_PROVIDER`
- Snapshot persistence: Hetzner native; Vultr via R2 transit
- JSONL state in git; sibling vm-software writes `state/installs.jsonl`
- GUI v0: read-only status board (`gui:serve`) — pico CSS, semantic HTML5
- fnox + mise secrets; no `.env` files, no curl-piped installers

---

## v1 — write surface

- [ ] **`mcp:serve` task** — `nu --mcp` turns vm-servers into an MCP server (stdio or
  HTTP); long-running ops auto-promote to background jobs so snapshot/rdp-wait don't block
- [ ] **`job spawn` in polling loops** — replace `mut elapsed / sleep 30sec` in
  `providers/vultr/snapshot-create.nu` and `connect/rdp-wait.nu` with nushell's native
  job mailbox (`job spawn` / `job recv`)
- [ ] **GUI POST endpoints** — `POST /api/vm/start`, `/stop`, `/snapshot/list` → shell
  out to existing `mise run` tasks; each action logged as an xs event
- [ ] **Datastar reactivity** — wire the already-injected `<script>` tag to the new
  POST endpoints; SSE patches from xs stream back to the browser

---

## v2 — auth + durability

- [ ] **CF Access gate** (or basic auth) in front of `gui:serve`
- [ ] **xs relay via iroh** — sync state across machines without exposing the GUI port;
  uses the relay-url branch already pinned in `mise.toml`
- [ ] **`runs:show` live view** — SSE push as `state/vms.jsonl` grows; currently
  requires a manual `gui:state:refresh`

---

## Later / maybe

- Extract `gui/` into its own repo when managing multiple vm-servers instances
- Installer catalog in the GUI — surface vm-software's installs with
  install/uninstall buttons (needs v1 write path + v2 auth first)
- Hetzner Dedicated path: `vm:kvm-up` + native KVM, skip TCG penalty
