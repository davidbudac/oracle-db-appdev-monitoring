#!/bin/bash
# Script to create a GitHub release with AIX binary
# Usage: ./create-release.sh v1.0.0

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./create-release.sh <version>"
    echo "Example: ./create-release.sh v1.0.0"
    exit 1
fi

echo "Building AIX binary for $VERSION..."
GOOS=aix GOARCH=ppc64 CGO_ENABLED=0 go build -tags goora -o oracledb_exporter-aix-ppc64 main.go
tar -czf oracledb_exporter-aix-ppc64.tar.gz oracledb_exporter-aix-ppc64

echo "Creating git tag..."
git tag "$VERSION"
git push origin "$VERSION"

echo "Creating GitHub release..."
gh release create "$VERSION" \
    oracledb_exporter-aix-ppc64.tar.gz \
    --title "$VERSION" \
    --generate-notes

echo "Done! Release created at: https://github.com/davidbudac/oracle-db-appdev-monitoring/releases/tag/$VERSION"

# Cleanup
rm oracledb_exporter-aix-ppc64 oracledb_exporter-aix-ppc64.tar.gz
