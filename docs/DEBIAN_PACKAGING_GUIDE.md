# Debian Package Build System

A comprehensive automated build system for creating Debian packages from upstream repositories with support for multi-architecture builds, debug symbols, systemd service integration, and complete GDB debugging support.

## Overview

This system automates the complete lifecycle of building Debian packages from upstream source code repositories. It supports both Make and CMake build systems, handles complex multi-package scenarios, integrates systemd services, and creates comprehensive debug packages for production debugging.

### Package Types

The system generates up to **4 package types** per project:

1. **Runtime Package** (`<project>_<version>_<arch>.deb`)
   - Binaries: `/usr/bin/`, `/usr/sbin/`
   - Shared libraries: All `.so*` files (including symlinks)
   - Data files: `/usr/share/`
   - Configuration files and resources
   - Systemd service files (when applicable)
   - Optimized for production deployment (stripped binaries)

2. **Development Package** (`<project>-dev_<version>_<arch>.deb`)
   - Header files: `/usr/include/`
   - Static libraries: `.a` files
   - pkg-config files: `/usr/lib/pkgconfig/`
   - Required for building software against the library

3. **Debug Symbols Package** (`<project>-dbg_<version>_<arch>.deb`)
   - Separated debug symbols with GNU debuglink
   - Installed to `/usr/lib/debug/`
   - Used by GDB for debugging without impacting runtime size

4. **Debug Source Package** (`<project>-dbgsrc_<version>_all.deb`)
   - Complete source code
   - Installed to `/usr/src/<project>-<version>/`
   - Enables source-level debugging with GDB

## Architecture

### Directory Structure

```
project-root/
├── packages/
│   └── <project>/
│       ├── control              # Package metadata (required)
│       ├── build_system         # "make" or "cmake" (optional, auto-detected)
│       ├── cmake_options        # CMake-specific flags (optional)
│       ├── make_options         # Make-specific flags (optional)
│       ├── additional_repos     # Additional git repos to clone (optional)
│       ├── patches/             # Source patches (optional)
│       │   └── 001-fix.patch
│       ├── postinst             # Post-installation script (optional)
│       ├── prerm                # Pre-removal script (optional)
│       ├── postrm               # Post-removal script (optional)
│       ├── preinst              # Pre-installation script (optional)
│       └── <project>.service    # Systemd service file (optional)
├── scripts/
│   └── build-helpers/
│       └── build-common.sh      # Core build logic
└── .github/
    └── workflows/
        └── package-<project>.yml # GitHub Actions workflow
```

### Control File Format

The `control` file uses a YAML-like format that defines package metadata:

```yaml
Source: project-name
Version: 1.0.0
Upstream-URL: https://github.com/org/repo.git
Upstream-Ref: v1.0.0
Build-Depends: pkg-config, libssl-dev, cmake

Package: project-name
Section: libs
Priority: optional
Depends: libc6, libssl3
Description: Short description
 Long description paragraph 1.
 Can span multiple lines.
 .
 Paragraph 2 starts after a dot line.

Package: libproject-dev
Section: libdevel
Priority: optional
Depends: project-name (= ${version})
Description: Development files
 Headers and libraries for development.
```

**Key Features:**
- **Multi-package support**: Define multiple binary packages from one source
- **Version placeholders**: Use `${version}` in Depends fields
- **Automatic dependency detection**: Runtime dependencies are auto-detected for libraries
- **Flexible sections**: Standard Debian sections (libs, libdevel, utils, net, etc.)

### Build Flow

```
1. Clone/Checkout
   ↓
2. Apply Patches (if any)
   ↓
3. Detect Build System
   ↓
4. Configure & Build
   ├─ Make: gcc wrapper injects -g flag
   └─ CMake: CMAKE_C_FLAGS_RELEASE="-g -O2"
   ↓
5. Save Unstripped Binaries
   ↓
6. Install to Staging Directory
   ↓
7. Prepare Debug Symbols
   ├─ Extract symbols: objcopy --only-keep-debug
   ├─ Strip binaries: strip --strip-debug
   └─ Add debuglink: objcopy --add-gnu-debuglink
   ↓
8. Create Packages
   ├─ Runtime package(s)
   ├─ Dev package(s)
   ├─ Debug package
   └─ Source package
```

