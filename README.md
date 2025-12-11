# Package Workflows

A centralized repository for building Debian packages (and potentially other formats) from upstream open-source projects.

## Purpose

This repository contains GitHub Actions workflows that automatically build Debian packages from external upstream projects that either don't provide official packages or whose packages are outdated. Each upstream project gets its own workflow that handles cloning, patching, building, and packaging.

## Structure

```
package-workflows/
├── .github/workflows/       # Per-project build workflows
│   └── package-<project>.yml
├── packages/                # Project metadata and configuration
│   └── <project>/
│       ├── control          # Package metadata (Debian-style)
│       └── patches/         # Optional patches for packaging
├── scripts/
│   └── build-helpers/       # Shared build scripts
├── templates/               # Templates for new projects
└── README.md
```

## Features

- **Multi-Architecture Support**: Builds for amd64 and arm64 using Docker + QEMU
- **Build System Detection**: Auto-detects and adapts to Make, CMake, Autotools, or Meson
- **Version Pinning**: Reproducible builds from specific upstream tags/commits
- **Patch Management**: Apply packaging-specific patches when needed
- **Automated Workflows**: Scheduled builds and manual triggers
- **Consistent Packaging**: Standardized package structure across diverse build systems

## Adding a New Project

1. Create project metadata directory:
   ```bash
   mkdir -p packages/<project>/patches
   ```

2. Create control file with package metadata:
   ```bash
   cat > packages/<project>/control << EOF
   Source: <project>
   Version: <version>
   Upstream-URL: https://github.com/user/repo.git
   Upstream-Ref: <tag-or-commit>
   
   Package: <project>
   Architecture: any
   Depends: libc6 (>= 2.17)
   Build-Depends: gcc, make
   Description: Short description
    Long description here.
   EOF
   ```

3. Create workflow from template:
   ```bash
   cp templates/workflow-template.yml .github/workflows/package-<project>.yml
   # Edit to customize for your project
   ```

4. Test locally:
   ```bash
   act -j build -W .github/workflows/package-<project>.yml
   ```

5. Commit and push to trigger builds

## Current Projects

- **[QuickJS](packages/quickjs/)** - Small and embeddable JavaScript engine (ES2020 support)

## Requirements

- GitHub Actions (no local requirements for CI builds)
- For local testing: [nektos/act](https://github.com/nektos/act)

## License

*(To be determined)*

## Contributing

See [openspec/](openspec/) for development proposals and specifications.
