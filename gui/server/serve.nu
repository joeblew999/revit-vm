# http-nu entry. Called as `http-nu $addr gui/server/serve.nu` from the
# `gui:serve` mise task. Defines the closure http-nu invokes per request.
#
# Lives inside vm-servers, so `vms.jsonl` is the local repo's own state
# file (state/vms.jsonl). Installs state comes from the sibling vm-software
# repo clone via $VM_SOFTWARE_REPO.
#
# Skeleton — read-only status board. Returns one HTML page on GET /,
# JSON state on GET /api/state, and 404 elsewhere.

def aggregate_state [] {
    let vms_path = "state/vms.jsonl"
    let installs_path = $"($env.VM_SOFTWARE_REPO)/state/installs.jsonl"

    let vms = (if ($vms_path | path exists) {
        open $vms_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    let installs = (if ($installs_path | path exists) {
        open $installs_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    let latest_vms = ($vms | group-by label | values | each {|grp| $grp | sort-by ts | last })

    {
        vms: $latest_vms,
        installs_count: ($installs | length),
        installs_recent: ($installs | sort-by ts | last 10)
    }
}

def render_status_board [] {
    let state = (aggregate_state)
    let rows = ($state.vms | each {|v|
        let installs_for_vm = ($state.installs_recent | where vm_label == $v.label | length)
        $"<tr><td>($v.label)</td><td>($v.provider? | default '-')</td><td>($v.action? | default '-')</td><td>($v.ip? | default '-')</td><td>($installs_for_vm) recent</td></tr>"
    } | str join "\n")

    let html = $"<!doctype html>
<html><head>
<title>vm-servers gui</title>
<link rel='stylesheet' href='/static/style.css'>
</head><body>
<h1>vm-servers</h1>
<p>Read-only status board. Local state from <code>state/vms.jsonl</code>;
installs from <code>($env.VM_SOFTWARE_REPO)/state/installs.jsonl</code>.</p>
<h2>VMs</h2>
<table>
  <thead><tr><th>label</th><th>provider</th><th>last action</th><th>ip</th><th>installs</th></tr></thead>
  <tbody>
($rows)
  </tbody>
</table>
<h2>Recent installs</h2>
<pre>($state.installs_recent | to json --indent 2)</pre>
</body></html>"

    {body: $html, headers: {"Content-Type": "text/html; charset=utf-8"}}
}

{|req|
    let path = ($req.path | default "/")
    let method = ($req.method | default "GET")

    match [$method, $path] {
        ["GET", "/"]            => { render_status_board }
        ["GET", "/api/state"]   => { aggregate_state | to json }
        _                       => {
            {body: $"not found: ($method) ($path)", status: 404}
        }
    }
}
