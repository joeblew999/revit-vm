# Derived view over state/vms.jsonl: pair each provision event with its
# subsequent destroy to produce per-run records (label, provider, started,
# stopped, duration_hr, flavor/sku, snapshot_id).
#
# A "run" is bounded by:
#   start  ← provisioned | provisioned-from-snapshot   (event for $label)
#   stop   ← destroyed                                  (event for $label)
#
# Snapshotted events that fall inside a run are attributed to it (most
# recent wins). An unclosed run (no destroy yet) reports stopped=null and
# duration_hr based on `now`.
#
# Usage:
#   nu state/runs.nu                  # print table
#   nu state/runs.nu --json           # emit JSONL (one record per run)
#
# This is a VIEW, not state — it reads vms.jsonl, derives, and prints.
# Nothing is written to disk.

def load_events [] {
    let path = "state/vms.jsonl"
    if not ($path | path exists) { return [] }
    open $path | lines | where ($it | is-not-empty) | each {|l| $l | from json } | sort-by ts
}

def derive_runs [events: list] {
    mut runs = []
    mut open_by_label = {}  # label -> partial run record

    for e in $events {
        let label = ($e.label? | default "")
        if ($label | is-empty) { continue }

        match $e.action {
            "provisioned" | "provisioned-from-snapshot" => {
                # Close any prior open run for this label (orphaned start).
                if ($open_by_label | get -o $label) != null {
                    $runs = ($runs | append ($open_by_label | get $label))
                }
                let started = {
                    label: $label,
                    provider: ($e.provider? | default ""),
                    started_at: $e.ts,
                    stopped_at: null,
                    duration_hr: null,
                    sku: ($e.flavor? | default ($e.plan? | default "")),
                    region: ($e.region? | default ""),
                    started_from: $e.action,
                    snapshot_id: ($e.snapshot_id? | default null),
                }
                $open_by_label = ($open_by_label | upsert $label $started)
            },
            "snapshotted" => {
                if ($open_by_label | get -o $label) != null {
                    let cur = ($open_by_label | get $label)
                    let updated = ($cur | upsert snapshot_id ($e.snapshot_id? | default $cur.snapshot_id))
                    $open_by_label = ($open_by_label | upsert $label $updated)
                }
            },
            "destroyed" => {
                if ($open_by_label | get -o $label) != null {
                    let cur = ($open_by_label | get $label)
                    let started = ($cur.started_at | into datetime)
                    let stopped = ($e.ts | into datetime)
                    let dur_sec = (($stopped - $started) / 1sec)
                    let closed = ($cur
                        | upsert stopped_at $e.ts
                        | upsert duration_hr (($dur_sec / 3600) | math round --precision 3))
                    $runs = ($runs | append $closed)
                    $open_by_label = ($open_by_label | reject $label)
                }
                # destroy without open run = orphan; skip silently.
            },
        }
    }

    # Any still-open runs: report duration to now, stopped=null.
    let now = (date now)
    for label in ($open_by_label | columns) {
        let cur = ($open_by_label | get $label)
        let started = ($cur.started_at | into datetime)
        let dur_sec = (($now - $started) / 1sec)
        let open_run = ($cur | upsert duration_hr (($dur_sec / 3600) | math round --precision 3))
        $runs = ($runs | append $open_run)
    }

    $runs | sort-by started_at
}

def "main" [--json] {
    let runs = (derive_runs (load_events))
    if $json {
        $runs | each {|r| $r | to json -r } | str join "\n" | print $in
    } else {
        if ($runs | is-empty) {
            print "(no runs yet — state/vms.jsonl is empty or only has orphan events)"
        } else {
            $runs | table -e
        }
    }
}
