# Validate state/vms.jsonl against state/vms.schema.json. Structural
# pure-nu check (no oneOf branch enforcement — for that, install
# check-jsonschema via pip and run `check-jsonschema --schemafile
# state/vms.schema.json state/vms.jsonl`).
#
# Verifies:
#   - Every line parses as JSON
#   - Each record has the top-level required fields (action, label, ts, provider)
#   - action is in the schema's enum
#   - provider is in hetzner|vultr

let jsonl_path = "state/vms.jsonl"
let schema_path = "state/vms.schema.json"

if not ($jsonl_path | path exists) {
    print "(state/vms.jsonl missing — nothing to validate)"
    exit 0
}
if ((open $jsonl_path | str trim) | is-empty) {
    print "(state/vms.jsonl empty — nothing to validate)"
    exit 0
}

let schema = (open $schema_path)
let valid_actions = ($schema.oneOf | each {|v| $v.properties.action.const })
let required_top = $schema.required

mut failures = 0
let lines = (open $jsonl_path | lines | where ($it | str trim | is-not-empty))

for line in $lines {
    let record = (try { $line | from json } catch { null })
    if $record == null {
        print -e $"  FAIL: line not parseable as JSON: ($line)"
        $failures = $failures + 1
        continue
    }
    let cols = ($record | columns)
    for f in $required_top {
        if not ($f in $cols) {
            print -e $"  FAIL: line missing required field '($f)': ($line)"
            $failures = $failures + 1
        }
    }
    if ("action" in $cols) and (not ($record.action in $valid_actions)) {
        print -e $"  FAIL: action '($record.action)' not in: ($valid_actions)"
        $failures = $failures + 1
    }
    if ("provider" in $cols) and (not ($record.provider in ["hetzner", "vultr"])) {
        print -e $"  FAIL: provider '($record.provider)' not in [hetzner, vultr]"
        $failures = $failures + 1
    }
}

if $failures > 0 {
    print -e $"\n($failures) validation failure\(s\)"
    exit 1
}

print $"validated ($lines | length) record\(s\) against ($schema_path)"
