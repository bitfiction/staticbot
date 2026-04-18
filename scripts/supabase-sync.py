#!/usr/bin/env python3
"""
Supabase Upstream Sync Tool

Detects upstream Supabase changes and applies safe image bumps across all
Staticbot Terraform templates. Generates versions.md changelog entries.

Usage:
    python scripts/supabase-sync.py detect          # Show what changed
    python scripts/supabase-sync.py detect --json   # Machine-readable output
    python scripts/supabase-sync.py apply --safe     # Auto-apply image bumps
    python scripts/supabase-sync.py report           # Generate versions.md entry
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

WORKSPACE = Path.home() / "Dev" / "Workspaces" / "staticbot"
UPSTREAM = WORKSPACE / "supabase" / "supabase" / "docker"

# Service name → image prefix (used for matching in both docker-compose and TF)
SERVICE_IMAGES = {
    "studio":    "supabase/studio:",
    "kong":      "kong/kong:",
    "auth":      "supabase/gotrue:",
    "rest":      "postgrest/postgrest:",
    "realtime":  "supabase/realtime:",
    "storage":   "supabase/storage-api:",
    "imgproxy":  "darthsim/imgproxy:",
    "meta":      "supabase/postgres-meta:",
    "functions": "supabase/edge-runtime:",
    "analytics": "supabase/logflare:",
    "db":        "supabase/postgres:",
    "vector":    "timberio/vector:",
    "supavisor": "supabase/supavisor:",
}

TEMPLATES = {
    "do_single": {
        "label": "DO Single-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "do_supabase_self_hosting_template",
        "docker_copy": True,
        "tf_files": {
            "auth":      "k8s-services-core.tf",
            "rest":      "k8s-services-core.tf",
            "realtime":  "k8s-services-core.tf",
            "storage":   "k8s-services-core.tf",
            "imgproxy":  "k8s-services-core.tf",
            "kong":      "k8s-services-gateway.tf",
            "studio":    "k8s-services-gateway.tf",
            "meta":      "k8s-services-gateway.tf",
            "analytics": "k8s-services-gateway.tf",
            "functions": "k8s-services-gateway.tf",
            "supavisor": "k8s-services-gateway.tf",
            "db":        "k8s-services-data.tf",
            "vector":    "k8s-services-data.tf",
        },
    },
    "aws_single": {
        "label": "AWS Single-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "aws_supabase_self_hosting_template",
        "docker_copy": True,
        "tf_files": {
            "auth":      "ecs-services-core.tf",
            "rest":      "ecs-services-core.tf",
            "realtime":  "ecs-services-core.tf",
            "storage":   "ecs-services-core.tf",
            "imgproxy":  "ecs-services-core.tf",
            "kong":      "ecs-services-gateway.tf",
            "studio":    "ecs-services-gateway.tf",
            "meta":      "ecs-services-gateway.tf",
            "analytics": "ecs-services-gateway.tf",
            "functions": "ecs-services-gateway.tf",
            "supavisor": "ecs-services-gateway.tf",
            "db":        "ecs-services-data.tf",
            "vector":    "ecs-services-data.tf",
        },
    },
    "mt_shared": {
        "label": "Multi-Tenant Shared",
        "base": WORKSPACE / "staticbot-control-center" / "infra" / "digitalocean" / "modules-tenants" / "shared",
        "docker_copy": False,
        "tf_files": {
            "realtime":  "k8s-services-shared.tf",
            "supavisor": "k8s-services-shared.tf",
            "imgproxy":  "k8s-services-shared.tf",
            "meta":      "k8s-services-shared.tf",
            "db":        "k8s-services-data.tf",
            "vector":    "k8s-services-data.tf",
            "analytics": "k8s-services-data.tf",
        },
    },
    "mt_tenant": {
        "label": "Multi-Tenant Per-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "do_supabase_multi_tenant_tenant",
        "docker_copy": False,
        "tf_files": {
            "auth":      "k8s-services.tf",
            "rest":      "k8s-services.tf",
            "storage":   "k8s-services.tf",
            "functions": "k8s-services.tf",
            "db":        "k8s-provisioning.tf",
        },
    },
}

# Volume directories to diff (relative to docker/)
VOLUME_DIRS = ["volumes/db", "volumes/api", "volumes/pooler", "volumes/logs", "volumes/functions"]

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_upstream_images() -> dict[str, str]:
    """Parse image tags from upstream docker-compose.yml."""
    compose_path = UPSTREAM / "docker-compose.yml"
    if not compose_path.exists():
        print(f"ERROR: Upstream docker-compose.yml not found at {compose_path}", file=sys.stderr)
        sys.exit(1)

    content = compose_path.read_text()
    images = {}

    # Match lines like: image: supabase/gotrue:v2.186.0
    for match in re.finditer(r"image:\s*(\S+)", content):
        full_image = match.group(1)
        for service, prefix in SERVICE_IMAGES.items():
            if full_image.startswith(prefix):
                images[service] = full_image
                break

    return images


def parse_template_images(template: dict) -> dict[str, str]:
    """Parse image tags from a template's Terraform files."""
    images = {}
    seen_files = set()

    for service, tf_file in template["tf_files"].items():
        filepath = template["base"] / tf_file
        if not filepath.exists():
            continue

        if tf_file not in seen_files:
            seen_files.add(tf_file)

        content = filepath.read_text()
        prefix = SERVICE_IMAGES[service]

        # Match patterns like: image = "supabase/gotrue:v2.186.0" or image     = "..."
        for match in re.finditer(r'image\s*=\s*"([^"]+)"', content):
            full_image = match.group(1)
            if full_image.startswith(prefix):
                images[service] = full_image
                break

    return images


