#!/bin/sh
# Runs the iOS unit tests on an available iPhone simulator.
#
# The destination is resolved at runtime rather than hardcoded, so this keeps
# working when Xcode or the CI runner image changes its set of simulators. A
# simulator that is already booted is preferred, which makes this reuse the one
# the e2e job boots instead of starting a second.
set -e

SCHEME="SmartcompanionNativeAudioPlayer"

udid_matching() {
    xcrun simctl list devices available | grep -m1 -E "$1" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" || true
}

UDID=$(udid_matching "^ +iPhone.*\(Booted\)")

if [ -z "$UDID" ]; then
    UDID=$(udid_matching "^ +iPhone")
fi

if [ -z "$UDID" ]; then
    echo "error: no available iPhone simulator found" >&2
    xcrun simctl list devices available >&2
    exit 1
fi

echo "Running iOS unit tests on simulator $UDID"
exec xcodebuild test -scheme "$SCHEME" -destination "id=$UDID"
