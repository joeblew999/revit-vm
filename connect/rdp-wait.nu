# Block until the VM accepts TCP on 3389 — the signal Windows finished
# OOBE and the RDP service is up. Polls every 30s, 90 min max. macOS
# notification on success or timeout.

let ip = (match $env.VM_PROVIDER {
    "hetzner" => (nu providers/hetzner/ip.nu),
    "vultr"   => (nu providers/vultr/ip.nu),
    _ => { print -e $"VM_PROVIDER must be hetzner|vultr \(got '($env.VM_PROVIDER)'\)"; exit 1 }
} | str trim)

print $"polling ($ip):3389 \(every 30s, max 90 min\)..."

job spawn --description "rdp-wait" {
    mut elapsed = 0
    let max = 90 * 60
    loop {
        let probe = (^nc -z -w 3 $ip "3389" | complete)
        if $probe.exit_code == 0 {
            {status: "ready", elapsed: $elapsed} | job send 0
            return
        }
        if $elapsed >= $max {
            {status: "timeout", elapsed: $elapsed} | job send 0
            return
        }
        sleep 30sec
        $elapsed = $elapsed + 30
        print -n $"[t+($elapsed)s] not yet\r"
    }
}

let result = (job recv --timeout 91min)
if $result.status == "ready" {
    print $"\n[t+($result.elapsed)s] 3389 accepting — Windows is RDP-ready"
    ^osascript -e 'display notification "Windows is RDP-ready — run mise run rdp:open" with title "vm-servers" sound name "Glass"' out+err> /dev/null
} else {
    print $"\n[t+($result.elapsed)s] timed out — investigate via mise run viewer:open"
    ^osascript -e 'display notification "RDP wait timed out after 90 min" with title "vm-servers" sound name "Basso"' out+err> /dev/null
    exit 1
}