def get_last_sync_date() -> str | None:
    """Read the most recent date from the DO single-tenant versions.md."""
    versions_path = TEMPLATES["do_single"]["base"] / "docker" / "versions.md"
    if not versions_path.exists():
        return None

    content = versions_path.read_text()
    dates = re.findall(r"^## (\d{4}-\d{2}-\d{2})", content, re.MULTILINE)
    return dates[0] if dates else None


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

def detect_image_changes() -> list[dict]:
    """Detect image version differences between upstream and templates."""
    upstream = parse_upstream_images()
    changes = []

    for service, upstream_image in sorted(upstream.items()):
        for tmpl_key, tmpl in TEMPLATES.items():
            if service not in tmpl["tf_files"]:
                continue

            tmpl_images = parse_template_images(tmpl)
            current = tmpl_images.get(service)

            if current and current != upstream_image:
                changes.append({
                    "service": service,
                    "template": tmpl_key,
                    "template_label": tmpl["label"],
                    "current": current,
                    "upstream": upstream_image,
                    "tier": 1,
                })

    # Deduplicate: group by service, show which templates are affected
    return changes


def detect_volume_diffs() -> list[dict]:
    """Detect differences in volume files between upstream and templates."""
    diffs = []

    for vol_dir in VOLUME_DIRS:
        upstream_dir = UPSTREAM / vol_dir

        for tmpl_key, tmpl in TEMPLATES.items():
            if tmpl["docker_copy"]:
                tmpl_dir = tmpl["base"] / "docker" / vol_dir
            else:
                # Multi-tenant templates may have volume files differently
                # Check if the dir exists under the template base
                tmpl_dir = tmpl["base"] / "docker" / vol_dir
                if not tmpl_dir.exists():
                    continue

            if not upstream_dir.exists() or not tmpl_dir.exists():
                continue

            # Run diff
            result = subprocess.run(
                ["diff", "-rq", str(upstream_dir), str(tmpl_dir)],
                capture_output=True, text=True
            )

            if result.returncode != 0 and result.stdout.strip():
                diffs.append({
                    "volume": vol_dir,
                    "template": tmpl_key,
                    "template_label": tmpl["label"],
                    "diff_summary": result.stdout.strip(),
                    "tier": 3,
                })

    return diffs


def detect_env_changes() -> list[dict]:
    """Detect new environment variables in upstream .env.example."""
    env_path = UPSTREAM / ".env.example"
    if not env_path.exists():
        return []

    content = env_path.read_text()

    # Extract all non-commented env var names
    upstream_vars = set()
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            var_name = line.split("=", 1)[0].strip()
            upstream_vars.add(var_name)

    # Compare with our known set (from our .env.example copies)
    our_env_path = TEMPLATES["do_single"]["base"] / "docker" / ".env.example"
    if not our_env_path.exists():
        return []

    our_content = our_env_path.read_text()
    our_vars = set()
    for line in our_content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            var_name = line.split("=", 1)[0].strip()
            our_vars.add(var_name)

    new_vars = upstream_vars - our_vars
    removed_vars = our_vars - upstream_vars

    changes = []
    if new_vars:
        changes.append({
            "type": "new_env_vars",
            "vars": sorted(new_vars),
            "tier": 2,
        })
    if removed_vars:
        changes.append({
            "type": "removed_env_vars",
            "vars": sorted(removed_vars),
            "tier": 2,
        })

    return changes


