# Context for Claude Code — vm-servers/gui/

The web control plane for **vm-servers** (this repo) + **vm-software** (sibling). Lives as a subfolder here, not a separate repo, because:
- The Mac-side `mise run` UX and the browser UX are the same conceptual control plane, just different surfaces.
- vm-servers IS the state-of-truth for VM lifecycle (`state/vms.jsonl` is right there) — co-location means zero cross-repo coupling for the half of state that matters most.
- vm-software stays separate because it has a different RUNTIME (runs on the VM's Linux host, not Mac) — its state needs the cross-repo pull dance, gui code reads it via `$VM_SOFTWARE_REPO`.

If the gui ever grows to manage multiple vm-servers instances (team setting, hosted SaaS), it can be extracted back into its own repo later. Until then, co-located is simpler.

## Stack

- **[http-nu](https://github.com/joeblew999/http-nu)** — HTTP server scriptable in nushell. Each route is a `{|req| ... }` closure. Pinned in root `mise.toml` `[tools]` via `github:joeblew999/http-nu` (relay-url branch — adds iroh-relay support for FS sync; upstream cablehead doesn't ship release binaries).
- **[xs](https://github.com/joeblew999/xs)** — event stream store. Will back write-actions in v1 (every UI button-press becomes an xs event). Pinned alongside http-nu via `github:joeblew999/xs`.
- **[pitchfork](https://github.com/jdx/pitchfork)** — process manager for long-running operations. Pinned in `mise.toml` `[tools]`. The Vultr snapshot pipeline takes 30-60 min; pitchfork keeps it running across user sessions.
- **[Datastar](https://data-star.dev)** — server-side reactivity. UI is plain HTML; http-nu pushes SSE patches. No JS framework.

## Layout

```
gui/
├── CLAUDE.md            (this file)
├── server/
│   └── serve.nu         http-nu entry — routes inlined for now
├── state/
│   ├── aggregate.nu     CLI table view of joined vms + installs state
│   └── refresh.nu       git pull on vm-software (vm-servers is local)
└── static/
    └── style.css        minimal type + table CSS
```

## Read-only first

v0 = status board. v1 = POST endpoints that `mise run` lifecycle tasks (start/stop/snapshot, install:*). v2 = auth (CF Access or basic auth in front). Don't try to ship v2 in v0 — every layer adds debugging surface.

## Don't

- Don't add a database. State is JSONL in git. If you find yourself wanting SQLite, use xs.
- Don't introduce a JS framework. Datastar + plain HTML.
- Don't put cloud-provider tokens here. They're in vm-servers's fnox keychain — gui tasks shell out to existing mise tasks that already know how to authenticate.
- Don't `git commit` or `git push` without explicit user approval.
