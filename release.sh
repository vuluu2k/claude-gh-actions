#!/bin/bash
set -e

# Usage: ./release.sh <version>
# Example: ./release.sh v1.0.0
#          ./release.sh v1.2.3

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh v1.0.0"
  echo ""
  echo "Recent tags:"
  git tag --sort=-v:refname | head -10
  exit 1
fi

# Extract major version (v1.0.0 -> v1)
MAJOR=$(echo "$VERSION" | grep -oE '^v[0-9]+')

if [ -z "$MAJOR" ]; then
  echo "Error: version must start with v (e.g. v1.0.0)"
  exit 1
fi

echo "Version:  $VERSION"
echo "Major:    $MAJOR"
echo ""

# Tag + push
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"

# Move major tag to latest
git tag -fa "$MAJOR" -m "Update $MAJOR to $VERSION"
git push origin "$MAJOR" --force

# Move latest tag
git tag -fa latest -m "Latest: $VERSION"
git push origin latest --force

echo ""
echo "Done. Released $VERSION"
echo "  @${MAJOR}    -> $VERSION"
echo "  @latest  -> $VERSION"