def run_detect(as_json: bool = False):
    """Run full detection and print report."""
    image_changes = detect_image_changes()
    volume_diffs = detect_volume_diffs()
    env_changes = detect_env_changes()

    last_sync = get_last_sync_date() or "unknown"

    if as_json:
        print(json.dumps({
            "last_sync": last_sync,
            "date": str(date.today()),
            "image_changes": image_changes,
            "volume_diffs": volume_diffs,
            "env_changes": env_changes,
        }, indent=2))
        return

    print(f"=== Supabase Upstream Sync Report ===")
    print(f"Last synced: {last_sync}")
    print(f"Report date: {date.today()}")
    print()

    # Group image changes by service
    tier1_by_service: dict[str, dict] = {}
    for ch in image_changes:
        svc = ch["service"]
        if svc not in tier1_by_service:
            tier1_by_service[svc] = {
                "current": ch["current"],
                "upstream": ch["upstream"],
                "templates": [],
            }
        tier1_by_service[svc]["templates"].append(ch["template_label"])

    if tier1_by_service:
        total_files = len(image_changes)
        total_templates = len({ch["template"] for ch in image_changes})
        print(f"TIER 1 (auto-safe) — run `apply --safe` to update:")
        for svc, info in sorted(tier1_by_service.items()):
            print(f"  {info['current']} → {info['upstream']}")
            print(f"    Templates: {', '.join(info['templates'])}")
        print(f"  Affects: {total_files} file references across {total_templates} templates")
        print()
    else:
        print("TIER 1: All images up to date.")
        print()

    if volume_diffs:
        print("TIER 3 (review-required) — volume file differences:")
        for d in volume_diffs:
            print(f"  {d['volume']} ({d['template_label']}):")
            for line in d["diff_summary"].splitlines():
                print(f"    {line}")
        print()

    if env_changes:
        for ch in env_changes:
            if ch["type"] == "new_env_vars":
                print(f"TIER 2 (review-light) — new env vars in upstream .env.example:")
                for var in ch["vars"]:
                    print(f"  + {var}")
                print()
            elif ch["type"] == "removed_env_vars":
                print(f"TIER 2 (review-light) — removed env vars from upstream .env.example:")
                for var in ch["vars"]:
                    print(f"  - {var}")
                print()

    if not tier1_by_service and not volume_diffs and not env_changes:
        print("Everything is in sync with upstream.")


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

