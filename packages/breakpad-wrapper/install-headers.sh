#!/bin/bash
# Install headers
# Args: $1 = staging directory, $2 = source directory

STAGING="$1"
SOURCE="$2"

# Create main include directories
mkdir -p "$STAGING/usr/include"

# Install headers
cp "$SOURCE/breakpad_wrapper.h" "$STAGING/usr/include/" 2>/dev/null || true

echo "Headers installed to $STAGING/usr/include"
