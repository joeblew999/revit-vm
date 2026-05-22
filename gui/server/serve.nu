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
    <h2>Snapshots <small>— loaded on page load; refresh for fresh</small></h2>
($snapshots)
  </section>

  <section>
    <h2>Recent installs</h2>
    <pre><code>(html-esc ($state.installs_recent | to json --indent 2))</code></pre>
  </section>
</main>"

    shell "vm-servers" $body
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
