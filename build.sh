#!/bin/bash
set -e

echo "🧹 Cleaning up..."
rm -rf .build

echo "🎨 Generating Icons..."
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh || { echo "❌ Icon generation failed"; exit 1; }
else
    echo "⚠️ Icon script missing"
fi

echo "🦞 Building Clawsy (Debug)..."
# Check for swift
if ! command -v swift &> /dev/null; then
    echo "❌ Error: 'swift' command not found. Do you have Xcode installed?"
    exit 1
fi

swift build -c debug -v

echo "✅ Build successful!"
echo "🚀 Run with: swift run Clawsy"
