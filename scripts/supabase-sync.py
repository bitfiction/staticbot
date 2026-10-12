#!/usr/bin/env python3
"""
Supabase Upstream Sync Tool

Detects upstream Supabase changes and applies safe image bumps across all
Staticbot Terraform templates. Keeps each template's docker/ reference copy in
sync with upstream and records which upstream commit it was synced from.

Usage:
    python scripts/supabase-sync.py detect          # Show what changed
    python scripts/supabase-sync.py detect --json   # Machine-readable output
    python scripts/supabase-sync.py apply --safe     # Auto-apply image bumps + docker/ sync
    python scripts/supabase-sync.py report           # Summarize image changes from the last sync

Before running, update the upstream checkout (the bitfiction/supabase fork
clone tracks supabase/supabase as the `upstream` remote):

    git -C ~/Dev/Workspaces/supabot/supabase pull --ff-only upstream master
"""

import argparse
import json
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
UPSTREAM = Path.home() / "Dev" / "Workspaces" / "supabot" / "supabase" / "docker"
STATE_FILE = Path(__file__).with_name("supabase-sync.state.json")

# Compose files we read image tags from. The base file is the default stack;
# the overrides carry services our templates always run (logs) or alternate
# version tracks we still support (pg15).
UPSTREAM_COMPOSE_FILES = [
    "docker-compose.yml",
    "docker-compose.logs.yml",
    "docker-compose.pg15.yml",
]