### Multi-Architecture Support

The system builds packages for multiple architectures using Docker with QEMU:

- **amd64** (x86_64) - Intel/AMD 64-bit
- **arm64** (aarch64) - ARM 64-bit

**GitHub Actions Matrix Strategy:**
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - platform: amd64
        docker_platform: linux/amd64
      - platform: arm64
        docker_platform: linux/arm64
```

Each architecture build runs in parallel and creates architecture-specific packages.

## Core Components

### 1. Build System (`build-common.sh`)

The `build-common.sh` script provides the core build orchestration:

#### Key Functions

**`build_package()`**
- Main entry point for building a package
- Clones source, applies patches, detects build system
- Orchestrates the entire build process
- Creates all package types
- **Usage:** `build_package "<project>" "${{ matrix.platform }}" "${{ inputs.upstream_ref }}"`
  - First argument: package name (must match directory name in `packages/`)
  - Second argument: platform/architecture (arm64, amd64)
  - Third argument: optional upstream ref override (defaults to value in control file)

**`build_cmake()`**
- Handles CMake-based projects
- Injects debug flags: `-DCMAKE_C_FLAGS_RELEASE="-g -O2"`
- Saves unstripped binaries before installation
- Installs to staging directory

**`build_make()`**
- Handles Make-based projects
- Uses gcc/g++ wrapper to inject `-g` flag
- Automatically detects and saves unstripped binaries
- Supports custom make targets

**`prepare_debug_symbols()`**
- Extracts debug symbols from unstripped binaries
- Creates `.debug` files in proper hierarchy
- Strips binaries in staging directory
- Adds `.gnu_debuglink` sections to point to debug files

**`create_multi_deb()`**
- Creates multiple packages from control file definitions
- Distributes files based on package rules
- Handles service files and maintainer scripts
- Generates proper control files with dependencies

**`create_debug_package()`**
- Builds debug symbol package
- Creates GDB init script for path mapping
- Installs to `/usr/lib/debug/` hierarchy

**`create_source_package()`**
- Packages source code for debugging
- Architecture-independent (built once)
- Installs to `/usr/src/<project>-<version>/`

#### Debug Symbol Handling

**Critical Principle**: Extract symbols, strip binaries, add links BEFORE creating packages.

```bash
# 1. Extract debug symbols
objcopy --only-keep-debug /path/to/binary /path/to/binary.debug

# 2. Strip the binary
strip --strip-debug --strip-unneeded /path/to/binary

# 3. Add link to debug symbols
objcopy --add-gnu-debuglink=/path/to/binary.debug /path/to/binary

# 4. Verify the link
readelf -p .gnu_debuglink /path/to/binary
```

**Result:**
- Runtime package: Small, stripped binaries with debuglink
- Debug package: Full debug symbols in separate files
- GDB automatically finds symbols when both packages installed

### 2. GitHub Actions Workflows

Each package has a dedicated workflow file that:

1. **Sets up the build environment** (QEMU, Docker)
2. **Runs the build in a container** (Ubuntu 20.04)
3. **Installs dependencies** (from apt and from previous builds)
4. **Invokes the build script**
5. **Uploads artifacts** (per-architecture)

#### Workflow Structure

```yaml
name: Package <project>

on:
  workflow_dispatch:
    inputs:
      upstream_ref:
        description: 'Upstream tag/branch/commit'
        required: false
  push:
    paths:
      - 'packages/<project>/**'
      - '.github/workflows/package-<project>.yml'
      - 'scripts/build-helpers/**'

permissions:
  contents: write
  packages: write

