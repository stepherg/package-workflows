#!/bin/bash
# Install headers for utopia
# Args: $1 = staging directory, $2 = source directory

STAGING="$1"
SOURCE="$2"

# Create main include directories
mkdir -p "$STAGING/usr/include/syscfg"

# Install syscfg headers
cp "$SOURCE/source/include/syscfg/"*.h "$STAGING/usr/include/syscfg/" 2>/dev/null || true

echo "Headers installed to $STAGING/usr/include/syscfg"