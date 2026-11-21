#!/bin/zsh
# Compiles the UI-independent core with Tests/CoreChecks.swift and runs the checks
# (PKCE, OAuth callback validation, institution codes, change diffing, parsing, calendar).
set -e
cd "${0:A:h}/.."
out=$(mktemp -d)
cp Tests/CoreChecks.swift "$out/main.swift" # top-level code must live in main.swift
swiftc -swift-version 5 -o "$out/core-checks" Kreten/Core/*.swift Kreten/Model/Diary.swift Kreten/Model/SchoolCalendar.swift "$out/main.swift"
"$out/core-checks"
