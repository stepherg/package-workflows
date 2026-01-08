#!/bin/bash
# Create APT repository structure and index files for .deb packages
# Usage: ./create-apt-repository.sh [architecture] [output-dir]
#
# This script creates a proper APT repository structure that can be hosted
# on a web server. Clients can then add it to their sources.list.

set -euo pipefail

# Configuration
ARCH="${1:-arm64}"
OUTPUT_DIR="${2:-./apt-repo}"
DIST="stable"
COMPONENT="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if dpkg-scanpackages is available
if ! command -v dpkg-scanpackages &> /dev/null; then
    log_error "dpkg-scanpackages not found. Please install dpkg-dev:"
    log_error "  Ubuntu/Debian: apt-get install dpkg-dev"
    log_error "  macOS: Install via Docker (this script will use Docker)"
    
    # Check if we can use Docker as fallback
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found either. Cannot proceed."
        exit 1
    fi
    
    USE_DOCKER=1
    log_warning "Using Docker to run dpkg-scanpackages"
else
    USE_DOCKER=0
fi

# Create directory structure
# Structure: dists/stable/main/binary-{arch}/
REPO_ROOT="$OUTPUT_DIR"
POOL_DIR="$REPO_ROOT/pool/$COMPONENT"
DISTS_DIR="$REPO_ROOT/dists/$DIST/$COMPONENT/binary-$ARCH"

log_info "Creating APT repository structure..."
mkdir -p "$POOL_DIR"
mkdir -p "$DISTS_DIR"

# Find all .deb packages in current directory
DEB_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l | tr -d ' ')

if [ "$DEB_COUNT" -eq 0 ]; then
    log_error "No .deb packages found in current directory"
    exit 1
fi

log_info "Found $DEB_COUNT .deb packages"

# Copy packages to pool directory
log_info "Copying packages to pool directory..."
for deb in *.deb; do
    if [ -f "$deb" ]; then
        # Extract package name and version for organized storage
        if command -v dpkg-deb &> /dev/null; then
            PKG_NAME=$(dpkg-deb -f "$deb" Package 2>/dev/null || basename "$deb" .deb | cut -d_ -f1)
        else
            PKG_NAME=$(basename "$deb" .deb | cut -d_ -f1)
        fi
        
        # Create subdirectory by first letter of package name
        FIRST_LETTER=$(echo "$PKG_NAME" | cut -c1 | tr '[:upper:]' '[:lower:]')
        mkdir -p "$POOL_DIR/$FIRST_LETTER/$PKG_NAME"
        
        # Copy package
        cp -v "$deb" "$POOL_DIR/$FIRST_LETTER/$PKG_NAME/"
    fi
done

# Generate Packages index file
log_info "Generating Packages index..."

if [ "$USE_DOCKER" -eq 1 ]; then
    # Use Docker to run dpkg-scanpackages
    docker run --rm \
        -v "$(cd "$REPO_ROOT" && pwd):/repo" \
        -w /repo \
        ubuntu:20.04 \
        bash -c "
            apt-get update -qq && apt-get install -y -qq dpkg-dev > /dev/null 2>&1
            dpkg-scanpackages --arch $ARCH pool/ > dists/$DIST/$COMPONENT/binary-$ARCH/Packages
        "
else
    # Run dpkg-scanpackages directly
    cd "$REPO_ROOT"
    dpkg-scanpackages --arch "$ARCH" pool/ > "dists/$DIST/$COMPONENT/binary-$ARCH/Packages"
    cd - > /dev/null
fi

# Compress Packages file
log_info "Compressing Packages index..."
gzip -9c "$DISTS_DIR/Packages" > "$DISTS_DIR/Packages.gz"

# Generate Release file for the distribution
log_info "Generating Release file..."

# Check if Release file exists and extract existing architectures
EXISTING_ARCHS=""
if [ -f "$REPO_ROOT/dists/$DIST/Release" ]; then
    EXISTING_ARCHS=$(grep "^Architectures:" "$REPO_ROOT/dists/$DIST/Release" 2>/dev/null | sed 's/^Architectures: *//' || echo "")
fi

# Add current architecture if not already present
if [ -z "$EXISTING_ARCHS" ]; then
    ALL_ARCHS="$ARCH"
elif ! echo "$EXISTING_ARCHS" | grep -qw "$ARCH"; then
    ALL_ARCHS="$EXISTING_ARCHS $ARCH"
else
    ALL_ARCHS="$EXISTING_ARCHS"
fi

