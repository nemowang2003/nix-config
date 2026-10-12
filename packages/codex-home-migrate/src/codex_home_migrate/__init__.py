"""Explicitly migrate an inactive Codex home; check only unless --apply is supplied."""

import argparse
import json
import re
import shutil
import socket
import sqlite3
from contextlib import closing
from pathlib import Path


def require_inactive(home):
    for path in (home / "app-server-control").glob("*.sock"):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(0.2)
            try:
                client.connect(str(path))
            except (ConnectionRefusedError, FileNotFoundError):
                continue
            raise RuntimeError(
                f"Codex home {home} has a running app-server. Close its sessions, then run "
                f"CODEX_HOME={home} <original-codex-binary> app-server daemon stop before switching Home Manager."
            )


def rewrite_paths(value, source, target):
    if isinstance(value, str):
        updated = re.sub(re.escape(str(source)) + r"(?=$|[/\s'\":])", lambda _: str(target), value)
        return updated.replace("./" + source.name + "/", "./" + target.name + "/")
    if isinstance(value, list):
        return [rewrite_paths(item, source, target) for item in value]
    if isinstance(value, dict):
        return {key: rewrite_paths(item, source, target) for key, item in value.items()}
    return value


def rewrite_database(database, source, target, backup_dir):
    with closing(sqlite3.connect(database.as_uri() + "?mode=rw", uri=True)) as connection:
        backup = backup_dir / database.name
        if not backup.exists():
            with closing(sqlite3.connect(backup)) as saved:
                connection.backup(saved)
        with connection:
            tables = connection.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")
            for (table,) in tables.fetchall():
                quoted_table = '"' + table.replace('"', '""') + '"'
                for column in connection.execute(f"PRAGMA table_info({quoted_table})"):
                    name = column[1]
                    if not (name.endswith("_path") or name in {"path", "codex_home"}):
                        continue
                    quoted_column = '"' + name.replace('"', '""') + '"'
                    prefix = str(source) + "/"
                    connection.execute(
                        f"UPDATE {quoted_table} SET {quoted_column} = ? || substr({quoted_column}, ?) "
                        f"WHERE substr({quoted_column}, 1, ?) = ?",
                        (str(target) + "/", len(prefix) + 1, len(prefix), prefix),
                    )


def check_migration(source, target):
    source, target = source.absolute(), target.absolute()
    if source.is_symlink() or target.is_symlink():
        raise RuntimeError("Codex home migration requires real directories, not symlinks")
    if source.exists():
        if target.exists():
            raise RuntimeError(
                f"Both {source} and {target} exist; refusing to merge independent homes"
            )
        require_inactive(source)
    elif (target / ".home-migration.json").exists():
        require_inactive(target)


def migrate(source, target):
    source, target = source.absolute(), target.absolute()
    marker = target / ".home-migration.json"
    check_migration(source, target)
    if source.exists():
        # A marker allows an interrupted migration to resume after the rename.
        (source / marker.name).write_text(json.dumps({"source": str(source)}))
        source.rename(target)
    elif not marker.exists():
        return
    if json.loads(marker.read_text())["source"] != str(source):
        raise RuntimeError("Codex home migration marker belongs to a different source")
    require_inactive(target)
    backup_dir = target / "home-migration-backup"
    backup_dir.mkdir(exist_ok=True, mode=0o700)
    for database in target.glob("*.sqlite"):
        rewrite_database(database, source, target, backup_dir)
    # Update operational metadata only; conversation JSONL/history is unchanged.
    metadata = list(target.glob("*.json"))
    metadata += list((target / "app-server-daemon").glob("*.json"))
    metadata += list((target / "plugins").rglob("*.json"))
    marketplace = target.parent / ".agents/plugins/marketplace.json"
    if marketplace.exists():
        metadata.append(marketplace)
    for path in metadata:
        if path == marker or path.is_symlink():
            continue
        contents = path.read_text()
        updated = rewrite_paths(json.loads(contents), source, target)
        if updated != json.loads(contents):
            relative = (
                path.relative_to(target)
                if path.is_relative_to(target)
                else Path("marketplace.json")
            )
            backup = backup_dir / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                shutil.copy2(path, backup)
            temporary = path.with_name(path.name + ".migrate")
            temporary.write_text(json.dumps(updated))
            shutil.copymode(path, temporary)
            temporary.replace(path)
    operational_text = list(target.glob("*.toml")) + list((target / "shell_snapshots").glob("*.sh"))
    for path in operational_text:
        if path.is_symlink():
            continue
        original = path.read_text()
        updated = rewrite_paths(original, source, target)
        if updated != original:
            backup = backup_dir / path.relative_to(target)
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                shutil.copy2(path, backup)
            path.write_text(updated)
    marker.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--apply",
        action="store_true",
        help="move the explicitly supplied source to target and update paths",
    )
    mode.add_argument("--check", action="store_true", help="validate without writes (default)")
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.apply:
            migrate(args.source, args.target)
        else:
            check_migration(args.source, args.target)
    except (OSError, ValueError, sqlite3.Error, RuntimeError) as error:
        parser.exit(1, f"codex-home-migrate: {error}\n")
    return 0