jobs:
  build:
    name: Build <project> for ${{ matrix.platform }}
    runs-on: ubuntu-22.04
    strategy:
      fail-fast: false
      matrix:
        include:
          - platform: amd64
            docker_platform: linux/amd64
          - platform: arm64
            docker_platform: linux/arm64
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: linux/amd64,linux/arm64
      
      - name: Build package in Docker
        run: |
          docker run --rm --platform=${{ matrix.docker_platform }} \
            -v ${{ github.workspace }}:/workspace \
            -w /workspace \
            ubuntu:20.04 \
            bash -c '
              set -euo pipefail
              
              # Install base dependencies
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              apt-get install -y -qq \
                git \
                build-essential \
                cmake \
                pkg-config \
                file \
                binutils \
                dpkg-dev
              
              # Install project-specific dependencies
              apt-get install -y -qq <dependencies>
              
              # Source build helpers
              source scripts/build-helpers/build-common.sh
              
              # Build package
              build_package "<project>" "${{ matrix.platform }}" "${{ inputs.upstream_ref }}"
            '
      
      - name: List generated packages
        run: |
          echo "Generated packages:"
          ls -lh *.deb || echo "No packages found"
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: <project>-${{ matrix.platform }}-packages
          path: '*.deb'
```

#### Dependency Chain Handling

For projects with dependencies on other packages from this system:

```bash
# Install dependency packages first
if [ -f "dep_1.0_arm64.deb" ]; then
  dpkg -i dep_1.0_arm64.deb || apt-get install -f -y
fi

# Or download from releases
curl -sSL "https://github.com/$REPO/releases/download/dep-1.0/dep_1.0_arm64.deb" -o dep.deb
dpkg -i dep.deb || apt-get install -f -y
```

### 3. Systemd Service Integration

The system automatically handles systemd service files and lifecycle management.

#### Service File Placement

Place service file in package directory:
```
packages/<project>/<project>.service
```

Or for multi-package projects:
```
packages/<project>/<package-name>.service
```

#### Service File Example

```ini
[Unit]
Description=My Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/myservice
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### Automatic Service Management

The build system automatically creates maintainer scripts for service management.

**Generated `postinst` Script:**
```bash
#!/bin/bash
set -e

case "$1" in
    configure)
        if [ -d /run/systemd/system ]; then
            systemctl daemon-reload >/dev/null 2>&1 || true
            
            if ! systemctl is-enabled myservice.service >/dev/null 2>&1; then
                systemctl enable myservice.service >/dev/null 2>&1 || true
            fi
            
            if ! systemctl is-active myservice.service >/dev/null 2>&1; then
                systemctl start myservice.service >/dev/null 2>&1 || true
            fi
        fi
        ;;
esac

exit 0
```

**Generated `prerm` Script:**
```bash
#!/bin/bash
set -e

case "$1" in
    remove|deconfigure)
        if [ -d /run/systemd/system ]; then
            if systemctl is-active myservice.service >/dev/null 2>&1; then
                systemctl stop myservice.service >/dev/null 2>&1 || true
            fi
            
            if systemctl is-enabled myservice.service >/dev/null 2>&1; then
                systemctl disable myservice.service >/dev/null 2>&1 || true
            fi
        fi
        ;;
esac

exit 0
```

**Service File Installation:**
- Service files are installed to `/lib/systemd/system/`
- Only included in runtime packages (not -dev, -dbg, or -dbgsrc)
- Automatically detected and handled during package creation

### 4. Patch Management

Source code patches are automatically applied before building.

#### Patch Directory Structure

```
packages/<project>/
└── patches/
    ├── 001-first-fix.patch
    ├── 002-second-fix.patch
    └── 003-third-fix.patch
```

**Patches are applied in alphabetical order** using `patch -p1`.

#### Patch Format

Patches must be in unified diff format with `a/` and `b/` prefixes:

```diff
--- a/src/file.c
+++ b/src/file.c
@@ -10,7 +10,7 @@
 void function() {
-    old_code();
+    new_code();
 }
```

#### Creating Patches

```bash
# Make changes in the source tree
cd source-dir
# ... edit files ...

# Create patch
git diff > /tmp/fix.patch

# Or without git:
diff -Naur original/ modified/ > fix.patch
```

### 5. Additional Repository Cloning