cat > "$REPO_ROOT/dists/$DIST/Release" << EOF
Origin: RDK/XMiDT Packages
Label: RDK/XMiDT Packages
Suite: $DIST
Codename: $DIST
Architectures: $ALL_ARCHS
Components: $COMPONENT
Description: RDK and XMiDT component packages
Date: $(date -u "+%a, %d %b %Y %H:%M:%S %z")
EOF

# Calculate checksums for Release file with correct file sizes
cd "$REPO_ROOT/dists/$DIST"

# MD5Sum
echo "MD5Sum:" >> Release
find . -type f -name 'Packages*' | while read f; do
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
    md5=$(md5sum "$f" 2>/dev/null | awk '{print $1}' || md5 -q "$f" 2>/dev/null || echo "0")
    printf " %s %16d %s\n" "$md5" "$size" "${f#./}"
done >> Release

# SHA1
echo "SHA1:" >> Release
find . -type f -name 'Packages*' | while read f; do
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
    sha1=$(sha1sum "$f" 2>/dev/null | awk '{print $1}' || shasum -a 1 "$f" 2>/dev/null | awk '{print $1}' || echo "0")
    printf " %s %16d %s\n" "$sha1" "$size" "${f#./}"
done >> Release

# SHA256
echo "SHA256:" >> Release
find . -type f -name 'Packages*' | while read f; do
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
    sha256=$(sha256sum "$f" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || echo "0")
    printf " %s %16d %s\n" "$sha256" "$size" "${f#./}"
done >> Release

cd - > /dev/null

# Create usage instructions
cat > "$REPO_ROOT/README.md" << 'EOF'
# APT Repository

This directory contains a Debian/Ubuntu APT repository structure.

## Hosting the Repository

### Option 1: Simple HTTP Server (for testing)

```bash
# Python 3
cd apt-repo
python3 -m http.server 8080

# Then access at: http://localhost:8080
```

### Option 2: Nginx

```nginx
server {
    listen 80;
    server_name packages.example.com;
    root /path/to/apt-repo;
    
    location / {
        autoindex on;
    }
}
```

### Option 3: Apache

```apache
<VirtualHost *:80>
    ServerName packages.example.com
    DocumentRoot /path/to/apt-repo
    
    <Directory /path/to/apt-repo>
        Options +Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
```

## Using the Repository

Add the repository to your system:

```bash
# Add repository (replace URL with your server)
echo "deb [arch=arm64] https://stepherg.github.io/package-workflows stable main" | \
    sudo tee /etc/apt/sources.list.d/custom-packages.list

# Download and import the public key
wget -qO - https://stepherg.github.io/package-workflows/KEY.gpg | \
   gpg --dearmor -o /etc/apt/trusted.gpg.d/custom-packages.gpg

# If you have a GPG key (optional but recommended):
# wget -qO - http://your-server-url/apt-repo/KEY.gpg | sudo apt-key add -

# Update package list
sudo apt-get update

# Install packages
sudo apt-get install package-name
```

## Repository Structure

```
apt-repo/
├── dists/
│   └── stable/
│       ├── Release
│       └── main/
│           └── binary-arm64/
│               ├── Packages
│               └── Packages.gz
└── pool/
    └── main/
        └── [a-z]/
            └── package-name/
                └── package_version_arch.deb
```

## Updating the Repository

After adding new .deb files, regenerate the index:

```bash
./scripts/create-apt-repository.sh arm64 apt-repo
```

## Signing the Repository (Recommended for Production)

To sign the repository with GPG:

```bash
# Generate a GPG key if you don't have one
gpg --gen-key

# Export the public key
gpg --armor --export YOUR_EMAIL > apt-repo/KEY.gpg

# Sign the Release file
cd apt-repo/dists/stable
gpg --clearsign -o InRelease Release
gpg -abs -o Release.gpg Release
```

Clients will then need to add your public key before trusting the repository.
EOF

log_info "Repository structure created successfully!"
log_info ""
log_info "Repository location: $REPO_ROOT"
log_info "Total packages: $DEB_COUNT"
log_info ""
log_info "To host the repository:"
log_info "  1. Copy the '$OUTPUT_DIR' directory to your web server"
log_info "  2. See $REPO_ROOT/README.md for hosting and usage instructions"
log_info ""
log_info "Repository URL format: http://your-server/$(basename "$OUTPUT_DIR")"
log_info "APT sources.list entry:"
log_info "  deb [arch=$ARCH] http://your-server/$(basename "$OUTPUT_DIR") $DIST $COMPONENT"
