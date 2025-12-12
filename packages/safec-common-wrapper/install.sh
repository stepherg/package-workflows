#!/bin/bash
# Custom installation script for safec-common-wrapper
# This package contains only a header file, no upstream build needed

set -euo pipefail

PROJECT_DIR="/workspace/packages/safec-common-wrapper"
FILES_DIR="$PROJECT_DIR/files"

# Copy header file to staging directory
if [ -f "$FILES_DIR/safec_lib.h" ]; then
    mkdir -p "$STAGING_DIR/usr/include"
    cp "$FILES_DIR/safec_lib.h" "$STAGING_DIR/usr/include/"
    echo "Installed safec_lib.h to /usr/include"
else
    echo "ERROR: safec_lib.h not found in $FILES_DIR"
    exit 1
fi
