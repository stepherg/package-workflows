#!/bin/bash
# Install headers for telemetry
# Args: $1 = staging directory, $2 = source directory

STAGING="$1"
SOURCE="$2"

# Create main include directories
mkdir -p "$STAGING/usr/include"

# Install headers
cp "$SOURCE/include"/*.h "$STAGING/usr/include/" 2>/dev/null || true

echo "Headers installed to $STAGING/usr/include"