# Service name → image prefix (used for matching in both docker-compose and TF)
SERVICE_IMAGES = {
    "studio":    "supabase/studio:",
    "api-gw":    "envoyproxy/envoy:",
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

# Images upstream no longer ships by default. A template still referencing one
# needs a manual migration, not a tag bump.
RETIRED_IMAGES = {
    "kong/kong:": "Kong is deprecated upstream (superseded by Envoy, self-hosted 0.8.0)",
}

TEMPLATES = {
    "do_single": {
        "label": "DO Single-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "do_supabase_self_hosting_template",
        "docker_sync": "full",
    },
    "aws_single": {
        "label": "AWS Single-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "aws_supabase_self_hosting_template",
        "docker_sync": "full",
    },
    "mt_shared": {
        "label": "Multi-Tenant Shared",
        "base": WORKSPACE / "staticbot-control-center" / "infra" / "digitalocean" / "modules-tenants" / "shared",
        "docker_sync": "subset",
    },
    "mt_tenant": {
        "label": "Multi-Tenant Per-Tenant",
        "base": WORKSPACE / "staticbot" / "infrastructure" / "_templates" / "do_supabase_multi_tenant_template",
        "docker_sync": "subset",
    },
}

# Volume directories to diff (relative to docker/)
VOLUME_DIRS = ["volumes/db", "volumes/api", "volumes/pooler", "volumes/logs", "volumes/functions"]

# Upstream files a "subset" template must carry even if they are missing locally,
# because the template's Terraform reads them.
SUBSET_REQUIRED = {
    "mt_tenant": [
        "volumes/functions/deno.jsonc",
        "volumes/api/envoy/envoy.yaml",
        "volumes/api/envoy/cds.yaml",
        "volumes/api/envoy/lds.template.yaml",
        "volumes/api/envoy/docker-entrypoint.sh",
    ],
}

# Paths under docker/ we deliberately don't sync from upstream. Suppressed from
# TIER 3 output so unimportant drift doesn't drown out real review items.
# Keyed by path relative to UPSTREAM (docker/), value is the reason.
IGNORED_VOLUME_PATHS: dict[str, str] = {
    "volumes/db/init": "Legacy dir; data.sql is empty and not mounted by upstream docker-compose.yml",
}

# Templates whose databases are upgraded in place by a migrate job
# (k8s/db-lifecycle): image migrations a newer Postgres image adds need an
# apply/skip decision there, and changed upstream init SQL needs a template
# migration, because existing databases never re-run first-boot SQL.
DB_LIFECYCLE_TEMPLATES = ["mt_tenant"]

# Upstream files whose changes always need a human to port them into Terraform.
REVIEW_FILES = [
    "docker-compose.yml",
    "docker-compose.logs.yml",
    "docker-compose.pg15.yml",
    ".env.example",
    "volumes/api/envoy/envoy.yaml",
    "volumes/api/envoy/cds.yaml",
    "volumes/api/envoy/lds.template.yaml",
    "volumes/api/envoy/docker-entrypoint.sh",
    "volumes/logs/vector.yml",
]

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def service_for_image(image: str) -> str | None:
    for service, prefix in SERVICE_IMAGES.items():
        if image.startswith(prefix):
            return service
    return None


def image_track(service: str, image: str) -> str:
    """Return the version track an image belongs to.

    Postgres majors are separate tracks: a template pinned to 15 must only ever
    get 15.x bumps. Every other service has a single track.
    """
    if service == "db":
        return image.split(":", 1)[1].split(".", 1)[0]
    return ""


def compose_images(content: str) -> dict[str, dict[str, str]]:
    """{service: {track: image}} for every known image in a compose file."""
    images: dict[str, dict[str, str]] = {}
    # Match lines like: image: supabase/gotrue:v2.186.0
    for match in re.finditer(r"^\s*image:\s*(\S+)", content, re.MULTILINE):
        full_image = match.group(1)
        service = service_for_image(full_image)
        if service:
            images.setdefault(service, {})[image_track(service, full_image)] = full_image
    return images


def parse_upstream_images() -> dict[str, dict[str, str]]:
    """Parse image tags from upstream compose files → {service: {track: image}}."""
    if not (UPSTREAM / "docker-compose.yml").exists():
        print(f"ERROR: Upstream docker-compose.yml not found at {UPSTREAM}", file=sys.stderr)
        sys.exit(1)

    images: dict[str, dict[str, str]] = {}
    for name in UPSTREAM_COMPOSE_FILES:
        path = UPSTREAM / name
        if path.exists():
            for service, tracks in compose_images(path.read_text()).items():
                images.setdefault(service, {}).update(tracks)
    return images


def template_tf_files(template: dict) -> list[Path]:
    return sorted(p for p in template["base"].glob("*.tf") if p.is_file())


def parse_template_images(template: dict) -> list[dict]:
    """Find every image reference in a template's Terraform files.

    Matches any quoted image string, so `image = "..."` attributes and images
    kept in locals/maps (e.g. one per Postgres major) are both covered.
    """
    prefixes = [*SERVICE_IMAGES.values(), *RETIRED_IMAGES]
    quoted = re.compile(r'"((?:' + "|".join(re.escape(p) for p in prefixes) + r')[^"\s]+)"')
    refs = []
    for filepath in template_tf_files(template):
        for match in quoted.finditer(filepath.read_text()):
            refs.append({"file": filepath, "image": match.group(1)})
    return refs


def git(*args: str) -> str | None:
    result = subprocess.run(["git", "-C", str(UPSTREAM.parent), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def upstream_head() -> dict:
    commit = git("rev-parse", "HEAD")
    return {"commit": commit, "date": git("log", "-1", "--format=%cs", "HEAD") if commit else None}


def warn_if_upstream_stale():
    """Warn when the local checkout is behind the supabase/supabase remote."""
    if git("rev-parse", "--verify", "--quiet", "upstream/master") is None:
        print("NOTE: no `upstream` remote in the fork checkout; can't check freshness.")
        print("      git -C ~/Dev/Workspaces/supabot/supabase remote add upstream https://github.com/supabase/supabase.git")
        print()
        return
    behind = git("rev-list", "--count", "HEAD..upstream/master")
    if behind and behind != "0":
        print(f"WARNING: local upstream checkout is {behind} commits behind upstream/master (as of the last fetch).")
        print("         git -C ~/Dev/Workspaces/supabot/supabase pull --ff-only upstream master")
        print()


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def get_last_sync() -> dict:
    """Last synced upstream commit, falling back to versions.md for old checkouts."""
    state = load_state()
    if state.get("commit"):
        return state

    versions_path = TEMPLATES["do_single"]["base"] / "docker" / "versions.md"
    if versions_path.exists():
        dates = re.findall(r"^## (\d{4}-\d{2}-\d{2})", versions_path.read_text(), re.MULTILINE)
        if dates:
            return {"commit": None, "date": dates[0]}
    return {}


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

def _ref_info(tmpl_key: str, tmpl: dict, ref: dict) -> dict:
    return {
        "template": tmpl_key,
        "template_label": tmpl["label"],
        "file": str(ref["file"].relative_to(WORKSPACE)),
        "image": ref["image"],
    }


def detect_image_changes() -> tuple[list[dict], list[dict]]:
    """Detect image version differences between upstream and templates.

    Returns (changes, problems). Problems are references that can't be bumped
    automatically: retired images, or a Postgres major upstream no longer ships.
    """
    upstream = parse_upstream_images()
    changes, problems = [], []

    for tmpl_key, tmpl in TEMPLATES.items():
        seen = set()
        for ref in parse_template_images(tmpl):
            current = ref["image"]
            if (ref["file"], current) in seen:
                continue
            seen.add((ref["file"], current))

            retired = next((why for prefix, why in RETIRED_IMAGES.items() if current.startswith(prefix)), None)
            if retired:
                problems.append({**_ref_info(tmpl_key, tmpl, ref), "problem": retired, "tier": 4})
                continue

            service = service_for_image(current)
            track = image_track(service, current)
            target = upstream.get(service, {}).get(track)
            if target is None:
                problems.append({
                    **_ref_info(tmpl_key, tmpl, ref),
                    "problem": f"upstream no longer ships a {service} image on track '{track or 'default'}'",
                    "tier": 4,
                })
            elif current != target:
                changes.append({
                    **_ref_info(tmpl_key, tmpl, ref),
                    "service": service,
                    "current": current,
                    "upstream": target,
                    "tier": 1,
                })

    return changes, problems


def _parse_diff_line(line: str) -> dict | None:
    """Parse one `diff -rq` output line into a structured entry."""
    m = re.match(r"^Files (.+) and (.+) differ$", line)
    if m:
        upstream_file = Path(m.group(1))
        try:
            rel = str(upstream_file.relative_to(UPSTREAM))
        except ValueError:
            rel = str(upstream_file)
        return {"kind": "differ", "rel_path": rel}

    m = re.match(r"^Only in (.+): (.+)$", line)
    if m:
        dir_path = Path(m.group(1))
        name = m.group(2)
        try:
            rel_dir = str(dir_path.relative_to(UPSTREAM))
            return {"kind": "only_upstream", "rel_path": f"{rel_dir}/{name}"}
        except ValueError:
            return {"kind": "only_template", "rel_path": name}
    return None


def _matches_ignore(rel_path: str) -> str | None:
    """Return the ignore reason if rel_path is suppressed, else None."""
    for ignored_path, reason in IGNORED_VOLUME_PATHS.items():
        if rel_path == ignored_path or rel_path.startswith(ignored_path + "/"):
            return reason
    return None


def get_upstream_commits(rel_path: str, since: str | None, limit: int = 3) -> list[str]:
    """Return upstream commits touching docker/<rel_path>, newest first.

    With a recorded sync commit, only commits after it are listed; otherwise the
    most recent `limit` commits are shown as context.
    """
    rev = [f"{since}..HEAD"] if since else [f"-{limit}"]
    out = git("log", *rev, "--no-merges", "--pretty=format:%h %ad %s", "--date=short", "--", f"docker/{rel_path}")
    return [l for l in (out or "").splitlines() if l.strip()]


def detect_volume_diffs(since: str | None) -> tuple[list[dict], list[dict]]:
    """Detect volume-file differences between upstream and templates.

    Returns (diffs, ignored). `ignored` holds entries matched by IGNORED_VOLUME_PATHS
    so the caller can show them under a separate "suppressed" section.
    """
    diffs: list[dict] = []
    ignored: list[dict] = []

    for vol_dir in VOLUME_DIRS:
        upstream_dir = UPSTREAM / vol_dir

        for tmpl_key, tmpl in TEMPLATES.items():
            tmpl_dir = tmpl["base"] / "docker" / vol_dir
            if not upstream_dir.exists() or not tmpl_dir.exists():
                continue

            result = subprocess.run(
                ["diff", "-rq", str(upstream_dir), str(tmpl_dir)],
                capture_output=True, text=True
            )
            if result.returncode == 0 or not result.stdout.strip():
                continue

            for line in result.stdout.splitlines():
                entry = _parse_diff_line(line)
                if not entry:
                    continue
                # Subset templates only carry the files their Terraform reads.
                if entry["kind"] == "only_upstream" and tmpl["docker_sync"] == "subset" \
                        and entry["rel_path"] not in SUBSET_REQUIRED.get(tmpl_key, []):
                    continue
                entry.update({
                    "volume": vol_dir,
                    "template": tmpl_key,
                    "template_label": tmpl["label"],
                    "tier": 3,
                })

                reason = (
                    _matches_ignore(entry["rel_path"])
                    if entry["kind"] != "only_template"
                    else None
                )
                if reason:
                    entry["reason"] = reason
                    ignored.append(entry)
                    continue

                if entry["kind"] == "differ":
                    # Drift that predates the last sync has no commits in the range;
                    # show the latest ones so the reviewer still sees why.
                    entry["commits"] = get_upstream_commits(entry["rel_path"], since) \
                        or get_upstream_commits(entry["rel_path"], None)
                diffs.append(entry)

    return diffs, ignored


def _env_var_names(content: str) -> set[str]:
    names = set()
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            names.add(line.split("=", 1)[0].strip())
    return names


def detect_env_changes(since: str | None) -> list[dict]:
    """Detect env var names added/removed in upstream .env.example since the last sync."""
    env_path = UPSTREAM / ".env.example"
    if not env_path.exists():
        return []
    upstream_vars = _env_var_names(env_path.read_text())

    if since:
        previous = git("show", f"{since}:docker/.env.example")
    else:
        our_env_path = TEMPLATES["do_single"]["base"] / "docker" / ".env.example"
        previous = our_env_path.read_text() if our_env_path.exists() else None
    if previous is None:
        return []
    our_vars = _env_var_names(previous)

    changes = []
    if upstream_vars - our_vars:
        changes.append({"type": "new_env_vars", "vars": sorted(upstream_vars - our_vars), "tier": 2})
    if our_vars - upstream_vars:
        changes.append({"type": "removed_env_vars", "vars": sorted(our_vars - upstream_vars), "tier": 2})
    return changes


def detect_review_files(since: str | None) -> list[dict]:
    """Upstream config files changed since the last sync that need porting to Terraform."""
    if not since:
        return []
    changed = []
    for rel in REVIEW_FILES:
        commits = get_upstream_commits(rel, since)
        if commits:
            changed.append({"rel_path": rel, "commits": commits, "tier": 3})
    return changed


def image_migrations(image: str) -> list[str] | None:
    """List an image's built-in migrations (needs Docker; None if unavailable)."""
    if shutil.which("docker") is None:
        return None
    result = subprocess.run(
        ["docker", "run", "--rm", "--entrypoint", "ls", image, "/docker-entrypoint-initdb.d/migrations"],
        capture_output=True, text=True,
    )
    return result.stdout.split() if result.returncode == 0 else None


def decided_image_migrations(tmpl: dict) -> set[str]:
    path = tmpl["base"] / "k8s" / "db-lifecycle" / "image-migrations.txt"
    if not path.exists():
        return set()
    return {line.split()[0] for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")}


def detect_db_lifecycle(image_changes: list[dict], volume_diffs: list[dict]) -> list[dict]:
    """What existing databases need by hand: image-migration decisions and template migrations."""
    items = []
    for tmpl_key in DB_LIFECYCLE_TEMPLATES:
        tmpl = TEMPLATES[tmpl_key]
        for ch in image_changes:
            if ch["template"] != tmpl_key or ch["service"] != "db":
                continue
            old, new = image_migrations(ch["current"]), image_migrations(ch["upstream"])
            if old is None or new is None:
                items.append({"template_label": tmpl["label"], "kind": "decide", "image": ch["upstream"],
                              "files": None, "hint": f"docker run --rm --entrypoint ls {ch['upstream']} /docker-entrypoint-initdb.d/migrations"})
                continue
            undecided = sorted(set(new) - set(old) - decided_image_migrations(tmpl))
            if undecided:
                items.append({"template_label": tmpl["label"], "kind": "decide", "image": ch["upstream"], "files": undecided})
        changed_sql = sorted({d["rel_path"] for d in volume_diffs if d["template"] == tmpl_key and d["rel_path"].startswith("volumes/db/")})
        if changed_sql:
            items.append({"template_label": tmpl["label"], "kind": "template_migration", "files": changed_sql})
    return items


def run_detect(as_json: bool = False):
    """Run full detection and print report."""
    last = get_last_sync()
    since = last.get("commit")
    head = upstream_head()

    image_changes, image_problems = detect_image_changes()
    volume_diffs, ignored_diffs = detect_volume_diffs(since)
    env_changes = detect_env_changes(since)
    review_files = detect_review_files(since)
    db_lifecycle = detect_db_lifecycle(image_changes, volume_diffs)

    if as_json:
        print(json.dumps({
            "last_sync": last,
            "upstream_head": head,
            "date": str(date.today()),
            "image_changes": image_changes,
            "image_problems": image_problems,
            "volume_diffs": volume_diffs,
            "ignored_volume_diffs": ignored_diffs,
            "env_changes": env_changes,
            "review_files": review_files,
            "db_lifecycle": db_lifecycle,
        }, indent=2))
        return

    print("=== Supabase Upstream Sync Report ===")
    warn_if_upstream_stale()
    print(f"Last synced: {last.get('date', 'unknown')} ({(since or 'commit unknown')[:10]})")
    print(f"Upstream:    {head.get('date')} ({(head.get('commit') or '?')[:10]})")
    print(f"Report date: {date.today()}")
    print()

    # Group image changes by (current, upstream) so each bump prints once.
    tier1: dict[tuple[str, str], list[str]] = {}
    for ch in image_changes:
        labels = tier1.setdefault((ch["current"], ch["upstream"]), [])
        if ch["template_label"] not in labels:
            labels.append(ch["template_label"])

    if tier1:
        total_templates = len({ch["template"] for ch in image_changes})
        print("TIER 1 (auto-safe) — run `apply --safe` to update:")
        for (current, upstream), labels in sorted(tier1.items()):
            print(f"  {current} → {upstream}")
            print(f"    Templates: {', '.join(labels)}")
        print(f"  Affects: {len(image_changes)} file references across {total_templates} templates")
        print()
    else:
        print("TIER 1: All images up to date.")
        print()

    if image_problems:
        print("TIER 4 (breaking) — images that can't be bumped automatically:")
        for p in image_problems:
            print(f"  ! {p['image']}  [{p['template_label']}: {p['file']}]")
            print(f"    {p['problem']}")
        print()

    if review_files:
        print("TIER 3 (review-required) — upstream config changed since last sync; port to Terraform:")
        for f in review_files:
            print(f"  ~ {f['rel_path']}")
            for c in f["commits"]:
                print(f"      {c}")
        print(f"  Full diff: git -C {UPSTREAM.parent} diff {since[:10]}..HEAD -- docker/<file>")
        print()

    if volume_diffs:
        print("TIER 3 (review-required) — volume file differences:")
        # Group by (kind, rel_path) so we explain each change once and list templates.
        grouped: dict[tuple[str, str], dict] = {}
        for d in volume_diffs:
            key = (d["kind"], d["rel_path"])
            if key not in grouped:
                grouped[key] = {**d, "templates": []}
            grouped[key]["templates"].append(d["template_label"])

        for (kind, path), info in sorted(grouped.items()):
            marker = {"differ": "~", "only_upstream": "+", "only_template": "-"}[kind]
            label = {
                "differ": "modified upstream",
                "only_upstream": "new in upstream",
                "only_template": "template-only (not in upstream)",
            }[kind]
            print(f"  {marker} {path}  [{label}]")
            print(f"    Templates: {', '.join(info['templates'])}")
            commits = info.get("commits") or []
            if kind == "differ":
                if commits:
                    print("    Upstream commits:")
                    for c in commits:
                        print(f"      {c}")
                else:
                    print("    (no upstream history found for this file)")
        print()

    if db_lifecycle:
        print("TIER 3 (review-required) — existing tenant databases (k8s/db-lifecycle):")
        for item in db_lifecycle:
            if item["kind"] == "decide":
                print(f"  {item['template_label']}: {item['image']} adds image migrations; add 'apply' or 'skip <reason>'")
                print("    to k8s/db-lifecycle/image-migrations.txt, or the migrate job fails:")
                for f in item["files"] or [f"(Docker unavailable; list them with: {item['hint']})"]:
                    print(f"      {f}")
            else:
                print(f"  {item['template_label']}: upstream init SQL changed; existing databases only get it through a")
                print("    template migration in k8s/db-lifecycle/migrations/:")
                for f in item["files"]:
                    print(f"      {f}")
        print()

    if ignored_diffs:
        # Collapse to unique paths so each reason prints once.
        unique: dict[str, dict] = {}
        for d in ignored_diffs:
            unique.setdefault(d["rel_path"], d)
        print(f"Suppressed ({len(unique)} path(s) ignored via IGNORED_VOLUME_PATHS):")
        for path, d in sorted(unique.items()):
            print(f"  {path} — {d['reason']}")
        print()

    for ch in env_changes:
        added = ch["type"] == "new_env_vars"
        print(f"TIER 2 (review-light) — {'new env vars in' if added else 'removed env vars from'} upstream .env.example:")
        for var in ch["vars"]:
            print(f"  {'+' if added else '-'} {var}")
        print()

    if not (tier1 or image_problems or review_files or volume_diffs or env_changes or db_lifecycle):
        print("Everything is in sync with upstream.")


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

def sync_docker_dir(tmpl_key: str, tmpl: dict) -> list[str]:
    """Bring a template's docker/ reference copy in line with upstream."""
    dst = tmpl["base"] / "docker"
    if not dst.exists():
        return [f"WARNING: {dst} not found, skipping docker sync for {tmpl['label']}"]

    if tmpl["docker_sync"] == "full":
        # Mirror upstream docker/ exactly. Staticbot-specific adaptations live
        # outside docker/ (e.g. k8s/), so --delete never removes our own files.
        result = subprocess.run(
            ["rsync", "-a", "--delete", "--exclude", ".env", "--exclude", ".DS_Store",
             str(UPSTREAM) + "/", str(dst) + "/"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return [f"WARNING: rsync failed for {tmpl['label']}: {result.stderr}"]
        return [f"Synced upstream docker/ → {tmpl['label']} docker/"]

    # Subset: refresh only the files the template carries (plus required ones).
    messages = []
    rel_paths = {str(p.relative_to(dst)) for p in dst.rglob("*") if p.is_file() and p.name != ".DS_Store"}
    rel_paths.update(SUBSET_REQUIRED.get(tmpl_key, []))
    for rel in sorted(rel_paths):
        src = UPSTREAM / rel
        target = dst / rel
        if not src.exists():
            messages.append(f"WARNING: {tmpl['label']} docker/{rel} no longer exists upstream")
            continue
        if not target.exists() or target.read_bytes() != src.read_bytes():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
            messages.append(f"Updated {tmpl['label']} docker/{rel}")
    return messages


def apply_safe():
    """Apply TIER 1 changes (image tag bumps) and sync docker/ reference copies."""
    image_changes, image_problems = detect_image_changes()

    by_file: dict[str, list[tuple[str, str]]] = {}
    for ch in image_changes:
        pairs = by_file.setdefault(ch["file"], [])
        if (ch["current"], ch["upstream"]) not in pairs:
            pairs.append((ch["current"], ch["upstream"]))

    for rel_file, pairs in sorted(by_file.items()):
        filepath = WORKSPACE / rel_file
        content = filepath.read_text()
        for old_image, new_image in pairs:
            # Replace whole quoted references only, so a tag never matches a longer tag.
            content = content.replace(f'"{old_image}"', f'"{new_image}"')
            print(f"  Updated {old_image} → {new_image}")
            print(f"    in {rel_file}")
        filepath.write_text(content)

    for tmpl_key, tmpl in TEMPLATES.items():
        for message in sync_docker_dir(tmpl_key, tmpl):
            print(f"  {message}")

    head = upstream_head()
    if head.get("commit"):
        previous = load_state().get("commit")
        STATE_FILE.write_text(json.dumps({
            "commit": head["commit"],
            "date": head["date"],
            "synced_on": str(date.today()),
            "previous_commit": previous if previous != head["commit"] else load_state().get("previous_commit"),
        }, indent=2) + "\n")
        print(f"  Recorded upstream commit {head['commit'][:10]} in {STATE_FILE.name}")

    if image_problems:
        print(f"\n{len(image_problems)} image reference(s) need manual migration — see `detect`.")

    print(f"\nDone. Modified {len(by_file)} Terraform files.")
    print("Image bumps are the easy part: port the TIER 2/3 changes `detect` listed before this run,")
    print("then run `tofu validate` in each template.")


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def generate_report():
    """Print a changelog entry: upstream image changes between the last two syncs.

    docker/versions.md and docker/CHANGELOG.md are owned by upstream and get
    overwritten on every sync, so this only prints; paste it into the commit
    message or PR description.
    """
    state = load_state()
    current, previous = state.get("commit"), state.get("previous_commit")
    if not current or not previous:
        print("Need two recorded syncs to compare; run `apply --safe` first.")
        return

    def images_at(rev: str) -> dict[str, str]:
        found: dict[str, str] = {}
        for name in UPSTREAM_COMPOSE_FILES:
            for service, tracks in compose_images(git("show", f"{rev}:docker/{name}") or "").items():
                for track, image in tracks.items():
                    found[f"{service}{track}"] = image
        return found

    before, after = images_at(previous), images_at(current)
    lines = [f"- {after[k]} (prev {before[k]})" for k in sorted(after) if k in before and before[k] != after[k]]
    lines += [f"- {after[k]} (new)" for k in sorted(after) if k not in before]
    lines += [f"- {before[k]} (removed)" for k in sorted(before) if k not in after]
    if not lines:
        print("No version changes to report.")
        return
    print(f"## {state.get('synced_on', date.today())} (upstream {previous[:10]}..{current[:10]})")
    print("\n".join(lines))


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
                              help="Only apply TIER 1 (image bumps) and docker/ sync")

    subparsers.add_parser("report", help="Summarize image changes from the last sync")

    args = parser.parse_args()

    # Validate upstream exists
    if not UPSTREAM.exists():
        print(f"ERROR: Upstream not found at {UPSTREAM}", file=sys.stderr)
        print("Run: git -C ~/Dev/Workspaces/supabot/supabase pull --ff-only upstream master", file=sys.stderr)
        sys.exit(1)

    if args.command == "detect":
        run_detect(as_json=args.json)
    elif args.command == "apply":
        apply_safe()
    elif args.command == "report":
        generate_report()


if __name__ == "__main__":
    main()
