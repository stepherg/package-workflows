#!/usr/bin/env python3
"""
Build all packages in dependency order without creating a container.
Assumes commands are run in an existing build environment (container or host).
Reads Build-Depends from control files and builds packages in the correct order.
"""

import os
import sys
import subprocess
import re
from pathlib import Path
from collections import defaultdict, deque
from typing import Dict, List, Set, Tuple, Optional

# Color codes for terminal output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

def log_info(message: str):
    print(f"{BLUE}ℹ{NC} {message}")

def log_success(message: str):
    print(f"{GREEN}✓{NC} {message}")

def log_error(message: str):
    print(f"{RED}✗{NC} {message}", file=sys.stderr)

def log_warning(message: str):
    print(f"{YELLOW}⚠{NC} {message}")

def parse_control_file(control_path: Path) -> Tuple[Optional[str], Set[str]]:
    """
    Parse control file and extract package name and custom dependencies.
    Returns: (package_name, set of custom package dependencies)
    """
    with open(control_path, 'r') as f:
        content = f.read()
    
    # Get package name from Source: field
    source_match = re.search(r'^Source:\s*(\S+)', content, re.MULTILINE)
    if not source_match:
        return None, set()
    
    package_name = source_match.group(1)
    
    # Get Build-Depends
    build_deps_match = re.search(r'^Build-Depends:\s*(.*)$', content, re.MULTILINE)
    if not build_deps_match:
        return package_name, set()
    
    build_deps = build_deps_match.group(1).strip()
    
    # Parse dependencies - split by comma and clean up
    deps = set()
    for dep in build_deps.split(','):
        dep = dep.strip()
        # Remove version constraints
        dep = re.sub(r'\s*\([^)]*\)', '', dep)
        
        # Filter out system packages (common ones that end with -dev)
        system_packages = {
            'gcc', 'make', 'cmake', 'meson', 'ninja-build', 'python3-pip',
            'perl', 'pkg-config', 'pkgconf', 'debhelper-compat',
            'zlib1g-dev', 'libdbus-1-dev', 'libssl-dev', 'openssl-dev',
            'libcurl4-openssl-dev', 'curl4-openssl-dev',
            'uuid-dev', 'libcjson-dev', 'libmsgpack-dev', 'libmsgpackc2',
            'libjansson-dev', 'liblog4c-dev', 'liblog4c3',
            'libxml2-dev', 'libspdlog-dev', 'libprotobuf-dev',
            'protobuf-compiler', 'grpc++', 'libgrpc++-dev',
            'libjson-c-dev', 'build-essential', 'autoconf', 'automake',
            'libtool', 'cargo', 'rustc'
        }
        
        if dep and dep not in system_packages:
            # Map dev packages to base package names
            # For -dev packages, try removing -dev suffix
            original_dep = dep
            if dep.endswith('-dev'):
                dep = dep[:-4]  # Remove -dev
            deps.add(dep)
    
    return package_name, deps


def get_workflow_file(package_name: str, workflows_dir: Path) -> Optional[Path]:
    """Find the workflow file for a package."""
    workflow_file = workflows_dir / f"package-{package_name}.yml"
    if workflow_file.exists():
        return workflow_file
    return None


def get_binary_package_names(package_name: str, packages_dir: Path) -> List[str]:
    """
    Get all binary package names produced by a source package.
    Reads the control file and extracts all Package: fields.
    """
    control_file = packages_dir / package_name / "control"
    if not control_file.exists():
        return [package_name]
    
    with open(control_file, 'r') as f:
        content = f.read()
    
    # Find all Package: lines
    packages = re.findall(r'^Package:\s*(\S+)', content, re.MULTILINE)
    return packages if packages else [package_name]

def build_dependency_graph(packages_dir: Path, workflows_dir: Path) -> Tuple[Dict[str, Set[str]], Dict[str, Path]]:
    """
    Build a dependency graph from all control files.
    Returns: (dependency_graph, workflow_map)
    """
    graph = {}
    workflow_map = {}
    
    for control_file in packages_dir.glob("*/control"):
        package_name, deps = parse_control_file(control_file)
        if package_name:
            graph[package_name] = deps
            workflow = get_workflow_file(package_name, workflows_dir)
            if workflow:
                workflow_map[package_name] = workflow
    
    return graph, workflow_map

