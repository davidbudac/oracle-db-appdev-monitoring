#!/bin/bash
# Script to create a GitHub release with AIX and Windows binaries
# Usage: ./create-release.sh v1.0.0

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./create-release.sh <version>"
    echo "Example: ./create-release.sh v1.0.0"
    exit 1
fi

# Check if release already exists and delete it
echo "Checking for existing release..."
if gh release view "$VERSION" &>/dev/null; then
    echo "Release $VERSION already exists. Deleting..."
    gh release delete "$VERSION" --yes
    echo "Existing release deleted."
fi

# Check if tag already exists and delete it
echo "Checking for existing tag..."
if git rev-parse "$VERSION" &>/dev/null; then
    echo "Tag $VERSION already exists. Deleting..."
    git tag -d "$VERSION"
    git push origin ":refs/tags/$VERSION" 2>/dev/null || true
    echo "Existing tag deleted."
fi

echo "Building AIX ppc64 binary for $VERSION..."
GOOS=aix GOARCH=ppc64 CGO_ENABLED=0 go build -tags goora -o oracledb_exporter-aix-ppc64 main.go
tar -czf oracledb_exporter-aix-ppc64.tar.gz oracledb_exporter-aix-ppc64

echo "Building Windows x64 binary for $VERSION..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -tags godror -o oracledb_exporter-windows-amd64.exe main.go
zip oracledb_exporter-windows-amd64.zip oracledb_exporter-windows-amd64.exe

echo "Creating git tag..."
git tag "$VERSION"
git push origin "$VERSION"

echo "Creating GitHub release..."
gh release create "$VERSION" \
    oracledb_exporter-aix-ppc64.tar.gz \
    oracledb_exporter-windows-amd64.zip \
    --title "$VERSION" \
    --generate-notes

echo "Done! Release created at: https://github.com/davidbudac/oracle-db-appdev-monitoring/releases/tag/$VERSION"

# Cleanup
rm oracledb_exporter-aix-ppc64 oracledb_exporter-aix-ppc64.tar.gz
rm oracledb_exporter-windows-amd64.exe oracledb_exporter-windows-amd64.zip
