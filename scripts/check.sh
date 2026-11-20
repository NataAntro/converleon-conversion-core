#!/usr/bin/env bash
set -euo pipefail

swift format lint --configuration .swift-format --recursive Sources Tests Package.swift
swift build
bash scripts/check-coverage.sh
