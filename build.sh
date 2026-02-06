#!/bin/bash
set -e

echo "🧹 Cleaning up..."
rm -rf .build
swift package reset

# Generate Icons
./scripts/generate_icons.sh

echo "🦞 Building Clawsy..."

# Check for swift
if ! command -v swift &> /dev/null; then
    echo "❌ Error: 'swift' command not found. Do you have Xcode installed?"
    exit 1
fi

# Build using Swift Package Manager
# Configuration: debug (for now, easy dev), release (later for dist)
swift build -c debug

echo "✅ Build successful!"
echo "🚀 Run with: ./.build/debug/Clawsy"
