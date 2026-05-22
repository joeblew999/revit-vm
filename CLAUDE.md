# Context for Claude Code — vm-servers

A `mise` + `nushell`-driven toolchain for provisioning a remote Windows VM (Mac control plane → dockur/windows on Hetzner Cloud or Vultr Bare Metal). Sibling [vm-software](../vm-software) is the per-app installer catalog (git-cloned inside the running VM); this repo's `gui/` is a small http-nu status board.

Daily UX is four commands: `start`, `stop`, `push`, `pull`. Everything else is granular.

## Decisions worth knowing (don't relitigate)

1. **Two providers behind one switch.** `VM_PROVIDER` env (`"hetzner"` default, `"vultr"`) routes every dispatcher (`vm:up`, `vm:down`, `vm:ip`, `snapshot:*`). Hetzner-specific tasks (`vm:qemu-up`, `vm:kvm-up`, `token:set`) keep un-namespaced names; Vultr lives under `vultr:*`. Pricing tradeoffs in `costs.jsonl` (`mise run costs:show`).

2. **Two cloud-init variants.** `cloud-init-qemu.yaml` (TCG, `KVM=N`) for Hetzner Cloud — no `/dev/kvm` on any tier (verified live 2026-05-18). `cloud-init-kvm.yaml` for anywhere that does expose KVM (Hetzner Dedicated, Vultr Bare Metal).

3. **Snapshot-based persistence.** Fresh Windows install is ~1hr on Hetzner TCG; `stop` snapshots so future `start`s restore in ~90s. Hetzner uses its native snapshot API. Vultr has no hot-snapshot — `providers/vultr/snapshot-create.nu` streams the qcow2 via R2 (dd|gzip|aws s3 cp), registers via `vultr-cli snapshot create-url`, drops the R2 transit object. Expect 30-60 min per Vultr `stop`.

4. **R2 for snapshot transit, not Vultr Object Storage.** Free egress, provider-neutral, already in the CF ecosystem. `mise run r2:bootstrap` walks through one-time setup (manual CF dashboard — no CLI for bucket + token creation).

5. **State is JSONL committed to git.** `state/vms.jsonl` captures every lifecycle event. Sibling vm-software writes `state/installs.jsonl`. The embedded `gui/` reads vm-servers's locally and pulls vm-software's on a timer. `git push` is the persistence story; no separate database.

6. **All task defs in root `mise.toml`.** Subfolder `mise.toml`s don't expose tasks to root without mise's experimental monorepo mode that breaks the 4-command UX. Tried 2026-05-22, rolled back. Encapsulation lives in per-stage folders' `.nu` files instead.

7. **Tools are binary-only, no compilers needed.** `hcloud`, `vultr-cli`, `aws`, `fnox`, `nushell`, `pitchfork`, `http-nu`, `xs`. `http-nu` + `xs` install via mise's `github:` backend from the `joeblew999/*` forks (relay-url branch — adds iroh-relay support for FS sync). Upstream `cablehead/*` doesn't yet ship release binaries. Goal: any clone → `mise install` → working repo, no compilers, no cargo, no curl-piped install scripts.

8. **fnox + mise for secrets.** Pointer table in `fnox.toml` maps env-var names to keychain items; `fnox set -p keychain <KEY>` writes; `fnox exec --if-missing ignore -- <cmd>` injects at runtime. `--if-missing ignore` is mandatory so missing other-provider secrets don't warn on every command.

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
