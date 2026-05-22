# Route handlers — pure functions called from server/serve.nu.

# Aggregate JSONL state from sibling repos into a single table joined on vm_label.
export def aggregate_state [] {
    let vms_path = $"($env.VM_SERVERS_REPO)/state/vms.jsonl"
    let installs_path = $"($env.VM_SOFTWARE_REPO)/state/installs.jsonl"

    let vms = (if ($vms_path | path exists) {
        open $vms_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    let installs = (if ($installs_path | path exists) {
        open $installs_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    # Latest record per vm_label.
    let latest_vms = ($vms | group-by label | values | each {|grp| $grp | sort-by ts | last })

    {
        vms: $latest_vms,
        installs_count: ($installs | length),
        installs_recent: ($installs | sort-by ts | last 10)
    }
}

# Render the read-only status board as HTML.
export def render_status_board [] {
    let state = (aggregate_state)
    let rows = ($state.vms | each {|v|
        let installs_for_vm = ($state.installs_recent | where vm_label == $v.label | length)
        $"<tr><td>($v.label)</td><td>($v.provider? | default '-')</td><td>($v.status? | default '-')</td><td>($v.ip? | default '-')</td><td>($installs_for_vm) recent</td></tr>"
    } | str join "\n")

    let html = $"<!doctype html>
<html><head>
<title>vm-gui</title>
<link rel='stylesheet' href='/static/style.css'>
</head><body>
<h1>vm-gui</h1>
<p>Read-only status board. Sibling state aggregated from
<code>($env.VM_SERVERS_REPO)/state/vms.jsonl</code> +
<code>($env.VM_SOFTWARE_REPO)/state/installs.jsonl</code>.</p>
<h2>VMs</h2>
<table>
  <thead><tr><th>label</th><th>provider</th><th>status</th><th>ip</th><th>installs</th></tr></thead>
  <tbody>
($rows)
  </tbody>
</table>
<h2>Recent installs</h2>
<pre>($state.installs_recent | to json --indent 2)</pre>
</body></html>"

    {body: $html, headers: {"Content-Type": "text/html; charset=utf-8"}}
}
