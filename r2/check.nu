# Verify R2 is wired up correctly: probe PUT/GET/DELETE on the bucket.

if ($env.R2_ENDPOINT | is-empty) {
    print -e "R2_ENDPOINT not set in mise.local.toml — run `mise run r2:bootstrap` first."
    exit 1
}
if ($env.R2_BUCKET | is-empty) {
    print -e "R2_BUCKET not set in mise.local.toml — run `mise run r2:bootstrap` first."
    exit 1
}

let probe = (^fnox get R2_ACCESS_KEY_ID | complete)
if $probe.exit_code != 0 {
    print -e "R2_ACCESS_KEY_ID missing in keychain — `fnox set -p keychain R2_ACCESS_KEY_ID`."
    exit 1
}
let probe2 = (^fnox get R2_SECRET_ACCESS_KEY | complete)
if $probe2.exit_code != 0 {
    print -e "R2_SECRET_ACCESS_KEY missing in keychain — `fnox set -p keychain R2_SECRET_ACCESS_KEY`."
    exit 1
}

let key = $"probe-(date now | format date '%Y%m%d-%H%M%S').txt"
let body = "hello from vm-servers r2:check"

print $"Probing s3://($env.R2_BUCKET)/($key) at ($env.R2_ENDPOINT)..."

# PUT
print "  → PUT"
$body | ^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 cp - $"s3://($env.R2_BUCKET)/($key)" --quiet
let put_rc = ($env.LAST_EXIT_CODE? | default 0)
if $put_rc != 0 { print -e "PUT failed"; exit 1 }

# GET
print "  → GET"
let got = (^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 cp $"s3://($env.R2_BUCKET)/($key)" - | str trim)
if $got != $body {
    print -e $"GET mismatch: expected '($body)', got '($got)'"
    exit 1
}

# DELETE
print "  → DELETE"
^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 rm $"s3://($env.R2_BUCKET)/($key)" --quiet
let del_rc = ($env.LAST_EXIT_CODE? | default 0)
if $del_rc != 0 { print -e "DELETE failed"; exit 1 }

print ""
print $"✅ R2 wired up: ($env.R2_ENDPOINT) bucket '($env.R2_BUCKET)' — PUT/GET/DELETE round-trip OK"
