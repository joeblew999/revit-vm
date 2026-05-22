# Block until the VM accepts TCP on 3389 — the signal Windows finished
# OOBE and the RDP service is up. Polls every 30s, 90 min max. macOS
# notification on success or timeout.

let ip = (mise run vm:ip | str trim)
mut elapsed = 0
let max = 90 * 60
print $"polling ($ip):3389 \(every 30s, max 90 min\)..."

while $elapsed <= $max {
    let probe = (^nc -z -w 3 $ip "3389" | complete)
    if $probe.exit_code == 0 {
        print $"\n[t+($elapsed)s] 3389 accepting — Windows is RDP-ready"
        ^osascript -e 'display notification "Windows is RDP-ready — run mise run rdp:open" with title "vm-servers" sound name "Glass"' out+err> /dev/null
        exit 0
    }
    print -n $"[t+($elapsed)s] not yet\r"
    sleep 30sec
    $elapsed = $elapsed + 30
}

print $"\n[t+($elapsed)s] timed out — investigate via mise run viewer:open"
^osascript -e 'display notification "RDP wait timed out after 90 min" with title "vm-servers" sound name "Basso"' out+err> /dev/null
exit 1
