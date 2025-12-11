# Workflow Template Guide

This document explains how to use the workflow template to create package build workflows for new upstream projects.

## Quick Start

1. Copy the template:
   ```bash
   cp templates/workflow-template.yml .github/workflows/package-myproject.yml
   ```

2. Replace all instances of `<PROJECT>` with your project name:
   ```bash
   sed -i 's/<PROJECT>/myproject/g' .github/workflows/package-myproject.yml
   ```

3. Customize triggers and options as needed

4. Commit and push to enable the workflow

## Template Variables

Replace these placeholders in the template:

- **`<PROJECT>`** - The project name (must match directory name in `packages/`)

Example: For QuickJS, replace `<PROJECT>` with `quickjs`

## Workflow Triggers

The template includes three trigger types. Customize based on your needs:

### 1. Scheduled Builds (Optional)
```yaml
schedule:
  - cron: '0 0 * * 0'  # Weekly on Sunday
```

Uncomment to enable automatic builds. Useful for tracking upstream updates.

**Common schedules:**
- Daily: `'0 0 * * *'`
- Weekly: `'0 0 * * 0'`
- Monthly: `'0 0 1 * *'`

### 2. Manual Dispatch (Always Enabled)
```yaml
workflow_dispatch:
  inputs:
    upstream_ref:
      description: 'Upstream tag/branch/commit'
      default: ''
```

Allows manual triggering with optional upstream version override. Useful for:
- Testing new upstream versions
- Rebuilding specific versions
- One-off builds

### 3. Push Triggers (Always Enabled)
```yaml
push:
  paths:
    - 'packages/<PROJECT>/**'
    - '.github/workflows/package-<PROJECT>.yml'
```

Automatically rebuilds when:
- Package metadata changes
- Patches are updated
- Workflow file is modified
- Build scripts change

## Build Process

The workflow performs these steps:

1. **Checkout** - Clone this repository
2. **QEMU Setup** - Enable multi-architecture builds
3. **Docker Build** - Run build in isolated container:
   - Install base tools (git, build-essential, dpkg-dev)
   - Parse control file for build dependencies
   - Install project-specific build dependencies
   - Source build helper scripts
   - Execute `build_package()` function
4. **List Packages** - Show generated .deb files
5. **Upload Artifacts** - Store packages in GitHub Actions
6. **Upload to Release** (optional) - Attach to GitHub releases

## Matrix Strategy

Builds run in parallel for multiple architectures:

```yaml
strategy:
  matrix:
    include:
      - platform: amd64
        docker_platform: linux/amd64
      - platform: arm64
        docker_platform: linux/arm64
```

**To add more architectures:**
```yaml
- platform: armhf
  docker_platform: linux/arm/v7
```

**To build for single architecture only:**
Remove the matrix and hardcode values:
```yaml
steps:
  - name: Build package
    run: |
      docker run --platform=linux/amd64 ...
```

## Artifact Configuration

### Retention Period
```yaml
retention-days: 90  # Keep artifacts for 90 days
```

Change based on your needs:
- Development builds: 30 days
- Release builds: 90 days
- Important releases: 365 days (max)

### Artifact Naming
```yaml
name: <PROJECT>-${{ matrix.platform }}-deb
```

Creates separate artifacts per architecture:
- `quickjs-amd64-deb`
- `quickjs-arm64-deb`

## Release Upload (Optional)

Uncomment to automatically attach packages to GitHub releases:

```yaml
- name: Upload to release
  if: github.event_name == 'release'
  uses: softprops/action-gh-release@v1
  with:
    files: '*.deb'
```

**When to enable:**
- You create GitHub releases for your packaging repo
- You want permanent public download links
- You want versioned package distributions

**When to skip:**
- Packages are only for internal use
- You use artifacts exclusively
- You have an external package repository

## Build Dependencies

The workflow automatically installs dependencies from the control file:

```yaml
BUILD_DEPS=$(grep "^Build-Depends:" "$CONTROL_FILE" | sed "s/^Build-Depends: *//")
apt-get install -y -qq $BUILD_DEPS_CLEAN
```

**Supported formats:**
- Simple list: `gcc, make, cmake`
- With versions: `gcc (>= 9), make, cmake (>= 3.10)`
- Alternatives: `gcc | clang`

Version constraints are stripped for apt-get installation.

## Docker Image

Default base image:
```yaml
ubuntu:20.04
```

**To use different image:**
```yaml
docker run --rm --platform=${{ matrix.docker_platform }} \
  -v ${{ github.workspace }}:/workspace \
  -w /workspace \
  ubuntu:22.04 \  # Or debian:bullseye, etc.
```

**Trade-offs:**
- `ubuntu:20.04` - Wider compatibility, older packages
- `ubuntu:22.04` - Newer tools, may limit deployment targets
- `debian:bullseye` - More conservative, stable

## Customization Examples

### Add CMake from Kitware PPA
```yaml
apt-get install -y -qq software-properties-common
add-apt-repository -y ppa:kitware/ppa
apt-get update -qq
apt-get install -y -qq cmake
```

### Enable ccache for faster rebuilds
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.ccache
    key: ccache-${{ matrix.platform }}-${{ hashFiles('packages/<PROJECT>/**') }}

# In Docker:
apt-get install -y -qq ccache
export PATH="/usr/lib/ccache:$PATH"
```

### Add verification step
```yaml
- name: Verify packages
  run: |
    for deb in *.deb; do
      echo "Verifying $deb"
      dpkg-deb -I "$deb"
      dpkg-deb -c "$deb"
    done
```

## Testing Locally

Use [nektos/act](https://github.com/nektos/act) to test workflows locally:

```bash
# Test for amd64
act -j build --matrix platform:amd64

# Test with workflow dispatch
act workflow_dispatch -j build --input upstream_ref=v1.2.3

# Test specific workflow
act -W .github/workflows/package-quickjs.yml
```

## Troubleshooting

### Build fails with "command not found"
- Add missing tool to `Build-Depends` in control file
- Or add explicit `apt-get install` in workflow

### Packages not uploaded
- Check `if-no-files-found: error` setting
- Verify `*.deb` files are created in workspace root
- Check Docker volume mount is correct

### Slow arm64 builds
- Normal - QEMU emulation is 2-3x slower than native
- Consider caching strategies (ccache, Docker layers)
- Or use self-hosted arm64 runners

### Workflow doesn't trigger
- Check trigger paths match your changes
- Ensure workflow file is in `.github/workflows/`
- Verify YAML syntax is valid

## Best Practices

1. **Start simple** - Use template as-is for first project
2. **Test locally** - Use act before pushing to GitHub
3. **Enable on push** - Catch packaging issues early
4. **Schedule thoughtfully** - Don't spam builds unnecessarily
5. **Document customizations** - Add comments for project-specific changes
6. **Keep matrix** - Build for both architectures by default
7. **Version retention** - Balance storage costs vs. convenience

## Example: Complete QuickJS Workflow

See `.github/workflows/package-quickjs.yml` for a working example (once implemented).
