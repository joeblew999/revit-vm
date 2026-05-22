# http-nu entry. Called as `http-nu --datastar $addr gui/server/serve.nu`
# from the `gui:serve` mise task. Defines the closure http-nu invokes per
# request.
#
# Lives inside vm-servers, so `vms.jsonl` is the local repo's own state
# file (state/vms.jsonl). Installs state comes from the sibling vm-software
# repo clone via $VM_SOFTWARE_REPO. The aggregate_state join lives in
# gui/state/lib.nu — shared with the CLI view (gui/state/aggregate.nu).
#
# v0: read-only status board with Datastar-polled VMs section.
#   GET /                  HTML shell (full page)
#   GET /api/state         JSON of aggregate_state
#   GET /api/runs          JSON of derived runs view (state/runs.nu)
#   GET /api/vms-fragment  HTML fragment of just the VMs table (Datastar polls
#                          this every POLL_MS to refresh the page in place)
# v1 will add POST endpoints to drive `mise run` lifecycle tasks.
#
# Styling: pico CSS via CDN + semantic HTML5. No custom stylesheet.
# Mirrors the convention in sibling joeblew999/scrapers-catalogs.

use ../state/lib.nu *

const PICO_CSS = "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"
const POLL_MS = 5000

def reactive [] {
    # Default ON. Matches sibling scrapers-catalogs convention. Set REACTIVE=0
    # for static rendering (e.g. CI smoke tests, no JS environment).
    ($env.REACTIVE? | default "1") != "0"
}

def html-esc [s: any] {
    ($s | into string)
    | str replace -a "&" "&amp;"
    | str replace -a "<" "&lt;"
    | str replace -a ">" "&gt;"
    | str replace -a '"' "&quot;"
    | str replace -a "'" "&#39;"
}

def shell [title: string, body: string] {
    let script_tag = (if (reactive) { '<script type="module" src="/datastar@1.0.1.js"></script>' } else { "" })
    let title_esc = (html-esc $title)
    $"<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
  <title>($title_esc)</title>
  <link rel=\"stylesheet\" href=\"($PICO_CSS)\">
  ($script_tag)
</head>
<body>
($body)
</body>
</html>"
}

def vm-row-render [v: record, installs_recent: list] {
    let installs_for_vm = ($installs_recent | where vm_label == $v.label | length)
    let label = (html-esc ($v.label? | default '-'))
    let provider = (html-esc ($v.provider? | default '-'))
    let action = (html-esc ($v.action? | default '-'))
    let ip = (html-esc ($v.ip? | default '-'))
    $"<tr><td>($label)</td><td>($provider)</td><td>($action)</td><td><code>($ip)</code></td><td>($installs_for_vm)</td></tr>"
}

# Build a {sku → eur_per_hour} lookup from state/costs.jsonl, so the
# Runs section can show per-run spend (duration_hr × rate). One file read,
# returns a record indexed by sku.
def cost-rates [] {
    let path = "state/costs.jsonl"
    if not ($path | path exists) { return {} }
    let rows = (open $path | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json } | where category == "compute")
    mut idx = {}
    for r in $rows {
        let sku = ($r.sku? | default "")
        let rate = ($r.eur_per_hour? | default 0)
        if ($sku | is-not-empty) and ($rate > 0) {
            $idx = ($idx | upsert $sku $rate)
        }
    }
    $idx
}

# Runs view: derived from vms.jsonl by state/runs.nu. One row per
# provisioned→destroyed pair with duration_hr × eur/hr cost.
def runs-render [] {
    let out = (^nu state/runs.nu --json | complete)
    if $out.exit_code != 0 or ($out.stdout | str trim | is-empty) {
        return "<aside><em>no runs yet — start a VM and stop it to see one</em></aside>"
    }
    let runs = ($out.stdout | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json })
    let rates = (cost-rates)
    let rows = ($runs | each {|r|
        let label = (html-esc ($r.label? | default '-'))
        let prov = (html-esc ($r.provider? | default '-'))
        let started = (html-esc ($r.started_at? | default '-'))
        let stopped = (html-esc ($r.stopped_at? | default 'still running'))
        let dur = ($r.duration_hr? | default 0)
        let sku = ($r.sku? | default '')
        let rate = ($rates | get -o $sku | default 0)
        let cost = (if $rate > 0 and $dur > 0 { ($dur * $rate | math round --precision 4) } else { '-' })
        let sku_html = (html-esc $sku)
        $"<tr><td>($label)</td><td>($prov)</td><td>($started)</td><td>($stopped)</td><td>($dur)</td><td><kbd>($sku_html)</kbd></td><td>€($cost)</td></tr>"
    } | str join "\n")
    $"<figure><table>
  <thead><tr><th scope=\"col\">label</th><th scope=\"col\">provider</th><th scope=\"col\">started</th><th scope=\"col\">stopped</th><th scope=\"col\">hours</th><th scope=\"col\">sku</th><th scope=\"col\">cost</th></tr></thead>
  <tbody>
