# Parse-check every .nu file in the repo using nushell's built-in
# `nu-check` command directly (no subprocess per file). Same script
# runs from `mise run check:syntax` locally and in CI.

let files = (glob "**/*.nu" --exclude ["**/target/**"])
mut failures = 0

for f in $files {
    let path = ($f | path relative-to (pwd))
    let ok = (try { nu-check $f } catch { false })
    if $ok {
        print $"  ok   ($path)"
    } else {
        print -e $"  FAIL ($path)"
        $failures = $failures + 1
    }
}

if $failures > 0 {
    print -e $"\n($failures) of ($files | length) file\(s\) failed parse check"
    exit 1
}

print $"\nall ($files | length) nu files parsed cleanly"
