#!/bin/bash
# parse-control.sh - Parse Debian-style control files for package metadata
# This script provides functions to extract metadata from packages/<project>/control files

set -euo pipefail

# Extract a single-line field from control file
# Args: $1 = field name, $2 = control file path
# Returns: field value (without field name)
get_control_field() {
    local field=$1
    local control_file=$2
    
    if [ ! -f "$control_file" ]; then
        echo ""
        return 1
    fi
    
    grep "^${field}:" "$control_file" | head -1 | sed "s/^${field}: *//" || echo ""
}

# Extract multi-line field from control file (like Description)
# Args: $1 = field name, $2 = control file path
# Returns: field value including continuation lines
get_control_field_multiline() {
    local field=$1
    local control_file=$2
    
    if [ ! -f "$control_file" ]; then
        echo ""
        return 1
    fi
    
    # Extract field and all continuation lines (lines starting with space)
    awk "/^${field}:/ { p=1; print; next } p && /^ / { print; next } p { exit }" "$control_file" || echo ""
}

# Parse entire control file and export common variables
# Args: $1 = project name
# Exports: SOURCE, VERSION, UPSTREAM_URL, UPSTREAM_REF, PACKAGE, ARCHITECTURE, DEPENDS, BUILD_DEPENDS, DESCRIPTION
parse_control_file() {
    local project=$1
    local control_file="packages/$project/control"
    
    if [ ! -f "$control_file" ]; then
        echo "ERROR: Control file not found: $control_file" >&2
        return 1
    fi
    
    # Export common fields as environment variables
    export SOURCE=$(get_control_field "Source" "$control_file")
    export VERSION=$(get_control_field "Version" "$control_file")
    export UPSTREAM_URL=$(get_control_field "Upstream-URL" "$control_file")
    export UPSTREAM_REF=$(get_control_field "Upstream-Ref" "$control_file")
    export PACKAGE=$(get_control_field "Package" "$control_file")
    export ARCHITECTURE=$(get_control_field "Architecture" "$control_file")
    export DEPENDS=$(get_control_field "Depends" "$control_file")
    export BUILD_DEPENDS=$(get_control_field "Build-Depends" "$control_file")
    export DESCRIPTION=$(get_control_field_multiline "Description" "$control_file")
    
    # Validate required fields
    if [ -z "$VERSION" ] || [ -z "$UPSTREAM_URL" ] || [ -z "$UPSTREAM_REF" ]; then
        echo "ERROR: Missing required fields in control file (Version, Upstream-URL, or Upstream-Ref)" >&2
        return 1
    fi
    
    return 0
}

# List all binary packages defined in control file
# Args: $1 = control file path
# Returns: List of package names (one per line)
list_binary_packages() {
    local control_file=$1
    
    if [ ! -f "$control_file" ]; then
        echo ""
        return 1
    fi
    
    # Find all "Package:" declarations (skip "Source:")
    grep "^Package:" "$control_file" | sed 's/^Package: *//' || echo ""
}

# Export functions for use in other scripts
export -f get_control_field get_control_field_multiline parse_control_file list_binary_packages
