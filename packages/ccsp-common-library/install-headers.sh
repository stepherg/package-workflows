#!/bin/bash
# Install headers for ccsp-common-library
# Args: $1 = staging directory, $2 = source directory

STAGING="$1"
SOURCE="$2"

mkdir -p "$STAGING/usr/include"

# Install CCSP headers
mkdir -p "$STAGING/usr/include/ccsp"
cp -r "$SOURCE/source/ccsp/include"/* "$STAGING/usr/include/ccsp/"
mkdir -p "$STAGING/usr/include/ccsp/components"
cp -r "$SOURCE/source/ccsp/components/include"/* "$STAGING/usr/include/ccsp/components/"
[ -d "$SOURCE/source/ccsp/custom" ] && cp "$SOURCE/source/ccsp/custom"/*.h "$STAGING/usr/include/ccsp/" 2>/dev/null || true

# Install COSA headers
mkdir -p "$STAGING/usr/include/cosa"
[ -d "$SOURCE/source/cosa/include" ] && cp -r "$SOURCE/source/cosa/include"/* "$STAGING/usr/include/cosa/" 2>/dev/null || true

# Install debug API headers
mkdir -p "$STAGING/usr/include/debug_api"
[ -d "$SOURCE/source/debug_api/include" ] && cp "$SOURCE/source/debug_api/include"/*.h "$STAGING/usr/include/debug_api/" 2>/dev/null || true

# Install util API headers
mkdir -p "$STAGING/usr/include/util_api"
for api in ansc http tls web stun asn.1; do
    if [ -d "$SOURCE/source/util_api/$api/include" ]; then
        mkdir -p "$STAGING/usr/include/util_api/$api"
        cp -r "$SOURCE/source/util_api/$api/include"/* "$STAGING/usr/include/util_api/$api/" 2>/dev/null || true
    fi
done

# Install dm_pack headers
[ -d "$SOURCE/source/dm_pack" ] && mkdir -p "$STAGING/usr/include/dm_pack" && \
    cp "$SOURCE/source/dm_pack"/*.h "$STAGING/usr/include/dm_pack/" 2>/dev/null || true

echo "Headers installed to $STAGING/usr/include"
