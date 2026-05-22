# CLI view of the joined vms + installs state. Same aggregator used by
# the http-nu server (see gui/state/lib.nu).

use lib.nu *

aggregate_state | table
