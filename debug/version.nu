# Show dockur/windows version: pinned in cloud-init, running on live VM,
# latest available on GitHub.

print "=== pinned in cloud-init ==="
glob "cloud-init-*.yaml" | each {|f|
    open $f | lines | where ($it | str contains "dockurr/windows") | each {|l| print $"  ($l | str trim)" }
} | ignore

print "=== running on live VM ==="
let probe = (mise run vm:ip | complete)
if $probe.exit_code != 0 {
    print "  no VM up"
} else {
    let ip = ($probe.stdout | str trim)
    let key = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)
    let logs = (^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" 'docker logs windows_batch_processor 2>&1' | complete)
    if $logs.exit_code == 0 {
        $logs.stdout | lines | find -r 'Windows for Docker v[0-9.]+' | first | default "  (version not detected in logs)" | print $"  ($in)"
    }
}

print "=== latest available on GitHub ==="
^gh release list --repo dockur/windows --limit 3 | lines | first 3 | each {|l| print $"  ($l)" } | ignore
