#!/bin/sh
# Rebuilds Packages/UncialCore/Sources/UncialCore/Resources/beautiful-mermaid.min.js (and
# BEAUTIFUL-MERMAID-LICENSE): beautiful-mermaid's renderMermaidSVG with elkjs and entities, bundled by
# esbuild into one IIFE that leaves `beautifulMermaid` on the global object, which is what
# MermaidRenderer reads in its JavaScriptCore context. The pins reproduce the committed file byte for
# byte (checked 2026-09-26).
#
# Usage: scripts/build-mermaid.sh   (needs node and npm; the pinned packages go into a temp dir)
set -eu

BEAUTIFUL_MERMAID_VERSION=1.1.3
ELKJS_VERSION=0.11.1
ENTITIES_VERSION=7.0.1
ESBUILD_VERSION=0.24.2

root=$(cd "$(dirname "$0")/.." && pwd)
resources="$root/Packages/UncialCore/Sources/UncialCore/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# elkjs and entities are named so npm takes the pinned versions for beautiful-mermaid's caret ranges.
npm install --silent --no-audit --no-fund "beautiful-mermaid@$BEAUTIFUL_MERMAID_VERSION" "elkjs@$ELKJS_VERSION" \
  "entities@$ENTITIES_VERSION" "esbuild@$ESBUILD_VERSION"

echo "export { renderMermaidSVG } from 'beautiful-mermaid';" > entry.js
npx esbuild entry.js --bundle --minify --format=iife --global-name=beautifulMermaid --target=es2020 \
  --outfile="$resources/beautiful-mermaid.min.js"

{
  echo "beautiful-mermaid $BEAUTIFUL_MERMAID_VERSION (https://github.com/lukilabs/beautiful-mermaid), bundled with esbuild $ESBUILD_VERSION as an IIFE"
  echo "exposing renderMermaidSVG. It contains elkjs $ELKJS_VERSION and entities $ENTITIES_VERSION; their notices follow."
  echo
  echo "=== beautiful-mermaid (MIT) ==="
  echo
  cat node_modules/beautiful-mermaid/LICENSE
  echo
  echo "=== elkjs (EPL-2.0) ==="
  echo
  cat node_modules/elkjs/LICENSE.md
  echo
  echo "=== entities (BSD-2-Clause) ==="
  echo
  cat node_modules/entities/LICENSE
} > "$resources/BEAUTIFUL-MERMAID-LICENSE"

ls -l "$resources/beautiful-mermaid.min.js" "$resources/BEAUTIFUL-MERMAID-LICENSE"