($rows)
  </tbody>
</table></figure>"
}

# Live events feed: tail of vms.jsonl rendered chronologically. Polled
# from the gui every POLL_MS so new lifecycle events appear without
# refreshing. (Same data the xs broadcast layer carries — we use the
# jsonl source-of-truth here to avoid the xs N+1 cas lookups.)
def events-feed-render [] {
    let path = "state/vms.jsonl"
    if not ($path | path exists) or ((open $path | str trim) | is-empty) {
        return "<pre id=\"events-feed\"><code>(no events yet — start a VM)</code></pre>"
    }
    let events = (open $path | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json } | last 30 | reverse)
    let rows = ($events | each {|e|
        let ts = (html-esc ($e.ts? | default '-'))
        let action = (html-esc ($e.action? | default '-'))
        let label = (html-esc ($e.label? | default '-'))
        let prov = (html-esc ($e.provider? | default '-'))
        let extra = (html-esc ($e | reject ts action label provider | to json -r))
        $"  <tr><td><small>($ts)</small></td><td><kbd>($prov)</kbd></td><td>($label)</td><td><strong>($action)</strong></td><td><small><code>($extra)</code></small></td></tr>"
    } | str join "\n")
    $"<figure id=\"events-feed\"><table>
  <thead><tr><th scope=\"col\">when</th><th scope=\"col\">provider</th><th scope=\"col\">label</th><th scope=\"col\">action</th><th scope=\"col\">details</th></tr></thead>
  <tbody>
($rows)
  </tbody>
</table></figure>"
}

# Costs reference: provider/SKU pricing from state/costs.jsonl. Static —
# loaded on page render, not polled.
def costs-render [] {
    let path = "state/costs.jsonl"
    if not ($path | path exists) { return "<aside><em>state/costs.jsonl missing</em></aside>" }
    let rows = (open $path | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json })
    let trs = ($rows | each {|r|
        let cat = (html-esc ($r.category? | default '-'))
        let prov = (html-esc ($r.provider? | default '-'))
        let sku = (html-esc ($r.sku? | default ($r.name? | default '-')))
        let note = (html-esc ($r.notes? | default ($r.note? | default '-')))
        $"<tr><td>($cat)</td><td>($prov)</td><td><kbd>($sku)</kbd></td><td><small>($note)</small></td></tr>"
    } | str join "\n")
    $"<figure><table>
  <thead><tr><th scope=\"col\">category</th><th scope=\"col\">provider</th><th scope=\"col\">sku / name</th><th scope=\"col\">notes</th></tr></thead>
  <tbody>
($trs)
  </tbody>
</table></figure>"
}

# The polled fragment: just the VMs table. Datastar re-fetches this every
# POLL_MS and swaps it into the #vms-fragment div in the shell.
def vms-fragment-render [] {
    let state = (aggregate_state)
    let rows = ($state.vms | each {|v| vm-row-render $v $state.installs_recent } | str join "\n")
    let updated = (date now | format date "%H:%M:%S")
    $"<figure>
  <table>
    <thead>
      <tr><th scope=\"col\">label</th><th scope=\"col\">provider</th><th scope=\"col\">last action</th><th scope=\"col\">ip</th><th scope=\"col\">installs</th></tr>
    </thead>
    <tbody>
($rows)
    </tbody>
  </table>
  <figcaption><small>updated ($updated)</small></figcaption>
</figure>"
}

