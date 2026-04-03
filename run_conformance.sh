#!/bin/bash
# Quick conformance score check
swift build --build-tests 2>/dev/null
swift test --filter "runAllConformanceFixtures" 2>&1 | grep -E "===|\.swift:|Conformance"