def apply_safe():
    """Apply TIER 1 changes: image tag bumps across all templates."""
    image_changes = detect_image_changes()

    if not image_changes:
        print("No image changes to apply. Everything is in sync.")
        return

    # Group by (current_image, upstream_image) to do bulk replacements
    replacements: dict[tuple[str, str], list[str]] = {}
    for ch in image_changes:
        key = (ch["current"], ch["upstream"])
        if key not in replacements:
            replacements[key] = []
        replacements[key].append(ch["template"])

    files_modified = set()

    for (old_image, new_image), tmpl_keys in sorted(replacements.items()):
        for tmpl_key in tmpl_keys:
            tmpl = TEMPLATES[tmpl_key]
            # Find which service this is
            service = None
            for svc, prefix in SERVICE_IMAGES.items():
                if old_image.startswith(prefix):
                    service = svc
                    break
            if not service or service not in tmpl["tf_files"]:
                continue

            tf_file = tmpl["tf_files"][service]
            filepath = tmpl["base"] / tf_file

            if not filepath.exists():
                print(f"  WARNING: {filepath} not found, skipping")
                continue

            content = filepath.read_text()
            if old_image in content:
                content = content.replace(old_image, new_image)
                filepath.write_text(content)
                files_modified.add(str(filepath))
                print(f"  Updated {old_image} → {new_image}")
                print(f"    in {filepath.relative_to(WORKSPACE)}")

    # Sync docker/ directories for single-tenant templates
    for tmpl_key, tmpl in TEMPLATES.items():
        if not tmpl["docker_copy"]:
            continue

        src = UPSTREAM
        dst = tmpl["base"] / "docker"

        if not dst.exists():
            print(f"  WARNING: {dst} not found, skipping docker copy for {tmpl['label']}")
            continue

        # rsync upstream docker/ → template docker/, excluding .env
        result = subprocess.run(
            [
                "rsync", "-a", "--delete",
                "--exclude", ".env",
                "--exclude", ".env.example",  # We track this separately
                str(src) + "/",
                str(dst) + "/",
            ],
            capture_output=True, text=True
        )

        if result.returncode == 0:
            print(f"  Synced upstream docker/ → {tmpl['label']} docker/")
        else:
            print(f"  WARNING: rsync failed for {tmpl['label']}: {result.stderr}")

    # Also sync .env.example separately (so we can detect env var changes)
    for tmpl_key, tmpl in TEMPLATES.items():
        if not tmpl["docker_copy"]:
            continue
        src_env = UPSTREAM / ".env.example"
        dst_env = tmpl["base"] / "docker" / ".env.example"
        if src_env.exists() and dst_env.parent.exists():
            shutil.copy2(src_env, dst_env)

    print(f"\nDone. Modified {len(files_modified)} Terraform files.")
    print("Run `terraform validate` in each template to verify.")


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def generate_report():
    """Generate a versions.md changelog entry for applied changes."""
    upstream = parse_upstream_images()
    today = date.today().isoformat()

    # Compare against what's in the templates NOW (after apply)
    # We use the last sync's versions from versions.md
    versions_path = TEMPLATES["do_single"]["base"] / "docker" / "versions.md"
    if not versions_path.exists():
        print("ERROR: versions.md not found", file=sys.stderr)
        sys.exit(1)

    content = versions_path.read_text()

    # Parse the most recent version block to find previous versions
    prev_versions: dict[str, str] = {}
    lines = content.splitlines()
    in_block = False
    for line in lines:
        if line.startswith("## "):
            if in_block:
                break  # Only parse the first (most recent) block
            in_block = True
            continue
        if in_block and line.startswith("- "):
            # Parse: - supabase/gotrue:v2.186.0 (prev supabase/gotrue:v2.185.0)
            match = re.match(r"- (\S+)", line)
            if match:
                full_image = match.group(1)
                for svc, prefix in SERVICE_IMAGES.items():
                    if full_image.startswith(prefix):
                        prev_versions[svc] = full_image
                        break

    # Build the new entry by comparing current upstream with our tracked versions
    # First get ALL current versions from the do_single template (most complete)
    current = parse_template_images(TEMPLATES["do_single"])

    changes = []
    for svc, upstream_img in sorted(upstream.items()):
        current_img = current.get(svc)
        if current_img and current_img != upstream_img:
            changes.append(f"- {upstream_img} (prev {current_img})")
        elif not current_img and svc in prev_versions and prev_versions[svc] != upstream_img:
            changes.append(f"- {upstream_img} (prev {prev_versions[svc]})")

    if not changes:
        # No new changes vs current templates, but maybe templates were just updated
        # Show current state vs previous versions.md entry
        for svc, current_img in sorted(current.items()):
            prev_img = prev_versions.get(svc)
            if prev_img and prev_img != current_img:
                changes.append(f"- {current_img} (prev {prev_img})")

    if not changes:
        print("No version changes to report.")
        return

    entry = f"\n## {today}\n" + "\n".join(changes) + "\n"
    print("Generated versions.md entry:")
    print(entry)

    # Ask whether to prepend to versions.md files
    response = input("Prepend to versions.md in both single-tenant templates? [y/N] ")
    if response.lower() == "y":
        for tmpl_key in ["do_single", "aws_single"]:
            tmpl = TEMPLATES[tmpl_key]
            vpath = tmpl["base"] / "docker" / "versions.md"
            if vpath.exists():
                existing = vpath.read_text()
                # Insert after the header line
                header_end = existing.index("\n") + 1
                new_content = existing[:header_end] + entry + existing[header_end:]
                vpath.write_text(new_content)
                print(f"  Updated {vpath.relative_to(WORKSPACE)}")
        print("Done.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Supabase Upstream Sync Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    detect_parser = subparsers.add_parser("detect", help="Detect upstream changes")
    detect_parser.add_argument("--json", action="store_true", help="JSON output")

    apply_parser = subparsers.add_parser("apply", help="Apply changes")
    apply_parser.add_argument("--safe", action="store_true", required=True,
                              help="Only apply TIER 1 (image bumps)")

    subparsers.add_parser("report", help="Generate versions.md entry")

    args = parser.parse_args()

    # Validate upstream exists
    if not UPSTREAM.exists():
        print(f"ERROR: Upstream not found at {UPSTREAM}", file=sys.stderr)
        print("Run: cd ~/Dev/Workspaces/staticbot/supabase/supabase && git pull", file=sys.stderr)
        sys.exit(1)

    if args.command == "detect":
        run_detect(as_json=args.json)
    elif args.command == "apply":
        apply_safe()
    elif args.command == "report":
        generate_report()


if __name__ == "__main__":
    main()
