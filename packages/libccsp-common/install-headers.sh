#!/bin/bash
# Install headers for ccsp-common-library
# Args: $1 = staging directory, $2 = source directory

STAGING="$1"
SOURCE="$2"

# Create main include directories
mkdir -p "$STAGING/usr/include/ccsp"
mkdir -p "$STAGING/usr/include/ccsp/linux"

# Install debug_api headers
cp "$SOURCE/source/debug_api/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true

# Install util_api headers
cp "$SOURCE/source/util_api/ansc/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/asn.1/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/http/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/slap/components/SlapVarConverter"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/stun/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/tls/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/util_api/web/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true

# Install cosa headers
cp "$SOURCE/source/cosa/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/cosa/package/slap/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/cosa/package/system/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/cosa/include/linux"/*.h "$STAGING/usr/include/ccsp/linux/" 2>/dev/null || true
cp "$SOURCE/source/cosa/include/linux"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true

# Install ccsp headers
cp "$SOURCE/source/ccsp/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/ccsp/custom"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/ccsp/components/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/ccsp/components/common/MessageBusHelper/include"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/ccsp/components/common/PoamIrepFolder"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true

# Install dm_pack headers
cp "$SOURCE/source/dm_pack/dm_pack_create_func.h" "$STAGING/usr/include/ccsp/" 2>/dev/null || true
cp "$SOURCE/source/dm_pack/dm_pack_xml_helper.h" "$STAGING/usr/include/ccsp/" 2>/dev/null || true

echo "Headers installed to $STAGING/usr/include/ccsp"