Some projects require additional git repositories to be cloned into specific subdirectories (e.g., third-party dependencies, git submodules). The build system supports this through the `additional_repos` file.

#### Additional Repos File Format

Create a file at `packages/<project>/additional_repos` with one repository per line:

```
<target-path> <git-url> <ref>
```

**Format details:**
- `target-path`: Relative path from the source directory where the repo should be cloned
- `git-url`: Full git URL (supports https:// and git://)
- `ref`: Git ref to checkout (tag, branch, or commit hash)
- Lines starting with `#` are comments
- Empty lines are ignored

#### Example: Breakpad with Linux System Call Support

```
# packages/breakpad/additional_repos

# Linux System Call Support library - required for breakpad on Linux
src/third_party/lss https://chromium.googlesource.com/linux-syscall-support v2024.02.01
```

This will execute:
```bash
cd source-breakpad
git clone -b v2024.02.01 https://chromium.googlesource.com/linux-syscall-support src/third_party/lss
```

#### Processing Order

Additional repositories are cloned after patches are applied:
1. Clone main upstream repository
2. Apply patches from `patches/` directory
3. Clone additional repositories from `additional_repos` file
4. Build the project

#### Multiple Additional Repositories

You can specify multiple repositories:

```
# packages/myproject/additional_repos

# Third-party dependency 1
vendor/lib1 https://github.com/org/lib1.git v1.0.0

# Third-party dependency 2
vendor/lib2 https://github.com/org/lib2.git main

# Internal submodule
internal/tools https://internal.git.server/tools.git abc123def
```

## Package Creation Process

### Control File Parsing

The build system parses the `control` file to extract:
- Source package name and version
- Upstream URL and ref (tag/branch/commit)
- Build dependencies
- Binary package definitions (one or more)
- Package metadata (section, priority, dependencies, description)

### Multi-Package Distribution

For projects with multiple binary packages (e.g., runtime + dev), files are distributed based on these rules:

**Runtime Package:**
- Binaries in `/usr/bin/`
- Shared libraries (`*.so*`) in `/usr/lib/`
- Data files in `/usr/share/`
- Configuration files in `/etc/`
- Service files in `/lib/systemd/system/`

**Development Package:**
- Header files (`*.h`) in `/usr/include/`
- Static libraries (`*.a`) in `/usr/lib/`
- pkg-config files (`*.pc`) in `/usr/lib/pkgconfig/`

**Debug Package:**
- Debug symbols in `/usr/lib/debug/usr/bin/`
- Debug symbols in `/usr/lib/debug/usr/lib/`
- GDB init script in `/etc/gdb/gdbinit.d/`

**Source Package:**
- All source code in `/usr/src/<project>-<version>/`

### Dependency Detection

**Automatic (for libraries):**
```bash
# Runtime dependencies are auto-detected by scanning ELF files
dpkg-shlibdeps -O /path/to/binary
```

**Manual (in control file):**
```yaml
Depends: libc6, libssl3, other-package (>= 1.0)
```

**Build dependencies:**
```yaml
Build-Depends: pkg-config, libssl-dev, cmake, other-dev
```

### Installed-Size Calculation

The system automatically calculates the installed size for each package:

```bash
# Calculate total size of package contents (excluding DEBIAN/ control dir)
installed_size=$(du -sk "$pkg_dir" 2>/dev/null | cut -f1)
debian_size=$(du -sk "$pkg_dir/DEBIAN" 2>/dev/null | cut -f1)
installed_size=$((installed_size - debian_size))
```

This ensures proper size reporting and eliminates repository warnings.

## Build System Support

### CMake Projects

**Detection:** Presence of `CMakeLists.txt` in source root.

**Build Process:**
```bash
mkdir -p build
cd build

# Configure with debug symbols
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS_RELEASE="-g -O2" \
      -DCMAKE_CXX_FLAGS_RELEASE="-g -O2" \
      <custom-options> \
      ..

# Build
make -j$(nproc)

# Install to staging
make install DESTDIR=/tmp/staging
```

**Custom Options:**
Create `packages/<project>/cmake_options` file:
```
-DENABLE_FEATURE=ON
-DBUILD_TESTS=OFF
```

### Make Projects

**Detection:** Presence of `Makefile` or `configure` script.

**Build Process:**
```bash
# Configure if needed
if [ -f configure ]; then
    ./configure --prefix=/usr
fi

# Build with debug symbols (via gcc wrapper)
make -j$(nproc) CC=/tmp/gcc-wrapper CXX=/tmp/g++-wrapper

# Install to staging
make install DESTDIR=/tmp/staging
```

**GCC Wrapper:**
The system creates wrapper scripts that inject the `-g` flag:
```bash
#!/bin/bash
exec /usr/bin/gcc -g "$@"
```

**Custom Options:**
Create `packages/<project>/make_options` file:
```
PREFIX=/usr
ENABLE_FEATURE=1
```

## Debugging Support

### GDB Integration

After installing runtime + debug + source packages:

```bash
# Start debugging
gdb /usr/bin/myapp

# GDB automatically:
# - Finds debug symbols in /usr/lib/debug/
# - Maps source paths to /usr/src/<project>-<version>/
# - Shows full source code and line numbers
```

**Example GDB Session:**
```
$ gdb /usr/bin/myapp
(gdb) break main
Breakpoint 1 at 0x1234: file main.c, line 42.
(gdb) run
Starting program: /usr/bin/myapp

Breakpoint 1, main (argc=1, argv=0x7fff...) at main.c:42
42          printf("Hello world\n");
(gdb) list
37
38      int main(int argc, char **argv) {
39          init_config();
40          
41          // Print greeting
42          printf("Hello world\n");
43          
44          return process_args(argc, argv);
45      }
46
(gdb) bt
#0  main (argc=1, argv=0x7fff...) at main.c:42
(gdb) info locals
argc = 1
argv = 0x7fffffff...
```

### GDB Auto-Load Script

The debug package includes a GDB init script that automatically maps build paths to installed source paths:

**Location:** `/etc/gdb/gdbinit.d/<project>.gdb`

**Content:**
```gdb
# Auto-configure source paths for debugging
set substitute-path /workspace/source-<project> /usr/src/<project>-<version>
set substitute-path /workspace /usr/src/<project>-<version>
```

This ensures GDB can find source files without manual path configuration.

### Verifying Debug Setup

```bash
# Check for debug symbols
readelf -S /usr/bin/myapp | grep debug

# Check for debug link
readelf -p .gnu_debuglink /usr/bin/myapp

# Check debug file exists
ls -lh /usr/lib/debug/usr/bin/myapp.debug

# Check source code installed
ls -lh /usr/src/<project>-<version>/
```

## Testing and Validation

### Local Testing with act

The `act` tool runs GitHub Actions workflows locally:

```bash
# Install act
brew install act  # macOS
# or from: https://github.com/nektos/act

# Run workflow for specific architecture
cd /path/to/project
act -j build --matrix platform:arm64 --matrix docker_platform:linux/arm64

# Run with timeout
gtimeout 180 act -j build --matrix platform:arm64

# Check generated packages
ls -lh *.deb
```

### Package Verification

**Check package contents:**
```bash
dpkg-deb -c package_1.0.0_amd64.deb
```

**Check package metadata:**
```bash
dpkg-deb -I package_1.0.0_amd64.deb
```

**Check control file:**
```bash
dpkg-deb -e package_1.0.0_amd64.deb /tmp/extract
cat /tmp/extract/control
```

**Verify maintainer scripts:**
```bash
dpkg-deb -e package_1.0.0_amd64.deb /tmp/extract
cat /tmp/extract/postinst
cat /tmp/extract/prerm
```

**Check binary stripping:**
```bash
# Extract and check binary
dpkg-deb -x package_1.0.0_amd64.deb /tmp/extract
file /tmp/extract/usr/bin/myapp
# Should show: "stripped"
```

**Verify debug link:**
```bash
readelf -p .gnu_debuglink /tmp/extract/usr/bin/myapp
# Should show: myapp.debug
```

**Check debug symbols:**
```bash
dpkg-deb -x package-dbg_1.0.0_amd64.deb /tmp/dbg
file /tmp/dbg/usr/lib/debug/usr/bin/myapp.debug
# Should show: "not stripped" with debug info
```

### Installation Testing

```bash
# Install in a container
docker run -it --rm -v $(pwd):/packages ubuntu:20.04 bash

# Inside container:
cd /packages
apt-get update
dpkg -i package_1.0.0_amd64.deb
apt-get install -f -y  # Fix dependencies

# Test service (if applicable)
systemctl status myservice

# Test debug package
dpkg -i package-dbg_1.0.0_amd64.deb
gdb /usr/bin/myapp
```

## Common Patterns and Best Practices

### 1. Naming Conventions

- **Runtime package:** `<project>` (e.g., `rbus`)
- **Development package:** `lib<project>-dev` or `<project>-dev` (e.g., `librbus-dev`)
- **Debug package:** `<project>-dbg` (e.g., `rbus-dbg`)
- **Source package:** `<project>-dbgsrc` (e.g., `rbus-dbgsrc`)

### 2. Version Management

- Use semantic versioning: `MAJOR.MINOR.PATCH`
- Match upstream project versions
- Use git tags for version control: `v1.0.0`
- Version can be overridden with workflow input

### 3. Dependency Chains

For projects that depend on each other, build in order and install dependencies during build.

**Workflow order:**
1. Build dependency packages first
2. Install them in the build container
3. Build dependent packages

### 4. Service Dependencies

For services that depend on other services:

```ini
[Unit]
Description=My Service
After=network.target dependency-service.service
Requires=dependency-service.service

[Service]
ExecStart=/usr/bin/myservice

[Install]
WantedBy=multi-user.target
```

### 5. File Conflicts

**Problem:** Multiple packages try to install the same file.

**Solution:** Only include service files in runtime packages:
```bash
# In create_package_from_section()
if [[ ! "$pkg_name" =~ -(dev|dbg|dbgsrc)$ ]]; then
    # Only install service files for runtime packages
fi
```

### 6. Build Reproducibility

- Always specify exact upstream versions or commit hashes
- Lock build dependencies to specific versions when needed
- Use consistent build flags across architectures
- Document all custom patches and their purpose

### 7. Security Considerations

- Keep build images up to date (ubuntu:20.04)
- Review and audit all patches before applying
- Use official package repositories for dependencies
- Sign packages for production deployment (not covered here)

## Troubleshooting

### Build Failures

**Issue:** "No such file or directory" during build

**Cause:** Missing build dependency

**Solution:** Add to `Build-Depends` in control file

---

**Issue:** "patch: **** Can't find file to patch"

**Cause:** Incorrect patch format or strip level

**Solution:** Ensure patch has `a/` and `b/` prefixes, applied with `-p1`

---

**Issue:** Debug symbols not found by GDB

**Cause:** Debug link not added or debug package not installed

**Solution:** Verify with `readelf -p .gnu_debuglink`, install debug package

---

**Issue:** Service fails to start after installation

**Cause:** Missing runtime dependency or incorrect service file

**Solution:** Check `systemctl status`, verify dependencies, test service file

---

**Issue:** Package size warning

**Cause:** `Installed-Size` not calculated correctly

**Solution:** Ensure size calculation includes all directories except DEBIAN/

---

**Issue:** Architecture mismatch

**Cause:** Building for wrong architecture

**Solution:** Verify `--platform` flag matches matrix configuration

---

**Issue:** File conflict between packages

**Cause:** Multiple packages installing the same file (e.g., service file in both runtime and -dev)

**Solution:** Service files should only be in runtime packages, not -dev/-dbg/-dbgsrc

## Advanced Topics

### Cross-Compilation

The system uses QEMU for cross-architecture builds rather than true cross-compilation:

- **amd64 host → arm64 target:** Run `docker --platform=linux/arm64`
- **arm64 host → amd64 target:** Run `docker --platform=linux/amd64`

QEMU transparently emulates the target architecture.

### Custom Build Steps

For projects requiring special build steps, modify the workflow:

```yaml
- name: Build package in Docker
  run: |
    docker run --rm --platform=${{ matrix.docker_platform }} \
      -v ${{ github.workspace }}:/workspace \
      -w /workspace \
      ubuntu:20.04 \
      bash -c '
        # ... standard setup ...
        
        # Custom pre-build steps
        ./autogen.sh
        ./configure --enable-special-feature
        
        # Standard build
        source scripts/build-helpers/build-common.sh
        build_package "project" "${{ matrix.platform }}"
        
        # Custom post-build steps
        ./run-tests.sh
      '
```

### Multiple Source Repositories

For packages combining multiple upstream sources:

```bash
# In workflow, before building:
git clone https://github.com/org/lib1.git
git clone https://github.com/org/lib2.git

# Modify build script to reference multiple sources
```

### Package Versioning Strategies

**Option 1: Match upstream exactly**
```yaml
Version: 2.7.0
Upstream-Ref: v2.7.0
```

**Option 2: Add packaging revision**
```yaml
Version: 2.7.0-1
Upstream-Ref: v2.7.0
```

**Option 3: Include commit hash for development**
```yaml
Version: 2.7.0+git20251210
Upstream-Ref: abc123
```

## Integration with CI/CD

### Automated Release Workflow

```yaml
on:
  release:
    types: [published]

jobs:
  build:
    # ... build packages ...
  
  upload:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - name: Upload to release
        uses: softprops/action-gh-release@v1
        with:
          files: '**/*.deb'
```

### Package Repository Integration

For setting up an APT repository:

```bash
# Create repository structure
mkdir -p repo/pool/main
cp *.deb repo/pool/main/

# Generate Packages file
cd repo
dpkg-scanpackages pool /dev/null | gzip -9c > pool/Packages.gz

# Create Release file
apt-ftparchive release . > Release
```

## Reference Documentation

### Control File Fields

- **Source:** Source package name
- **Version:** Package version
- **Upstream-URL:** Git repository URL
- **Upstream-Ref:** Git tag, branch, or commit
- **Build-Depends:** Build-time dependencies (comma-separated)
- **Package:** Binary package name
- **Section:** Package category (libs, libdevel, utils, net, admin, etc.)
- **Priority:** optional, required, important, standard
- **Depends:** Runtime dependencies (comma-separated, supports version constraints)
- **Description:** Multi-line description (short summary + detailed paragraphs)

### Standard Debian Sections

- `libs` - Runtime libraries
- `libdevel` - Development libraries and headers
- `utils` - Utility programs
- `net` - Network applications
- `admin` - System administration tools
- `debug` - Debug symbol packages

### Maintainer Script Triggers

- **preinst:** Before package installation
- **postinst:** After package installation
- **prerm:** Before package removal
- **postrm:** After package removal

### Common Package Relationships

- **Depends:** Required for package to function
- **Recommends:** Strongly suggested but not required
- **Suggests:** Optional enhancements
- **Conflicts:** Cannot be installed together
- **Replaces:** Supersedes another package

## Glossary

- **dpkg:** Debian package manager
- **dpkg-deb:** Tool for manipulating .deb files
- **GNU debuglink:** ELF section linking stripped binary to debug symbols
- **objcopy:** Tool for copying and modifying object files
- **QEMU:** Machine emulator for cross-architecture builds
- **shlibdeps:** Tool for detecting shared library dependencies
- **strip:** Tool for removing debug symbols from binaries

## Migration Guide

To adopt this system for a new project:

1. **Create package directory:** `packages/<project>/`
2. **Write control file:** Define metadata and packages
3. **Create workflow:** Copy and adapt existing workflow
4. **Add build configuration:** `build_system`, options files if needed
5. **Add patches:** If source modifications needed
6. **Add service file:** If project includes a daemon
7. **Test locally:** Use `act` to verify build
8. **Push and test:** Verify CI build
9. **Create release:** Tag and release packages

---

**System Version:** 1.0  
**Last Updated:** December 2025  
**Maintained by:** Package Workflows Team
