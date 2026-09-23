#!/usr/bin/env bash
# Stream unified logs for MentraQR from a connected iPhone (run while reproducing the issue).
set -euo pipefail

PREDICATE='subsystem == "com.local.mentraqr" OR process == "MentraQR" OR eventMessage CONTAINS[c] "GStreamer" OR eventMessage CONTAINS[c] "WHIP" OR eventMessage CONTAINS[c] "Fill light" OR eventMessage CONTAINS[c] "rgb_led" OR eventMessage CONTAINS[c] "RGB LED"'

echo "Streaming logs (Ctrl+C to stop). Filter: $PREDICATE"
echo "Tip: In Console.app, select your iPhone and search for MentraQR or com.local.mentraqr"
echo ""

/usr/bin/log stream --style compact --level debug --predicate "$PREDICATE"
