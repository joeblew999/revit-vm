# http-nu entry. Called as `http-nu $addr gui/server/serve.nu` from the
# `gui:serve` mise task. Defines the closure http-nu invokes per request.
#
# Lives inside vm-servers, so `vms.jsonl` is the local repo's own state
# file (state/vms.jsonl). Installs state comes from the sibling vm-software
# repo clone via $VM_SOFTWARE_REPO. The aggregate_state join lives in
# gui/state/lib.nu — shared with the CLI view (gui/state/aggregate.nu).
#
# v0: read-only status board. Routes:
#   GET /            HTML status board
#   GET /api/state   JSON of aggregate_state
#   GET /api/runs    JSON of derived runs view (state/runs.nu)
# v1 will add POST endpoints to drive `mise run` lifecycle tasks; the
# Datastar script tag is conditionally injected via $env.REACTIVE so v1
# is a small jump from v0.
#
# Styling: pico CSS via CDN + semantic HTML5. No custom stylesheet.
# Mirrors the convention in sibling joeblew999/scrapers-catalogs.

use ../state/lib.nu *

const PICO_CSS = "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"

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

def render-vm-row [v: record, installs_recent: list] {
    let installs_for_vm = ($installs_recent | where vm_label == $v.label | length)
    let label = (html-esc ($v.label? | default '-'))
    let provider = (html-esc ($v.provider? | default '-'))
    let action = (html-esc ($v.action? | default '-'))
    let ip = (html-esc ($v.ip? | default '-'))
    $"<tr><td>($label)</td><td>($provider)</td><td>($action)</td><td><code>($ip)</code></td><td>($installs_for_vm)</td></tr>"
}

def render-status-board [] {
    let state = (aggregate_state)
    let rows = ($state.vms | each {|v| render-vm-row $v $state.installs_recent } | str join "\n")
    let installs_repo = (html-esc ($env.VM_SOFTWARE_REPO? | default '<unset>'))

    let body = $"<main class=\"container\">
  <header>
    <hgroup>
      <h1>vm-servers</h1>
      <p>Read-only status board. VMs from <code>state/vms.jsonl</code>; installs from <code>($installs_repo)/state/installs.jsonl</code>.</p>
    </hgroup>
  </header>

  <section>
    <h2>VMs</h2>
    <figure>
      <table>
        <thead>
          <tr><th scope=\"col\">label</th><th scope=\"col\">provider</th><th scope=\"col\">last action</th><th scope=\"col\">ip</th><th scope=\"col\">installs</th></tr>
        </thead>
        <tbody>
($rows)
        </tbody>
      </table>
    </figure>
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
        ["GET", "/"]          => { render-status-board }
        ["GET", "/api/state"] => { aggregate_state | to json }
        ["GET", "/api/runs"]  => {
            # Derived runs view — same data the CLI `runs:show` task prints.
            ^nu state/runs.nu --json
        }
        _ => { $"not found: ($method) ($path)\n" }
    }
}