def topological_sort(graph: Dict[str, Set[str]]) -> List[str]:
    """
    Perform topological sort on the dependency graph.
    Returns packages in build order (dependencies first).
    """
    all_nodes = set(graph.keys())
    
    # Filter out dependencies that aren't source packages (no control file)
    # These are binary package names that will be built as part of their source package
    for package in graph:
        graph[package] = {dep for dep in graph[package] if dep in all_nodes}
    
    # Calculate in-degree for each node
    in_degree = {node: 0 for node in all_nodes}
    for node in graph:
        for dep in graph[node]:
            if dep in in_degree:
                in_degree[dep] += 1
    
    # Find all nodes with no dependencies (in-degree 0)
    # These are packages that nothing depends on, so they can be built last
    # We want to build dependencies first, so we need to reverse the logic
    
    # Actually, let's build a reverse graph: if A depends on B, then B -> A
    reverse_graph = defaultdict(set)
    for node in graph:
        for dep in graph[node]:
            if dep in all_nodes:
                reverse_graph[dep].add(node)
    
    # Now use the reverse graph: packages with no incoming deps in reverse = leaf nodes
    # Calculate in-degree in the reverse graph
    in_degree_reverse = {node: len(graph[node]) for node in all_nodes}
    
    # Nodes with 0 in-degree in reverse graph are the ones we should build first
    queue = deque([node for node in all_nodes if in_degree_reverse[node] == 0])
    result = []
    
    while queue:
        # Sort queue alphabetically for deterministic ordering
        queue = deque(sorted(queue))
        node = queue.popleft()
        result.append(node)
        
        # Remove this node from the graph
        for dependent in reverse_graph.get(node, set()):
            in_degree_reverse[dependent] -= 1
            if in_degree_reverse[dependent] == 0:
                queue.append(dependent)
    
    # Check for cycles
    if len(result) != len(all_nodes):
        remaining = all_nodes - set(result)
        log_error(f"Circular dependency detected involving: {', '.join(sorted(remaining))}")
        # Show what each remaining package depends on
        for pkg in sorted(remaining):
            deps = graph.get(pkg, set())
            log_error(f"  {pkg} depends on: {', '.join(sorted(deps))}")
        sys.exit(1)
    
    return result


def build_package(package_name: str, platform: str, timeout_seconds: int, output_file=None, force_source: bool = False) -> bool:
    """
    Build a single package locally (no container).
    Returns True on success, False on failure.
    """
    package_log = f"/tmp/build-{package_name}.log"

    # Use gtimeout on macOS, timeout on Linux
    timeout_cmd = "gtimeout" if sys.platform == "darwin" else "timeout"

    # Build the bash script
    force_source_flag = "--force-source" if force_source else ""
    bash_script = (
        "set -euo pipefail && "
        "source scripts/build-helpers/build-common.sh && "
        f"install_build_dependencies {package_name} && "
        f"build_package {package_name} {platform} '' {force_source_flag}"
    )

    # timeout_cmd, str(timeout_seconds),

    cmd = [
        "bash", "-c", bash_script
    ]

    # Debug: print the command
    log_info(f"  Running: bash -c 'build {package_name}'")

    try:
        if output_file:
            # If output_file is specified, redirect to it with headers
            with open(output_file, 'a') as log:
                # Write header for this package in the combined log
                log.write(f"\n{'=' * 80}\n")
                log.write(f"Building package: {package_name}\n")
                log.write(f"{'=' * 80}\n\n")

                result = subprocess.run(
                    cmd,
                    stdout=log,
                    stderr=subprocess.STDOUT
                )
        else:
            # Default: show output on stdout and also save to individual log file
            with open(package_log, 'w') as log:
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )

                # Stream output to both stdout and log file
                for line in process.stdout:
                    print(line, end='')
                    log.write(line)

                process.wait()
                result = process

        if result.returncode == 0:
            return True
        elif result.returncode in (124, 143):  # timeout
            log_error(f"Build timed out ({timeout_seconds}s)")
            return False
        else:
            log_error(f"Build failed with exit code {result.returncode}")
            return False
    except Exception as e:
        log_error(f"Build error: {e}")
        return False
    finally:
        if not output_file:
            log_info(f"  Log saved to: {package_log}")


