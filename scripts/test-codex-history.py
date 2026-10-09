#!/usr/bin/env python3
"""Run against a built app, with scratch state and no terminal sessions."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import uuid


def wait_for(check, description, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.2)
    raise AssertionError(description)


root = Path(tempfile.mkdtemp(prefix="vhostty-history-"))
print(f"Scratch artifacts: {root}", flush=True)
home = root / "codex"
project = root / "project"
support = root / "support"
snapshot = root / "snapshot"
for directory in (home, project, support, snapshot):
    directory.mkdir()

db_path = home / "state_5.sqlite"
with sqlite3.connect(db_path) as db:
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("""CREATE TABLE threads (
        id TEXT PRIMARY KEY, cwd TEXT, name TEXT, title TEXT, git_branch TEXT,
        updated_at INTEGER, rollout_path TEXT, archived INTEGER, source TEXT,
        thread_source TEXT, preview TEXT)""")
    for index in range(2):
        db.execute("INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?, 0, 'cli', 'user', 'prompt')",
                   (str(uuid.uuid4()), str(project), f"Codex fixture {index}", "prompt", "main",
                    int(time.time()) - index, str(root / f"rollout-{index}.jsonl")))
(support / "state.json").write_text(json.dumps({
    "projects": [{"id": str(uuid.uuid4()), "name": "Fixture", "path": str(project), "expanded": True}],
    "tabs": [],
}))

state_path = snapshot / "state.txt"
log_path = root / "app.log"


def state():
    return state_path.read_text() if state_path.exists() else ""


def refresh():
    (snapshot / "input.txt").write_text("refreshhistory\n")
    wait_for(lambda: not (snapshot / "input.txt").exists(), "debug command not consumed")


env = dict(os.environ, CODEX_HOME=str(home), VHOSTTY_SUPPORT_DIR=str(support),
           VHOSTTY_DEBUG_SNAPSHOT=str(snapshot))
with log_path.open("w") as log:
    app = subprocess.Popen(["build/Vhostty.app/Contents/MacOS/Vhostty"], env=env,
                           stdout=log, stderr=subprocess.STDOUT)
    blocker = None
    try:
        wait_for(lambda: all(f"Codex fixture {i}" in state() for i in range(2)),
                 "initial Codex history not loaded")
        print("PASS initial history", flush=True)
        # The last writer checkpoints and removes WAL/SHM files when it closes.
        db.close()
        refresh()
        stamp = state_path.stat().st_mtime_ns
        wait_for(lambda: state_path.stat().st_mtime_ns > stamp, "snapshot not updated")
        assert all(f"Codex fixture {i}" in state() for i in range(2)), "closing last writer erased history"
        assert "unable to open database file" not in log_path.read_text(), "cannot read without WAL sidecars"
        print("PASS history after last writer closes", flush=True)
        blocker = sqlite3.connect(db_path, timeout=2)
        blocker.execute("PRAGMA locking_mode=EXCLUSIVE")
        blocker.execute("BEGIN EXCLUSIVE")
        refresh()
        wait_for(lambda: "database is locked" in log_path.read_text(), "locked read not exercised")
        # Allow the main queue and a subsequent debug snapshot to publish the result.
        stamp = state_path.stat().st_mtime_ns
        wait_for(lambda: state_path.stat().st_mtime_ns > stamp, "snapshot not updated")
        assert all(f"Codex fixture {i}" in state() for i in range(2)), "database lock erased history"
        print("PASS failed read preserves history", flush=True)
        blocker.rollback()
        blocker.close()
        blocker = None
        with sqlite3.connect(db_path) as db:
            db.execute("UPDATE threads SET name = 'Recovered ' || name")
        refresh()
        wait_for(lambda: "Recovered Codex fixture 0" in state(), "history did not recover")
        print("PASS refresh recovers after unlock", flush=True)
        with sqlite3.connect(db_path) as db:
            db.execute("DELETE FROM threads")
        refresh()
        wait_for(lambda: "Codex fixture" not in state(), "successful empty result retained stale history")
        print("PASS successful empty result clears history", flush=True)
    finally:
        db.close()
        if blocker is not None:
            blocker.close()
        app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