# Live provider snapshots — one shell-out per page load (NOT polled, to
# avoid hammering the provider's rate limit every 5s).
def snapshots-render [] {
    let provider = ($env.VM_PROVIDER? | default "")
    let script = $"providers/($provider)/snapshot-list.nu"
    if not ($script | path exists) {
        return $"<aside><em>no snapshot-list for provider <kbd>(html-esc $provider)</kbd></em></aside>"
    }
    let out = (^nu $script --json | complete)
    if $out.exit_code != 0 {
        return $"<aside><em>snapshot:list failed: <code>(html-esc $out.stderr)</code></em></aside>"
    }
    let snaps = (try { $out.stdout | from json } catch { [] })
    if ($snaps | is-empty) {
        return $"<aside><em>no snapshots yet \(provider: <kbd>(html-esc $provider)</kbd>\)</em></aside>"
    }
    let rows = ($snaps | each {|s|
        let id = (html-esc ($s.id? | default '-'))
        let desc = (html-esc ($s.description? | default '-'))
        let sz = ($s.image_size_gb? | default ($s.size_gb? | default '-'))
        let created = (html-esc ($s.created? | default '-'))
        $"<tr><td><code>($id)</code></td><td>($desc)</td><td>($sz) GB</td><td>($created)</td></tr>"
    } | str join "\n")
    $"<figure><table>
  <thead><tr><th scope=\"col\">id</th><th scope=\"col\">description</th><th scope=\"col\">size</th><th scope=\"col\">created</th></tr></thead>
  <tbody>
($rows)
  </tbody>
</table></figure>"
}

def render-status-board [] {
    let state = (aggregate_state)
    let installs_repo = (html-esc ($env.VM_SOFTWARE_REPO? | default '<unset>'))
    let provider = (html-esc ($env.VM_PROVIDER? | default '<unset>'))
    let fragment = (vms-fragment-render)
    let snapshots = (snapshots-render)
    let runs = (runs-render)
    let costs = (costs-render)
    let xs_addr = (html-esc ($env.XS_ADDR? | default '<unset>'))
    let poll_attrs = (if (reactive) {
        $"data-on-interval__duration.($POLL_MS)ms=\"@get\(`/api/vms-fragment`\)\""
    } else { "" })

    let body = $"<main class=\"container\">
  <header>
    <hgroup>
      <h1>vm-servers</h1>
      <p>Status board. Active provider: <kbd>($provider)</kbd>. VMs from <code>state/vms.jsonl</code>; installs from <code>($installs_repo)/state/installs.jsonl</code>; snapshots live from provider API.</p>
    </hgroup>
  </header>

  <section>
    <h2>VMs <small>— auto-refresh every ($POLL_MS / 1000)s</small></h2>
    <div id=\"vms-fragment\" ($poll_attrs)>
($fragment)
    </div>
  </section>

  <section>
    <h2>Actions</h2>
    <p><small>Each button POSTs to a mise task that runs as a pitchfork-supervised daemon. See the Jobs section below for live status, or run <code>pitchfork list</code> / <code>pitchfork logs &lt;name&gt;</code> from the CLI.</small></p>
    <div role=\"group\">
      <button data-on-click=\"@post\(`/api/vm/start`\)\">Start</button>
      <button data-on-click=\"@post\(`/api/vm/stop`\)\" class=\"secondary\">Stop</button>
      <button data-on-click=\"@post\(`/api/snapshot/create`\)\" class=\"secondary\">Snapshot</button>
      <button data-on-click=\"@get\(`/api/vm/status`\)\" class=\"contrast\">Refresh status</button>
    </div>
    <pre id=\"action-output\"><code>Click a button to act on the active provider's VM.</code></pre>
  </section>

  <section>
    <h2>Jobs <small>— pitchfork list, polled every ($POLL_MS / 1000)s</small></h2>
    <div data-on-load=\"@get\(`/api/jobs`\)\" data-on-interval__duration.($POLL_MS)ms=\"@get\(`/api/jobs`\)\">
      <pre id=\"jobs-fragment\"><code>loading...</code></pre>
    </div>
  </section>

  <section>
    <h2>Snapshots <small>— loaded on page load; refresh for fresh</small></h2>
($snapshots)
  </section>

  <section>
    <h2>Runs <small>— derived from vms.jsonl by state/runs.nu</small></h2>
($runs)
  </section>

  <section>
    <h2>Costs <small>— provider/SKU pricing reference</small></h2>
($costs)
  </section>

  <section>
    <h2>Live events <small>— last 30 lifecycle events, polled every ($POLL_MS / 1000)s</small></h2>
    <div data-on-load=\"@get\(`/api/events-feed`\)\" data-on-interval__duration.($POLL_MS)ms=\"@get\(`/api/events-feed`\)\">
      <pre id=\"events-feed\"><code>loading ...</code></pre>
    </div>
    <p><small>Source: <code>state/vms.jsonl</code> — the on-disk truth. xs at <kbd>($xs_addr)</kbd> carries the same stream for live consumers like MCP. Tail xs directly: <code>mise x -- xs cat --follow --sse -T vm.lifecycle ($xs_addr)</code></small></p>
  </section>

  <section>
    <h2>Recent installs</h2>
    <pre><code>(html-esc ($state.installs_recent | to json --indent 2))</code></pre>
  </section>
</main>"

    shell "vm-servers" $body
}