def main():
    # Parse arguments
    platform = "arm64"
    timeout_seconds = 600
    dry_run = False
    log_file = None
    skip_existing = True
    single_package = None
    force_source = False

    if "--help" in sys.argv or "-h" in sys.argv:
        print("Usage: build-packages-local.py [OPTIONS]")
        print("\nOptions:")
        print("  --platform ARCH       Platform to build for (default: arm64)")
        print("  --timeout SECONDS     Timeout per package in seconds (default: 600)")
        print("  --log-file PATH      Save build logs to file instead of stdout")
        print("  --rebuild-existing   Rebuild packages even if .deb files already exist")
        print("  --force-source       Force re-cloning and patching source even if it exists")
        print("  --package NAME       Build only the specified package (without dependencies)")
        print("  --dry-run            Show build order without building")
        print("  --help, -h           Show this help message")
        print("\nNote: By default, packages with existing .deb files are skipped.")
        print("      This script runs builds locally without creating a container.")
        print("      Make sure you're in the correct build environment before running.")
        sys.exit(0)

    if "--platform" in sys.argv:
        idx = sys.argv.index("--platform")
        platform = sys.argv[idx + 1]

    if "--timeout" in sys.argv:
        idx = sys.argv.index("--timeout")
        timeout_seconds = int(sys.argv[idx + 1])

    if "--log-file" in sys.argv:
        idx = sys.argv.index("--log-file")
        log_file = sys.argv[idx + 1]

    if "--rebuild-existing" in sys.argv:
        skip_existing = False

    if "--force-source" in sys.argv:
        force_source = True

    if "--package" in sys.argv:
        idx = sys.argv.index("--package")
        single_package = sys.argv[idx + 1]

    if "--dry-run" in sys.argv:
        dry_run = True

    # Set up paths
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    packages_dir = repo_root / "packages"
    workflows_dir = repo_root / ".github" / "workflows"

    log_info("=" * 60)
    if single_package:
        log_info(f"Building package: {single_package}")
    else:
        log_info("Building all packages in dependency order")
    log_info(f"Platform: {platform}")
    log_info(f"Timeout per package: {timeout_seconds}s")
    if log_file:
        log_info(f"Build output will be saved to: {log_file}")
    log_info(f"Build environment: LOCAL (no container)")
    log_info("=" * 60)

    # Build dependency graph
    log_info("Analyzing package dependencies...")
    graph, workflow_map = build_dependency_graph(packages_dir, workflows_dir)

    # Sort packages by dependencies
    log_info("Calculating build order...")
    build_order = topological_sort(graph)

    # Filter to single package if requested
    if single_package:
        if single_package not in build_order:
            log_error(f"Package '{single_package}' not found")
            log_info(f"Available packages: {', '.join(sorted(build_order))}")
            sys.exit(1)

        # Build only the specified package
        build_order = [single_package]

        log_info(f"\nBuilding only package '{single_package}'")

    # Display dependency information
    log_info("\nDependency Graph:")
    for package in build_order:
        deps = graph.get(package, set())
        if deps:
            log_info(f"  {package} depends on: {', '.join(sorted(deps))}")
        else:
            log_info(f"  {package} (no custom dependencies)")

    log_info(f"\nBuild order: {' → '.join(build_order)}")
    log_info(f"\nTotal packages to build: {len(build_order)}")
    log_info("=" * 60)

    if dry_run:
        log_info("\n--dry-run mode: Showing build order only, not building packages")
        log_success(f"\nWould build {len(build_order)} packages in this order:")
        for idx, package_name in enumerate(build_order, 1):
            log_info(f"  {idx}. {package_name}")
        sys.exit(0)

    # Build packages in order
    succeeded = []
    failed = []
    skipped = []

    for idx, package_name in enumerate(build_order, 1):
        # Check if package already exists
        if skip_existing:
            # Get all binary package names produced by this source package
            binary_packages = get_binary_package_names(package_name, packages_dir)
            existing_debs = []
            for binary_pkg in binary_packages:
                deb_pattern = f"{binary_pkg}_*_{platform}.deb"
                existing_debs.extend(repo_root.glob(deb_pattern))

            if existing_debs:
                log_info(f"\n[{idx}/{len(build_order)}] Skipping {package_name} (found {len(existing_debs)} .deb file(s))")
                skipped.append(package_name)
                continue

        log_info(f"\n[{idx}/{len(build_order)}] Building {package_name}...")

        # workflow = workflow_map.get(package_name)
        # if not workflow:
        #    log_error(f"Workflow file not found for {package_name}")
        #    failed.append(package_name)
        #    break

        if build_package(package_name, platform, timeout_seconds, log_file, force_source):
            log_success(f"[{idx}/{len(build_order)}] ✓ {package_name} built successfully")
            succeeded.append(package_name)
        else:
            log_error(f"[{idx}/{len(build_order)}] ✗ {package_name} build failed")
            failed.append(package_name)
            log_error("Build failed, stopping...")
            break

    # Print summary
    log_info("\n" + "=" * 60)
    log_info("Build Summary")
    log_info("=" * 60)

    if skipped:
        log_info(f"Skipped (already built): {len(skipped)}/{len(build_order)}")
        for package in skipped:
            log_info(f"  ⊙ {package}")

    log_success(f"Succeeded: {len(succeeded)}/{len(build_order)}")

    if succeeded:
        for package in succeeded:
            log_success(f"  ✓ {package}")

    if failed:
        log_error(f"Failed: {len(failed)}/{len(build_order)}")
        for package in failed:
            log_error(f"  ✗ {package}")
        if log_file:
            log_info(f"\nComplete build log saved to: {log_file}")
        sys.exit(1)
    else:
        log_success("\nAll packages built successfully!")
        if log_file:
            log_info(f"\nComplete build log saved to: {log_file}")
        sys.exit(0)


if __name__ == "__main__":
    main()
