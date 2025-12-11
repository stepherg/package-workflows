#!/bin/bash
# build-common.sh - Shared build functions for packaging workflows
# This script provides reusable functions for building Debian packages from various upstream projects

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions - all output to stderr to avoid polluting function return values
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Detect the build system used by the upstream project
# Returns: cmake, make, autotools, meson, or unknown
detect_build_system() {
    if [ -f "CMakeLists.txt" ]; then
        echo "cmake"
    elif [ -f "meson.build" ]; then
        echo "meson"
    elif [ -f "configure" ] || [ -f "configure.ac" ] || [ -f "configure.in" ]; then
        echo "autotools"
    elif [ -f "Makefile" ] || [ -f "makefile" ] || [ -f "GNUmakefile" ]; then
        echo "make"
    else
        echo "unknown"
    fi
}

# Clone upstream repository and checkout specified ref
# Args: $1 = project name, $2 = upstream URL, $3 = upstream ref (tag/branch/commit)
clone_upstream() {
    local project=$1
    local upstream_url=$2
    local upstream_ref=$3
    
    log_info "Cloning upstream repository: $upstream_url"
    log_info "Target ref: $upstream_ref"
    
    # Clean up any existing source directory
    if [ -d "source-$project" ]; then
        log_warning "Removing existing source directory"
        rm -rf "source-$project"
    fi
    
    # Clone with shallow depth for efficiency
    if git clone --depth 1 --branch "$upstream_ref" "$upstream_url" "source-$project" 2>/dev/null; then
        log_success "Cloned repository at ref $upstream_ref"
    else
        # Fallback: clone full repo and checkout specific ref
        log_warning "Shallow clone failed, trying full clone..."
        git clone "$upstream_url" "source-$project"
        cd "source-$project"
        git checkout "$upstream_ref"
        cd ..
        log_success "Cloned repository and checked out $upstream_ref"
    fi
}

