# Print last-5-min Hetzner-side metrics (network peak, CPU avg/peak).
# Hetzner-only; Vultr has a different mechanism (vultr-cli bare-metal
# bandwidth) — emit a hint and exit 0 on Vultr.

if ($env.VM_PROVIDER != "hetzner") {
    print "debug:metrics is Hetzner-only (Vultr equivalent: vultr-cli bare-metal bandwidth <id>)"
    exit 0
}

# 5-minute window — date math handled by `date now` and string formatting.
let end_t = (date now | format date "%Y-%m-%dT%H:%M:%SZ")
let start_t = ((date now) - 5min | format date "%Y-%m-%dT%H:%M:%SZ")

print "=== network (bytes/s) ==="
let net = (^fnox exec --if-missing ignore -- hcloud server metrics $env.SERVER_NAME --type network --start $start_t --end $end_t -o json | from json)
$net.metrics.time_series | transpose key val | each {|row|
    let peak = ($row.val.values | each {|v| $v.1 | into float } | math max | math floor)
    print $"  ($row.key): peak=($peak)"
} | ignore

print "=== CPU (%) ==="
let cpu = (^fnox exec --if-missing ignore -- hcloud server metrics $env.SERVER_NAME --type cpu --start $start_t --end $end_t -o json | from json)
$cpu.metrics.time_series | transpose key val | each {|row|
    let vals = ($row.val.values | each {|v| $v.1 | into float })
    let avg = ($vals | math avg | math floor)
    let peak = ($vals | math max | math floor)
    print $"  ($row.key): avg=($avg)%, peak=($peak)%"
} | ignore
