# Vultr snapshot via R2 transit. The pipeline:
#   1. SSH into BM, ensure awscli is installed
#   2. docker stop (caller already did this in `stop`, but idempotent here)
#   3. gzip < qcow2 | aws s3 cp - to R2
#   4. aws s3 presign on Mac side → URL valid for 24h
#   5. vultr-cli snapshot create-url → Vultr fetches and registers
#   6. Poll until snapshot status = complete
#   7. aws s3 rm to delete the R2 object (Vultr has its own copy now)
#
# Expect 30-60 min for a ~40GB qcow2 over typical WAN bandwidth.

# Pre-flight checks.
if ($env.R2_ENDPOINT | is-empty) { print -e "R2_ENDPOINT not set — run `mise run r2:bootstrap`"; exit 1 }
if ($env.R2_BUCKET | is-empty)   { print -e "R2_BUCKET not set — run `mise run r2:bootstrap`"; exit 1 }
let r2_id = (^fnox get R2_ACCESS_KEY_ID | complete)
let r2_sec = (^fnox get R2_SECRET_ACCESS_KEY | complete)
if $r2_id.exit_code != 0 or $r2_sec.exit_code != 0 {
    print -e "R2 credentials missing in keychain — see `mise run r2:bootstrap`"
    exit 1
}

let listing = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | from json)
let matches = ($listing.bare_metals? | default [] | where label == $env.VULTR_LABEL)
if ($matches | is-empty) {
    print -e $"no Vultr Bare Metal with label '($env.VULTR_LABEL)' — nothing to snapshot"
    exit 1
}
let bm = ($matches | first)
let ip = $bm.main_ip
let key_file = ($env.SSH_KEY_FILE | str replace "~" $env.HOME)

let ts = (date now | format date "%Y%m%d-%H%M%S")
let desc = $"vm-servers-($ts)"
let s3_key = $"($desc).qcow2.gz"
let access_key = ($r2_id.stdout | str trim)
let secret_key = ($r2_sec.stdout | str trim)

print $"snapshot pipeline starting:"
print $"  BM:      ($bm.id) @ ($ip)"
print $"  R2:      s3://($env.R2_BUCKET)/($s3_key)"
print $"  via:     ($env.R2_ENDPOINT)"
print $"  expect:  30-60 min for upload, +few minutes for Vultr to fetch and index"
print ""

# Step 1+2+3: SSH in and run the upload pipeline. Use a template string
# with placeholders to avoid nushell-interpolation conflicts with bash
# $() / parens. Substitute values via `str replace` before sending.
let remote_template = '
set -e
command -v aws >/dev/null 2>&1 || {
  echo "  installing awscli on the BM (one-time)..."
  apt-get update -qq && apt-get install -y -qq awscli
}
docker stop --timeout=120 windows 2>/dev/null || true
QCOW2=$(ls /root/windows_storage/*.qcow2 2>/dev/null | head -1)
[ -z "$QCOW2" ] && { echo "no qcow2 found in /root/windows_storage"; exit 1; }
SIZE=$(du -h "$QCOW2" | cut -f1)
echo "  source: $QCOW2 ($SIZE)"
AWS_ACCESS_KEY_ID=__ACCESS__ AWS_SECRET_ACCESS_KEY=__SECRET__ \
  gzip -1 < "$QCOW2" | \
  aws --endpoint-url __ENDPOINT__ s3 cp - s3://__BUCKET__/__KEY__ --no-progress
'

let remote_script = ($remote_template
    | str replace --all "__ACCESS__" $access_key
    | str replace --all "__SECRET__" $secret_key
    | str replace --all "__ENDPOINT__" $env.R2_ENDPOINT
    | str replace --all "__BUCKET__" $env.R2_BUCKET
    | str replace --all "__KEY__" $s3_key)

print "→ streaming qcow2 from BM to R2..."
$remote_script | ^ssh -i $key_file -o StrictHostKeyChecking=accept-new $"root@($ip)" bash -s
let upload_rc = ($env.LAST_EXIT_CODE? | default 0)
if $upload_rc != 0 {
    print -e $"upload failed \(rc=($upload_rc)\) — R2 object may be partial; check via aws s3 ls"
    exit $upload_rc
}

# Step 4: presign for Vultr to fetch.
print "→ presigning R2 URL for Vultr (24h TTL)..."
let presigned = (^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 presign $"s3://($env.R2_BUCKET)/($s3_key)" --expires-in 86400 | str trim)
if ($presigned | is-empty) {
    print -e "presign returned empty URL — aborting"
    exit 1
}

# Step 5: register with Vultr.
print $"→ registering snapshot with Vultr \(($desc)\)..."
let create_out = (^fnox exec --if-missing ignore -- vultr-cli snapshot create-url --url $presigned --description $desc -o json | from json)
let snap_id = ($create_out.snapshot?.id? | default null)
if $snap_id == null {
    print -e "vultr-cli snapshot create-url returned no snapshot ID"
    exit 1
}
print $"  Vultr snapshot id: ($snap_id) — polling for ready..."

# Step 6: poll until complete.
mut waited = 0
let max_wait = 60 * 60
loop {
    let get = (^fnox exec --if-missing ignore -- vultr-cli snapshot get $snap_id -o json | from json)
    let status = ($get.snapshot?.status? | default "unknown")
    if $status == "complete" {
        print $"  ready after ($waited)s"
        break
    }
    if $waited > $max_wait {
        print -e $"timed out at ($waited)s — current status: ($status)"
        exit 1
    }
    sleep 30sec
    $waited = $waited + 30
    print $"  status=($status), waited ($waited)s"
}

# Step 7: cleanup R2 transit object.
print "→ deleting R2 transit object (Vultr has its own copy now)..."
^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 rm $"s3://($env.R2_BUCKET)/($s3_key)" --quiet

nu state/append.nu snapshotted --label $env.VULTR_LABEL --description $desc --snapshot-id $snap_id

print ""
print $"snapshot created: ($snap_id) — `mise run snapshot:list` to see it."
