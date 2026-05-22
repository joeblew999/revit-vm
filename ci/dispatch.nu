# Smoke-test lifecycle/dispatch.nu's error paths. Sets $env.VM_PROVIDER
# directly (overrides mise's [env] injection because nu env-vars apply
# only to children spawned BY this script — not what mise injected
# into THIS script's env).

def check-bad-provider [] {
    print "→ dispatcher rejects bad provider"
    $env.VM_PROVIDER = "garbage"
    let out = (^nu lifecycle/dispatch.nu up | complete)
    if not ($out.stderr | str contains "VM_PROVIDER must be") {
        print -e $"  FAIL: expected 'VM_PROVIDER must be' in stderr"
        print -e $"  stderr: ($out.stderr)"
        print -e $"  stdout: ($out.stdout)"
        return false
    }
    print "  ok"
    true
}

def check-missing-action [] {
    print "→ dispatcher rejects missing action"
    $env.VM_PROVIDER = "hetzner"
    let out = (^nu lifecycle/dispatch.nu nonexistent-action | complete)
    if not ($out.stderr | str contains "no such action") {
        print -e $"  FAIL: expected 'no such action' in stderr"
        print -e $"  stderr: ($out.stderr)"
        print -e $"  stdout: ($out.stdout)"
        return false
    }
    print "  ok"
    true
}

mut failures = 0
if not (check-bad-provider) { $failures = $failures + 1 }
if not (check-missing-action) { $failures = $failures + 1 }

if $failures > 0 {
    print -e $"\n($failures) dispatcher check\(s\) failed"
    exit 1
}
print "\nall dispatcher checks passed"