# Spawn a long-running mise task under pitchfork so the HTTP response
# returns immediately AND the user can see it / kill it / read its logs
# via `pitchfork list`, `pitchfork stop NAME`, `pitchfork logs NAME` —
# OR via the Jobs section in this gui, which calls `pitchfork list`.
#
# Each invocation gets a unique daemon name (vm-action-<task>-<ts>) so
# two concurrent Starts don't collide.
def fire-and-forget [mise_task: string] {
    let safe = ($mise_task | str replace --all ":" "-")
    let stamp = (date now | format date "%H%M%S")
    let name = $"vm-action-($safe)-($stamp)"
    # pitchfork run is detached itself; the inner `mise run ...` inherits
    # the pitchfork-supervised lifetime + logs.
    ^pitchfork run $name -f -- mise run $mise_task
    $name
}

{|req|
    let path = ($req.path | default "/")
    let method = ($req.method | default "GET")

    match [$method, $path] {
        ["GET", "/"]                  => { render-status-board }
        ["GET", "/api/state"]         => { aggregate_state | to json }
        ["GET", "/api/runs"]          => {
            # Derived runs view — same data the CLI `runs:show` task prints.
            ^nu state/runs.nu --json
        }
        ["GET", "/api/vms-fragment"]  => { vms-fragment-render }
        ["GET", "/api/vm/status"]     => {
            # Sync: hits provider API, slow on first call but small response.
            let out = (^nu lifecycle/dispatch.nu status | complete)
            let body = (if $out.exit_code == 0 { $out.stdout } else { $"no vm \(or status errored\): ($out.stderr)" })
            $"<pre id=\"action-output\"><code>(html-esc $body)</code></pre>"
        }
        ["POST", "/api/vm/start"]     => {
            let name = (fire-and-forget "start")
            $"<pre id=\"action-output\"><code>start queued as pitchfork daemon <kbd>($name)</kbd>\nVMs table above will show events; see Jobs section for live status\n`pitchfork logs ($name)` to tail</code></pre>"
        }
        ["POST", "/api/vm/stop"]      => {
            let name = (fire-and-forget "stop")
            $"<pre id=\"action-output\"><code>stop queued as pitchfork daemon <kbd>($name)</kbd>\nclean-shut Windows → snapshot → prune → destroy VM\n`pitchfork logs ($name)` to tail</code></pre>"
        }
        ["POST", "/api/snapshot/create"] => {
            let name = (fire-and-forget "snapshot:create")
            $"<pre id=\"action-output\"><code>snapshot:create queued as pitchfork daemon <kbd>($name)</kbd>\nHetzner ~60s, Vultr 30-60 min\n`pitchfork logs ($name)` to tail</code></pre>"
        }
        ["GET", "/api/jobs"]          => {
            # HTML fragment of `pitchfork list` for the Jobs section.
            let out = (^pitchfork list --hide-header | complete)
            if $out.exit_code != 0 or ($out.stdout | str trim | is-empty) {
                "<pre id=\"jobs-fragment\"><code>no pitchfork daemons running</code></pre>"
            } else {
                $"<pre id=\"jobs-fragment\"><code>(html-esc $out.stdout)</code></pre>"
            }
        }
        ["GET", "/api/events-feed"]   => { events-feed-render }
        ["GET", "/api/snapshots"]     => {
            # Live provider snapshot list (Hetzner or Vultr depending on $VM_PROVIDER).
            let provider = ($env.VM_PROVIDER? | default "")
            let script = $"providers/($provider)/snapshot-list.nu"
            if not ($script | path exists) {
                $"{\"error\":\"no snapshot-list for provider ($provider)\"}"
            } else {
                ^nu $script --json
            }
        }
        ["GET", "/api/events"]        => {
            # Live SSE stream of vm.lifecycle events from xs. Bridges the MCP
            # actor (writes) and the GUI actor (reads) without polling.
            # Requires `mise run xs:serve:bg` to be running.
            if ($env.XS_ADDR? | is-empty) {
                "XS_ADDR not set — run `mise run xs:serve:bg` first\n"
            } else {
                ^xs cat --follow --sse --topic vm.lifecycle $env.XS_ADDR
            }
        }
        _ => { $"not found: ($method) ($path)\n" }
    }
}
