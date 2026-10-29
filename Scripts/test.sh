#!/bin/bash
# Runs the unit checks (plain executable; XCTest/Swift Testing need Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c debug LingTipChecks
