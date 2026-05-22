# Quick health check: container state, mounts, restart policy, ports.

let ip = (mise run vm:ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
print $"=== VM: ($ip) ==="
print "--- container ---"
^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" 'bash -c "docker ps -a; echo \"restart policy: $(docker inspect windows_batch_processor --format {{.HostConfig.RestartPolicy.Name}} 2>/dev/null)\"; echo \"mounts:\"; docker inspect windows_batch_processor --format \"{{range .Mounts}}  {{.Source}} -> {{.Destination}}{{println}}{{end}}\" 2>/dev/null"'
print "--- external port probes ---"
for port in [22 8006 3389] {
    let label = match $port { 22 => "(SSH)   ", 8006 => "(viewer)", 3389 => "(RDP)   " }
    let probe = (^nc -z -w 3 $ip ($port | into string) | complete)
    if $probe.exit_code == 0 {
        print $"($port) ($label): open"
    } else {
        print $"($port) ($label): CLOSED"
    }
}
