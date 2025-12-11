# Control File Format Specification

This document describes the format of control files used to define package metadata in the `packages/<project>/` directories.

## Overview

Control files use a Debian-style format with `Field: Value` syntax. They define both source package information (upstream details) and binary package information (what gets installed).

## File Location

Each project has a control file at:
```
packages/<project>/control
```

## Required Fields

### Source Package Fields

These fields describe the upstream source and versioning:

- **`Source:`** - Source package name (usually same as project name)
- **`Version:`** - Debian package version (e.g., `2024-01-03`, `1.2.3-1`)
- **`Upstream-URL:`** - Full git URL to upstream repository
- **`Upstream-Ref:`** - Git ref to checkout (tag, branch, or commit SHA)

Example:
```
Source: quickjs
Version: 2024-01-03
Upstream-URL: https://github.com/bellard/quickjs.git
Upstream-Ref: 2024-01-03
```

### Binary Package Fields

These fields describe the packages that will be built:

- **`Package:`** - Binary package name
- **`Architecture:`** - Target architectures (`any`, `all`, `amd64`, `arm64`)
- **`Depends:`** - Runtime dependencies (comma-separated)
- **`Build-Depends:`** - Build-time dependencies (comma-separated)
- **`Description:`** - Short and long description

Example:
```
Package: quickjs
Architecture: any
Depends: libc6 (>= 2.17)
Build-Depends: gcc, make
Description: Small JavaScript engine
 QuickJS is a small and embeddable JavaScript engine.
 It supports the ES2020 specification including modules,
 async functions, and proxies.
```

## Optional Fields

- **`Section:`** - Package section (default: `misc`)
- **`Priority:`** - Package priority (default: `optional`)
- **`Homepage:`** - Upstream project homepage
- **`Maintainer:`** - Package maintainer (overrides default)

## Field Format Rules

### Single-Line Fields
Most fields are single-line:
```
Field: Value
```

### Multi-Line Fields
Description and other long fields use continuation lines (start with space):
```
Description: Short one-line summary
 Longer description paragraph that continues
 on multiple lines. Each continuation line
 starts with a single space.
```

### Dependency Syntax
Dependencies use Debian package syntax:
```
Depends: package1, package2 (>= 1.0), package3 | package4
```

- Multiple packages separated by commas
- Version constraints: `(>= 1.0)`, `(<< 2.0)`, `(= 1.5)`
- Alternatives: `package1 | package2` (either package works)

## Multiple Binary Packages

You can define multiple binary packages from one source:

```
Source: myproject
Version: 1.0.0
Upstream-URL: https://github.com/user/myproject.git
Upstream-Ref: v1.0.0

Package: myproject
Architecture: any
Depends: libc6 (>= 2.17)
Build-Depends: gcc, cmake
Description: Main package
 This is the main runtime package.

Package: myproject-dev
Architecture: any
Depends: myproject (= 1.0.0)
Description: Development files
 Headers and static libraries for development.
```

## Architecture Values

Common architecture values:

- **`any`** - Build for all architectures (architecture-dependent code)
- **`all`** - Architecture-independent (docs, scripts, arch-independent data)
- **`amd64`** - x86-64 only
- **`arm64`** - ARM 64-bit only
- **`amd64 arm64`** - Specific architectures only

## Version String Format

Version strings should follow Debian conventions:

- **Upstream version**: `1.2.3`, `2024-01-03`
- **With Debian revision**: `1.2.3-1`, `2024-01-03-2`
- **With epoch**: `1:1.2.3` (rarely needed)

The version string is used in:
- Package filename: `package_version_arch.deb`
- Control file `Version:` field
- Dependency version constraints

## Complete Example

```
# QuickJS package control file
Source: quickjs
Version: 2024-01-03
Upstream-URL: https://github.com/bellard/quickjs.git
Upstream-Ref: 2024-01-03

Package: quickjs
Architecture: any
Depends: libc6 (>= 2.17)
Build-Depends: gcc, make
Section: interpreters
Priority: optional
Homepage: https://bellard.org/quickjs/
Description: Small and embeddable JavaScript engine
 QuickJS is a small and embeddable JavaScript engine. It supports
 the ES2020 specification including modules, asynchronous generators,
 proxies and BigInt.
 .
 It includes:
  - A command line interpreter (qjs)
  - A compiler (qjsc) 
  - Support for ES2020 modules
 .
 It is designed to be small and fast while supporting most of the
 JavaScript language features.

Package: libquickjs-dev
Architecture: any
Depends: quickjs (= 2024-01-03)
Section: libdevel
Description: Development files for QuickJS
 This package contains the header files and static library needed to
 develop applications that use the QuickJS engine.
```

## Field Processing

The build system processes control files as follows:

1. **Parse control file** - Extract field values
2. **Clone upstream** - Use `Upstream-URL` and `Upstream-Ref`
3. **Install build dependencies** - From `Build-Depends` field
4. **Build project** - Using detected build system
5. **Detect dependencies** - Auto-detect with `dpkg-shlibdeps`, merge with `Depends:`
6. **Create package** - Generate control file and build `.deb`

## Validation

Required fields must be present:
- ✅ `Version`, `Upstream-URL`, `Upstream-Ref`
- ✅ At least one `Package:` declaration
- ✅ Each package needs `Architecture` and `Description`

The build will fail if required fields are missing.

## Comments

Lines starting with `#` are treated as comments:
```
# This is a comment
Source: myproject
# Another comment
Version: 1.0.0
```

## Parsing Functions

The `scripts/build-helpers/parse-control.sh` script provides:

- `get_control_field` - Extract single-line field
- `get_control_field_multiline` - Extract multi-line field
- `parse_control_file` - Parse and export all common fields
- `list_binary_packages` - List all binary package names

## References

This format is based on Debian control file syntax:
- [Debian Policy Manual - Control Files](https://www.debian.org/doc/debian-policy/ch-controlfields.html)
- [Debian New Maintainer's Guide](https://www.debian.org/doc/manuals/maint-guide/)