# Apply patches from packages/<project>/patches/ directory
# Args: $1 = project name
apply_patches() {
    local project=$1
    local patch_dir="/workspace/packages/$project/patches"
    
    if [ ! -d "$patch_dir" ]; then
        log_info "No patches directory found, skipping patch application"
        return 0
    fi
    
    local patches=($(ls "$patch_dir"/*.patch 2>/dev/null | sort))
    
    if [ ${#patches[@]} -eq 0 ]; then
        log_info "No patches found in $patch_dir"
        return 0
    fi
    
    log_info "Applying patches from $patch_dir"
    
    for patch in "${patches[@]}"; do
        log_info "Applying patch: $(basename "$patch")"
        if patch -p1 < "$patch"; then
            log_success "Applied $(basename "$patch")"
        else
            log_error "Failed to apply patch: $(basename "$patch")"
            return 1
        fi
    done
    
    log_success "All patches applied successfully"
}

# Build using CMake
# Args: $1 = project name, $2 = architecture
build_cmake() {
    local project=$1
    local arch=$2
    
    log_info "Building with CMake..."
    
    # Read custom cmake options if available
    local custom_options=""
    if [ -f "/workspace/packages/$project/cmake_options" ]; then
        custom_options=$(cat "/workspace/packages/$project/cmake_options")
        log_info "Using custom CMake options: $custom_options"
    fi
    
    mkdir -p build
    cd build
    
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr \
          -DCMAKE_C_FLAGS_RELEASE="-g -O2" \
          -DCMAKE_CXX_FLAGS_RELEASE="-g -O2" \
          $custom_options \
          ..
    
    make -j$(nproc)
    
    log_success "CMake build completed"
    
    # Save unstripped binaries for debug package creation BEFORE make install strips them
    mkdir -p /tmp/unstripped-$project
    find . -type f -executable -exec sh -c 'file "{}" | grep -q ELF && readelf -S "{}" 2>/dev/null | grep -q "\.debug_"' \; -exec cp -p {} /tmp/unstripped-$project/ \; 2>/dev/null || true
    # Also save libraries with debug symbols
    find . -name "*.a" -o -name "*.so*" | while read lib; do
        if file "$lib" 2>/dev/null | grep -qE "ELF" && readelf -S "$lib" 2>/dev/null | grep -q "\.debug_"; then
            cp -p "$lib" /tmp/unstripped-$project/
        fi
    done 2>/dev/null || true
    
    # Install to staging directory
    DESTDIR="/tmp/staging-$project" make install
    cd ..
}

# Build using plain Make
# Args: $1 = project name, $2 = architecture
build_make() {
    local project=$1
    local arch=$2
    
    log_info "Building with Make..."
    
    # Create a wrapper script to inject -g flag into compilation
    cat > /tmp/gcc-wrapper << 'EOF'
#!/bin/bash
# Add -g flag if not already present
args=("$@")
has_g=false
for arg in "${args[@]}"; do
    if [[ "$arg" == "-g" ]]; then
        has_g=true
        break
    fi
done
if [ "$has_g" = false ]; then
    args+=("-g")
fi
exec /usr/bin/gcc.real "${args[@]}"
EOF
    chmod +x /tmp/gcc-wrapper
    
    # Backup real gcc and use wrapper
    if [ ! -f /usr/bin/gcc.real ]; then
        mv /usr/bin/gcc /usr/bin/gcc.real
        cp /tmp/gcc-wrapper /usr/bin/gcc
    fi
    
    # Build
    make PREFIX=/usr -j$(nproc)
    
    # Save unstripped binaries for debug package creation BEFORE make install strips them
    mkdir -p /tmp/unstripped-$project
    find . -type f -executable -exec sh -c 'file "{}" | grep -q ELF && readelf -S "{}" 2>/dev/null | grep -q "\.debug_"' \; -exec cp -p {} /tmp/unstripped-$project/ \; 2>/dev/null || true
    # Also save libraries with debug symbols
    find . -name "*.a" -o -name "*.so*" | while read lib; do
        if file "$lib" 2>/dev/null | grep -qE "ELF" && readelf -S "$lib" 2>/dev/null | grep -q "\.debug_"; then
            cp -p "$lib" /tmp/unstripped-$project/
        fi
    done 2>/dev/null || true
    
    # Restore gcc
    if [ -f /usr/bin/gcc.real ]; then
        mv /usr/bin/gcc.real /usr/bin/gcc
    fi
    
    log_success "Make build completed"
    
    # Install to staging directory
    make install DESTDIR="/tmp/staging-$project" PREFIX=/usr || \
    make install DESTDIR="/tmp/staging-$project" prefix=/usr
}

# Build using Autotools (./configure)
# Args: $1 = project name, $2 = architecture
build_autotools() {
    local project=$1
    local arch=$2
    
    log_info "Building with Autotools..."
    
    # Run autogen if it exists
    if [ -f "autogen.sh" ]; then
        log_info "Running autogen.sh..."
        ./autogen.sh
    elif [ -f "configure.ac" ] && [ ! -f "configure" ]; then
        log_info "Running autoreconf to generate configure script..."
        autoreconf -i
    fi
    
    ./configure --prefix=/usr
    
    make -j$(nproc)
    
    log_success "Autotools build completed"
    
    # Install to staging directory
    make install DESTDIR="/tmp/staging-$project"
    
    # Check if there's a custom header installation script
    if [ -f "/workspace/packages/$project/install-headers.sh" ]; then
        log_info "Running custom header installation script..."
        bash "/workspace/packages/$project/install-headers.sh" "/tmp/staging-$project" "$(pwd)"
    fi
}

# Build using Meson
# Args: $1 = project name, $2 = architecture
build_meson() {
    local project=$1
    local arch=$2
    
    log_info "Building with Meson..."
    
    meson setup build --prefix=/usr --buildtype=release
    
    # Support both old and new meson syntax
    if meson compile --help 2>&1 | grep -q -- '-C'; then
        meson compile -C build
    else
        ninja -C build
    fi
    
    log_success "Meson build completed"
    
    # Install to staging directory
    if meson install --help 2>&1 | grep -q -- '-C'; then
        DESTDIR="/tmp/staging-$project" meson install -C build
    else
        DESTDIR="/tmp/staging-$project" ninja -C build install
    fi
}

# Detect runtime dependencies using dpkg-shlibdeps
# Args: $1 = project name, $2 = staging directory
detect_dependencies() {
    local project=$1
    local staging_dir=$2
    
    log_info "Detecting runtime dependencies..."
    
    # Find all binaries and shared libraries
    local bins=$(find "$staging_dir" -type f \( -executable -o -name "*.so*" \) 2>/dev/null || true)
    
    if [ -z "$bins" ]; then
        log_warning "No binaries or libraries found for dependency detection"
        return 0
    fi
    
    # Use dpkg-shlibdeps to detect dependencies
    local deps=""
    if command -v dpkg-shlibdeps &> /dev/null; then
        deps=$(dpkg-shlibdeps -O $bins 2>/dev/null | sed 's/shlibs:Depends=//' || true)
    fi
    
    if [ -n "$deps" ]; then
        log_info "Detected dependencies: $deps"
        echo "$deps"
    else
        log_info "No additional dependencies detected"
        echo ""
    fi
}

# Create Debian packages (supports multiple binary packages)
# Args: $1 = project name, $2 = version, $3 = architecture, $4 = staging directory
create_deb() {
    local project=$1
    local version=$2
    local arch=$3
    local staging_dir=$4
    
    local control_file="packages/$project/control"
    if [ ! -f "$control_file" ]; then
        log_error "Control file not found: $control_file"
        return 1
    fi
    
    # Count how many Package: sections exist
    local pkg_count=$(grep -c "^Package:" "$control_file")
    
    # Check if debug packages should be created (default: yes)
    local create_debug="yes"
    if [ -f "packages/$project/create_debug_packages" ]; then
        create_debug=$(cat "packages/$project/create_debug_packages" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    fi
    
    # Extract debug symbols and add debug links BEFORE creating packages
    if [ "$create_debug" = "yes" ] || [ "$create_debug" = "true" ] || [ "$create_debug" = "1" ]; then
        prepare_debug_symbols "$project" "$version" "$arch" "$staging_dir"
    else
        log_info "Debug packages disabled for $project"
    fi
    
    if [ "$pkg_count" -eq 1 ]; then
        # Single package - use simple approach
        create_single_deb "$project" "$version" "$arch" "$staging_dir"
    else
        # Multiple packages - need to split files
        create_multi_deb "$project" "$version" "$arch" "$staging_dir"
    fi
    
    # Create debug package if debug symbols exist and enabled
    if [ "$create_debug" = "yes" ] || [ "$create_debug" = "true" ] || [ "$create_debug" = "1" ]; then
        create_debug_package "$project" "$version" "$arch" "$staging_dir"
        create_source_package "$project" "$version"
    else
        log_info "Skipping debug and source packages (disabled)"
    fi
}

# Create a single Debian package
# Args: $1 = project name, $2 = version, $3 = architecture, $4 = staging directory
create_single_deb() {
    local project=$1
    local version=$2
    local arch=$3
    local staging_dir=$4
    
    log_info "Creating Debian package for $project version $version ($arch)..."
    
    # Create package directory structure
    local pkg_dir="/tmp/package-$project"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/DEBIAN"
    
    # Copy all files from staging
    if [ -d "$staging_dir/usr" ]; then
        mkdir -p "$pkg_dir/usr"
        cp -r "$staging_dir/usr/"* "$pkg_dir/usr/" 2>/dev/null || true
    fi
    
    # Calculate installed size (in KB) - include all directories except DEBIAN
    local installed_size=$(du -sk "$pkg_dir" 2>/dev/null | cut -f1 || echo "0")
    # Subtract DEBIAN directory if it exists
    if [ -d "$pkg_dir/DEBIAN" ]; then
        local debian_size=$(du -sk "$pkg_dir/DEBIAN" 2>/dev/null | cut -f1 || echo "0")
        installed_size=$((installed_size - debian_size))
    fi
    
    # Read control file metadata
    local control_file="packages/$project/control"
    local description=$(grep -A 20 "^Description:" "$control_file" || echo "Description: $project package")
    local depends=$(grep "^Depends:" "$control_file" | sed 's/^Depends: *//' | head -1 || echo "")
    
    # Detect additional dependencies
    local auto_depends=$(detect_dependencies "$project" "$staging_dir")
    
    # Substitute ${shlibs:Depends} with auto-detected dependencies
    if [[ "$depends" == *'${shlibs:Depends}'* ]]; then
        depends="${depends//\$\{shlibs:Depends\}/$auto_depends}"
    elif [ -n "$auto_depends" ] && [ -n "$depends" ]; then
        depends="$depends, $auto_depends"
    elif [ -n "$auto_depends" ]; then
        depends="$auto_depends"
    fi
    
    # Remove ${misc:Depends} template variable (not used in simple packaging)
    depends="${depends//\$\{misc:Depends\}/}"
    # Clean up any resulting issues: double commas, leading/trailing commas, extra spaces
    depends=$(echo "$depends" | sed 's/,,\+/,/g; s/^[, ]\+//; s/[, ]\+$//; s/  \+/ /g')
    
    # Generate control file
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $project
Version: $version
Section: misc
Priority: optional
Architecture: $arch
Installed-Size: $installed_size
Maintainer: Package Workflows <packages@example.com>
EOF
    
    if [ -n "$depends" ]; then
        echo "Depends: $depends" >> "$pkg_dir/DEBIAN/control"
    fi
    
    echo "$description" >> "$pkg_dir/DEBIAN/control"
    
    log_info "Package control file created"
    cat "$pkg_dir/DEBIAN/control"
    
    # Copy maintainer scripts if they exist
    for script in postinst prerm postrm preinst; do
        if [ -f "packages/$project/$script" ]; then
            log_info "Adding $script script"
            cp "packages/$project/$script" "$pkg_dir/DEBIAN/$script"
            chmod 755 "$pkg_dir/DEBIAN/$script"
        fi
    done
    
    # Install systemd service files if they exist
    if [ -f "packages/$project/${project}.service" ]; then
        log_info "Installing systemd service file"
        mkdir -p "$pkg_dir/lib/systemd/system"
        cp "packages/$project/${project}.service" "$pkg_dir/lib/systemd/system/"
    fi
    
    # Build the package
    local output_deb="${project}_${version}_${arch}.deb"
    dpkg-deb --build "$pkg_dir" "$output_deb"
    
    if [ -f "$output_deb" ]; then
        log_success "Package created: $output_deb"
        ls -lh "$output_deb"
        return 0
    else
        log_error "Failed to create package"
        return 1
    fi
}

# Create multiple Debian packages from control file
# Args: $1 = project name, $2 = version, $3 = architecture, $4 = staging directory
create_multi_deb() {
    local project=$1
    local version=$2
    local arch=$3
    local staging_dir=$4
    
    local control_file="packages/$project/control"
    
    log_info "Creating multiple Debian packages for $project version $version ($arch)..."
    
    # Get all package names
    local pkg_names=($(grep "^Package:" "$control_file" | sed 's/^Package: *//'))
    
    log_info "Found ${#pkg_names[@]} packages: ${pkg_names[*]}"
    
    # Process each package
    for pkg_name in "${pkg_names[@]}"; do
        create_package_from_section "$project" "$pkg_name" "$version" "$arch" "$staging_dir" "$control_file"
    done
}

# Create a single package from a specific Package: section in control file
# Args: $1 = source project, $2 = package name, $3 = version, $4 = arch, $5 = staging dir, $6 = control file
create_package_from_section() {
    local project=$1
    local pkg_name=$2
    local version=$3
    local arch=$4
    local staging_dir=$5
    local control_file=$6
    
    log_info "Creating package: $pkg_name"
    
    # Create package directory
    local pkg_dir="/tmp/package-$pkg_name"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/DEBIAN"
    mkdir -p "$pkg_dir/usr"
    
    # Determine which files belong to this package based on common patterns
    if [[ "$pkg_name" == *"-dev" ]]; then
        # Development package: headers, static libraries, pkg-config files
        [ -d "$staging_dir/usr/include" ] && cp -r "$staging_dir/usr/include" "$pkg_dir/usr/" 2>/dev/null || true
        if [ -d "$staging_dir/usr/lib" ]; then
            mkdir -p "$pkg_dir/usr/lib"
            # Copy static libraries only
            find "$staging_dir/usr/lib" -name "*.a" | while read f; do
                cp -a "$f" "$pkg_dir/usr/lib/" 2>/dev/null || true
            done
            # Copy pkgconfig directory
            [ -d "$staging_dir/usr/lib/pkgconfig" ] && cp -r "$staging_dir/usr/lib/pkgconfig" "$pkg_dir/usr/lib/" 2>/dev/null || true
        fi
    elif [[ "$pkg_name" == *"-dbg" ]] || [[ "$pkg_name" == *"-debug" ]]; then
        # Debug package: debug symbols
        [ -d "$staging_dir/usr/lib/debug" ] && cp -r "$staging_dir/usr/lib/debug" "$pkg_dir/usr/lib/" 2>/dev/null || true
    elif [[ "$pkg_name" == *"-doc" ]]; then
        # Documentation package
        [ -d "$staging_dir/usr/share/doc" ] && cp -r "$staging_dir/usr/share/doc" "$pkg_dir/usr/share/" 2>/dev/null || true
        [ -d "$staging_dir/usr/share/man" ] && cp -r "$staging_dir/usr/share/man" "$pkg_dir/usr/share/" 2>/dev/null || true
    else
        # Runtime package: binaries, shared libraries, data files
        [ -d "$staging_dir/usr/bin" ] && cp -r "$staging_dir/usr/bin" "$pkg_dir/usr/" 2>/dev/null || true
        [ -d "$staging_dir/usr/sbin" ] && cp -r "$staging_dir/usr/sbin" "$pkg_dir/usr/" 2>/dev/null || true
        [ -d "$staging_dir/usr/share" ] && cp -r "$staging_dir/usr/share" "$pkg_dir/usr/" 2>/dev/null || true
        # Copy all shared libraries (all .so files and symlinks)
        if [ -d "$staging_dir/usr/lib" ]; then
            mkdir -p "$pkg_dir/usr/lib"
            find "$staging_dir/usr/lib" -name "*.so*" \( -type f -o -type l \) | while read f; do
                local rel_path="${f#$staging_dir/usr/lib/}"
                local dir=$(dirname "$rel_path")
                mkdir -p "$pkg_dir/usr/lib/$dir"
                cp -a "$f" "$pkg_dir/usr/lib/$dir/" 2>/dev/null || true
            done
        fi
    fi
    
    # Skip if no files were included
    if [ ! -d "$pkg_dir/usr" ] || [ -z "$(find "$pkg_dir/usr" -type f 2>/dev/null)" ]; then
        log_warning "No files for package $pkg_name, skipping"
        rm -rf "$pkg_dir"
        return 0
    fi
    
    # Calculate installed size (in KB) - include all directories except DEBIAN
    local installed_size=$(du -sk "$pkg_dir" 2>/dev/null | cut -f1 || echo "0")
    # Subtract DEBIAN directory if it exists
    if [ -d "$pkg_dir/DEBIAN" ]; then
        local debian_size=$(du -sk "$pkg_dir/DEBIAN" 2>/dev/null | cut -f1 || echo "0")
        installed_size=$((installed_size - debian_size))
    fi
    
    # Extract metadata for this package from control file
    local start_line=$(grep -n "^Package: *$pkg_name\$" "$control_file" | cut -d: -f1)
    local next_line=$(grep -n "^Package:" "$control_file" | awk -v start="$start_line" '$1 > start {print $1; exit}' | cut -d: -f1)
    
    if [ -z "$next_line" ]; then
        # Last package in file
        local pkg_section=$(sed -n "${start_line},\$p" "$control_file")
    else
        # Extract up to next Package: line
        local pkg_section=$(sed -n "${start_line},$((next_line-1))p" "$control_file")
    fi
    
    local description=$(echo "$pkg_section" | grep -A 20 "^Description:" || echo "Description: $pkg_name")
    local depends=$(echo "$pkg_section" | grep "^Depends:" | sed 's/^Depends: *//' || echo "")
    local section=$(echo "$pkg_section" | grep "^Section:" | sed 's/^Section: *//' || echo "misc")
    local priority=$(echo "$pkg_section" | grep "^Priority:" | sed 's/^Priority: *//' || echo "optional")
    
    # Detect additional dependencies for this package
    local auto_depends=$(detect_dependencies "$project" "$pkg_dir")
    
    # Substitute ${shlibs:Depends} with auto-detected dependencies
    if [[ "$depends" == *'${shlibs:Depends}'* ]]; then
        depends="${depends//\$\{shlibs:Depends\}/$auto_depends}"
    elif [ -n "$auto_depends" ] && [ -n "$depends" ]; then
        depends="$depends, $auto_depends"
    elif [ -n "$auto_depends" ]; then
        depends="$auto_depends"
    fi
    
    # Remove ${misc:Depends} template variable (not used in simple packaging)
    depends="${depends//\$\{misc:Depends\}/}"
    
    # Replace version placeholder in depends
    depends="${depends//\$\{version\}/$version}"
    depends="${depends//(= \$\{version\})/(= $version)}"
    
    # Clean up any resulting issues: double commas, leading/trailing commas, extra spaces
    depends=$(echo "$depends" | sed 's/,,\+/,/g; s/^[, ]\+//; s/[, ]\+$//; s/  \+/ /g')
    
    # Generate control file
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $pkg_name
Version: $version
Section: $section
Priority: $priority
Architecture: $arch
Installed-Size: $installed_size
Maintainer: Package Workflows <packages@example.com>
EOF
    
    if [ -n "$depends" ]; then
        echo "Depends: $depends" >> "$pkg_dir/DEBIAN/control"
    fi
    
    echo "$description" >> "$pkg_dir/DEBIAN/control"
    
    # Copy maintainer scripts if they exist
    for script in postinst prerm postrm preinst; do
        if [ -f "packages/$project/$script" ]; then
            log_info "Adding $script script to $pkg_name"
            cp "packages/$project/$script" "$pkg_dir/DEBIAN/$script"
            chmod 755 "$pkg_dir/DEBIAN/$script"
        fi
    done
    
    # Install systemd service files if they exist
    # Only install for packages that are not -dev, -dbg, or -dbgsrc packages
    if [[ ! "$pkg_name" =~ -(dev|dbg|dbgsrc)$ ]]; then
        if [ -f "packages/$project/${pkg_name}.service" ]; then
            log_info "Installing systemd service file for $pkg_name"
            mkdir -p "$pkg_dir/lib/systemd/system"
            cp "packages/$project/${pkg_name}.service" "$pkg_dir/lib/systemd/system/"
        elif [ -f "packages/$project/${project}.service" ]; then
            log_info "Installing systemd service file for $pkg_name"
            mkdir -p "$pkg_dir/lib/systemd/system"
            cp "packages/$project/${project}.service" "$pkg_dir/lib/systemd/system/"
        fi
    fi
    
    # Build the package
    local output_deb="${pkg_name}_${version}_${arch}.deb"
    dpkg-deb --build "$pkg_dir" "$output_deb"
    
    if [ -f "$output_deb" ]; then
        log_success "Package created: $output_deb"
        ls -lh "$output_deb"
    else
        log_error "Failed to create package: $pkg_name"
        return 1
    fi
}

# Prepare debug symbols by extracting from unstripped binaries and adding debug links
# This must be called BEFORE creating packages so the runtime packages include debug links
# Args: $1 = project name, $2 = version, $3 = architecture, $4 = staging directory
prepare_debug_symbols() {
    local project=$1
    local version=$2
    local arch=$3
    local staging_dir=$4
    local unstripped_dir="/tmp/unstripped-$project"
    local debug_dir="/tmp/debug-$project"
    
    # Check if we have saved unstripped binaries
    if [ ! -d "$unstripped_dir" ]; then
        log_info "No unstripped binaries found, skipping debug symbol preparation"
        return 0
    fi
    
    rm -rf "$debug_dir"
    mkdir -p "$debug_dir/usr/lib/debug"
    
    log_info "Preparing debug symbols for $project"
    
    local has_debug=false
    
    # Process each unstripped binary
    for unstripped_file in "$unstripped_dir"/*; do
        [ -f "$unstripped_file" ] || continue
        
        local basename=$(basename "$unstripped_file")
        
        # Determine where this binary is installed and where debug symbols go
        local debug_file=""
        local stripped_binary=""
        
        if [ -f "$staging_dir/usr/bin/$basename" ]; then
            debug_file="$debug_dir/usr/lib/debug/usr/bin/$basename.debug"
            stripped_binary="$staging_dir/usr/bin/$basename"
        elif [ -f "$staging_dir/usr/lib/$basename" ] || [ -f "$staging_dir/usr/lib/quickjs/$basename" ]; then
            # Handle libraries in either /usr/lib or /usr/lib/quickjs
            if [ -f "$staging_dir/usr/lib/quickjs/$basename" ]; then
                debug_file="$debug_dir/usr/lib/debug/usr/lib/quickjs/$basename.debug"
                stripped_binary="$staging_dir/usr/lib/quickjs/$basename"
            else
                debug_file="$debug_dir/usr/lib/debug/usr/lib/$basename.debug"
                stripped_binary="$staging_dir/usr/lib/$basename"
            fi
        else
            continue
        fi
        
        mkdir -p "$(dirname "$debug_file")"
        
        log_info "Extracting debug symbols from $basename"
        # Extract debug symbols from unstripped version
        if objcopy --only-keep-debug "$unstripped_file" "$debug_file" 2>/dev/null; then
            has_debug=true
            log_info "Debug symbols extracted for $basename"
            
            # Add debug link to the stripped binary in staging (BEFORE it's packaged)
            if [ -n "$stripped_binary" ] && [ -f "$stripped_binary" ]; then
                log_info "Adding debug link to $basename in staging"
                local debug_basename="$basename.debug"
                local stripped_dir=$(dirname "$stripped_binary")
                
                # Temporarily copy debug file to same directory as binary
                cp "$debug_file" "$stripped_dir/$debug_basename" 2>/dev/null
                
                # Add debug link (must be in same directory)
                if (cd "$stripped_dir" && objcopy --add-gnu-debuglink="$debug_basename" "$basename" 2>&1); then
                    log_info "Debug link added successfully to $basename"
                else
                    log_error "Failed to add debug link to $basename"
                fi
                
                # Remove temporary debug file
                rm -f "$stripped_dir/$debug_basename"
            fi
        fi
    done
    
    if [ "$has_debug" = false ]; then
        log_info "No debug symbols found"
        rm -rf "$debug_dir"
    fi
    
    return 0
}

# Extract debug symbols from binaries and create debug package
# Args: $1 = project name, $2 = version, $3 = architecture, $4 = staging directory
create_debug_package() {
    local project=$1
    local version=$2
    local arch=$3
    local staging_dir=$4
    
    log_info "Creating debug package for $project..."
    
    # Check if debug symbols were prepared
    local debug_dir="/tmp/debug-$project"
    if [ ! -d "$debug_dir" ] || [ -z "$(find "$debug_dir" -type f 2>/dev/null)" ]; then
        log_info "No debug symbols found, skipping debug package"
        return 0
    fi
    
    # Create debug package directory
    local debug_pkg="${project}-dbg"
    local pkg_dir="/tmp/package-$debug_pkg"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/DEBIAN"
    
    # Copy debug symbols
    cp -r "$debug_dir/usr" "$pkg_dir/" 2>/dev/null
    
    # Calculate installed size
    local installed_size=$(du -sk "$pkg_dir/usr" 2>/dev/null | cut -f1 || echo "0")
    
    # Generate control file for debug package
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $debug_pkg
Version: $version
Section: debug
Priority: optional
Architecture: $arch
Installed-Size: $installed_size
Maintainer: Package Workflows <packages@example.com>
Depends: $project (= $version)
Description: Debug symbols for $project
 This package contains the debugging symbols for $project.
EOF
    
    # Build the debug package
    local output_deb="${debug_pkg}_${version}_${arch}.deb"
    dpkg-deb --build "$pkg_dir" "$output_deb"
    
    if [ -f "$output_deb" ]; then
        log_success "Debug package created: $output_deb"
        ls -lh "$output_deb"
    else
        log_warning "Failed to create debug package"
    fi
}

# Create source package as installable .deb (platform independent)
# Args: $1 = project name, $2 = version
create_source_package() {
    local project=$1
    local version=$2
    
    log_info "Creating source package for $project..."
    
    local source_dir="source-$project"
    if [ ! -d "$source_dir" ]; then
        log_warning "Source directory not found, skipping source package"
        return 0
    fi
    
    # Create debug source package directory
    local source_pkg="${project}-dbgsrc"
    local pkg_dir="/tmp/package-$source_pkg"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/DEBIAN"
    mkdir -p "$pkg_dir/usr/src/$project-$version"
    
    # Copy source files (excluding VCS and build artifacts)
    cp -r "$source_dir/." "$pkg_dir/usr/src/$project-$version/"
    
    # Remove VCS metadata and build artifacts
    cd "$pkg_dir/usr/src/$project-$version"
    rm -rf .git .github .gitignore .gitattributes
    find . -type f \( -name '*.o' -o -name '*.so' -o -name '*.so.*' -o -name '*.a' \) -delete 2>/dev/null || true
    make clean 2>/dev/null || true
    make distclean 2>/dev/null || true
    cd /workspace
    
    # Calculate installed size
    local installed_size=$(du -sk "$pkg_dir/usr" 2>/dev/null | cut -f1 || echo "0")
    
    # Generate control file for source package
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $source_pkg
Version: $version
Section: devel
Priority: optional
Architecture: all
Installed-Size: $installed_size
Maintainer: Package Workflows <packages@example.com>
Description: Source code for $project
 This package contains the source code for $project.
 .
 The source files are installed in /usr/src/$project-$version/
EOF
    
    # Build the source package
    local output_deb="${source_pkg}_${version}.deb"
    dpkg-deb --build "$pkg_dir" "$output_deb"
    
    if [ -f "$output_deb" ]; then
        log_success "Source package created: $output_deb"
        ls -lh "$output_deb"
    else
        log_error "Failed to create source package"
    fi
    
    # Clean up temporary directory
    rm -rf "$pkg_dir"
}

# Main build orchestration function
# Args: $1 = project name, $2 = architecture, $3 = upstream ref (optional, from workflow input)
build_package() {
    local project=$1
    local arch=$2
    local upstream_ref_override=${3:-""}
    
    log_info "========================================="
    log_info "Building package: $project"
    log_info "Architecture: $arch"
    log_info "========================================="
    
    # Read project configuration
    local control_file="packages/$project/control"
    if [ ! -f "$control_file" ]; then
        log_error "Control file not found: $control_file"
        return 1
    fi
    
    local upstream_url=$(grep "^Upstream-URL:" "$control_file" | sed 's/^Upstream-URL: *//')
    local upstream_ref=$(grep "^Upstream-Ref:" "$control_file" | sed 's/^Upstream-Ref: *//')
    local version=$(grep "^Version:" "$control_file" | sed 's/^Version: *//')
    
    # Override upstream ref if provided
    if [ -n "$upstream_ref_override" ]; then
        log_info "Using upstream ref override: $upstream_ref_override"
        upstream_ref="$upstream_ref_override"
    fi
    
    # Validate required fields
    if [ -z "$upstream_url" ] || [ -z "$upstream_ref" ] || [ -z "$version" ]; then
        log_error "Missing required fields in control file (Upstream-URL, Upstream-Ref, or Version)"
        return 1
    fi
    
    # Clone upstream repository
    clone_upstream "$project" "$upstream_url" "$upstream_ref"
    
    cd "source-$project"
    
    # Apply patches
    cd /workspace
    cd "source-$project"
    apply_patches "$project"
    
    # Detect build system
    local buildsys=$(detect_build_system)
    log_info "Detected build system: $buildsys"
    
    # Build with appropriate adapter
    case "$buildsys" in
        cmake)
            build_cmake "$project" "$arch"
            ;;
        make)
            build_make "$project" "$arch"
            ;;
        autotools)
            build_autotools "$project" "$arch"
            ;;
        meson)
            build_meson "$project" "$arch"
            ;;
        *)
            log_error "Unknown or unsupported build system"
            return 1
            ;;
    esac
    
    cd /workspace
    
    # Create Debian package
    create_deb "$project" "$version" "$arch" "/tmp/staging-$project"
    
    # Move all generated .deb files to workspace root for artifact upload
    log_info "Moving packages to workspace..."
    mv -f *.deb /workspace/ 2>/dev/null || true
    cd /workspace
    ls -lh *.deb 2>/dev/null || log_warning "No .deb files found"
    
    log_success "========================================="
    log_success "Package build completed successfully!"
    log_success "========================================="
}

# Export functions for use in workflows
export -f log_info log_success log_warning log_error
export -f detect_build_system clone_upstream apply_patches
export -f build_cmake build_make build_autotools build_meson
export -f detect_dependencies create_deb build_package
