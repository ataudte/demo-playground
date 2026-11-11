"""Local task events and a terminal companion for the SOLIDserver demo."""

from collections import deque
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time
import uuid


COLLECTION = "\033[1;36m"
BANNER = "\033[1;97;44m"
MUTED = "\033[90m"
FAILED = "\033[1;31m"
RESET = "\033[0m"
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
NAMESPACE = re.compile(r"community\.efficientip\.[a-zA-Z0-9_]+")
PRIVATE = re.compile(r"\b(?:password|url_password|username|url_username|authorization|token|secret)\b", re.I)
EVENT_FIELDS = {"step", "title", "file", "task_id", "name", "kind", "action", "line", "status"}


def event_path(root):
    return Path(root) / ".ansible" / "demo-events.jsonl"


class EventWriter:
    """Append metadata only; never pass task arguments or results to write()."""

    def __init__(self, root, run_id=None):
        self.path = event_path(root)
        self.run_id = run_id or uuid.uuid4().hex

    def write(self, event, **fields):
        metadata = {key: value for key, value in fields.items() if key in EVENT_FIELDS}
        record = {"version": 1, "run_id": self.run_id, "time": time.time(), "event": event, **metadata}
        data = (json.dumps(record, ensure_ascii=True) + "\n").encode()
        try:
            self.path.parent.mkdir(exist_ok=True)
            if event == "run_start":
                descriptor, temporary = tempfile.mkstemp(prefix=".demo-events-", dir=self.path.parent)
                try:
                    with os.fdopen(descriptor, "wb") as handle:
                        handle.write(data)
                    os.replace(temporary, self.path)
                finally:
                    Path(temporary).unlink(missing_ok=True)
                return True
            descriptor = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
            try:
                os.fchmod(descriptor, 0o600)
                os.write(descriptor, data)
            finally:
                os.close(descriptor)
        except OSError:
            return False
        return True


def clean(text):
    return CONTROL.sub("", str(text).replace("\t", "    "))


def source_task(root, event):
    """Read the source template, never evaluated Ansible arguments/configuration."""
    try:
        folder = (Path(root) / "examples").resolve()
        path = (Path(root) / event["file"]).resolve()
        path.relative_to(folder)
        if path.suffix not in (".yml", ".yaml"):
            return []
        lines = path.read_text().splitlines()
        start = max(0, int(event["line"]) - 1)
        first = lines[start]
        indentation = len(first) - len(first.lstrip())
        rows = []
        hidden_indent = None
        for index in range(start, min(len(lines), start + 100)):
            line = lines[index]
            stripped = line.strip()
            indent = len(line) - len(line.lstrip())
            if index > start and stripped and not stripped.startswith("#") and indent <= indentation:
                break
            if hidden_indent is not None and indent > hidden_indent:
                continue
            hidden_indent = None
            if PRIVATE.search(line) or re.search(r"https?://[^\s/@]+:[^\s/@]+@", line):
                line = " " * indent + "# credentials omitted"
                hidden_indent = indent
            if stripped:
                rows.append((index + 1, clean(line)))
        return rows
    except (OSError, ValueError, KeyError, IndexError):
        return []


def component(root, event):
    if event.get("kind") == "collection":
        action = event.get("action", "")
        if action.startswith("community.efficientip."):
            return action
        for _, line in source_task(root, event):
            match = NAMESPACE.search(line)
            if match:
                return match.group()
        return "community.efficientip lookup"
    return "ansible.builtin.uri"


class ViewState:
    def __init__(self):
        self.run_id = None
        self.title = "Waiting for a playbook"
        self.step = ""
        self.status = "waiting"
        self.current = None
        self.collection = None
        self.rest = None
        self.executed = {"collection": None, "rest": None}
        self.history = deque(maxlen=5)

    def apply(self, event):
        if event.get("version") != 1:
            return False
        kind = event.get("event")
        if kind == "run_start":
            self.__init__()
            self.run_id = event.get("run_id")
            self.title = clean(event.get("title", "Playbook"))
            self.step = clean(event.get("step", ""))
            self.status = "running"
        elif event.get("run_id") != self.run_id:
            return False
        elif kind == "play":
            self.title = clean(event.get("title", self.title))
        elif kind == "task" and event.get("kind") in ("collection", "rest"):
            self.current = event
            display = event
            if event.get("status") == "skipped":
                display = self.executed[event["kind"]] or event
            elif event.get("status") != "running":
                self.executed[event["kind"]] = event
            setattr(self, event["kind"], display)
            if event.get("status") != "running":
                self.history.append(event)
        elif kind == "check_failed":
            self.status = "failed"
        elif kind == "run_end":
            self.status = clean(event.get("status", "complete"))
            if self.current and self.current.get("status") == "running":
                self.current = dict(self.current, status=self.status)
                setattr(self, self.current["kind"], self.current)
        else:
            return False
        return True


def status_label(event):
    status = event.get("status", "")
    return "SKIPPED (no operation)" if status == "skipped" else status.upper()


def render(state, root, width=110, height=36, color=True):
    rows = []

    def add(text="", style=""):
        text = clean(text)[:max(1, width - 1)]
        rows.append((style + text + RESET) if color and style else text)

    add("SOLIDserver + Ansible | live integration view", BANNER)
    add(f"{state.step + ' - ' if state.step else ''}{state.title}")
    overall = state.status.upper()
    add(f"Playbook: {overall}", FAILED if state.status in ("failed", "interrupted") else "")
    if state.current:
        current = state.current
        label = "COLLECTION" if current["kind"] == "collection" else "REST"
        add(f"Latest activity: {label} | {status_label(current)}",
            COLLECTION if current["kind"] == "collection" else MUTED)
    else:
        add("Run ./sds_ansible_demo in the other terminal.", MUTED)
    add()

    event = state.collection
    active = event is not None and event.get("status") == "running" and state.status == "running"
    add(" EFFICIENTIP ANSIBLE COLLECTION " + (" | RUNNING " if active else " | latest task "),
        BANNER if active else COLLECTION)
    if event:
        style = (MUTED if event.get("status") == "skipped" else
                 FAILED if event.get("status") in ("failed", "unreachable", "interrupted") else COLLECTION)
        add(f"{component(root, event)} | {status_label(event)}", style)
        add(event.get("name", ""))
        add(f"{event.get('file', '')}:{event.get('line', '')}", MUTED)
        source = source_task(root, event)
        limit = max(2, min(12, height - 23))
        for line_number, text in source[:limit]:
            add(f"{line_number:>4}  {text}", COLLECTION if NAMESPACE.search(text) else "")
        if len(source) > limit:
            add("      ...", MUTED)
    else:
        add("Waiting for a collection module or lookup.", MUTED)
    add()

    add("REST API | latest task", MUTED)
    event = state.rest
    if event:
        add(f"ansible.builtin.uri | {status_label(event)}", MUTED)
        add(event.get("name", ""), MUTED)
        add(f"{event.get('file', '')}:{event.get('line', '')}", MUTED)
    else:
        add("No direct REST task in this playbook yet.", MUTED)
    add()
    add("Recent completed tasks", MUTED)
    for item in list(state.history)[-3:]:
        label = "COLLECTION" if item["kind"] == "collection" else "rest"
        name = re.sub(r"^\[SOLIDserver (?:collection|REST)\]\s*", "", item.get("name", ""))
        add(f"  {label} | {status_label(item)} | {name}",
            COLLECTION if item["kind"] == "collection" and item.get("status") != "skipped" else MUTED)
    add()
    add("Live task events | source templates only | Ctrl-C closes this view", MUTED)
    if len(rows) > height:
        rows = rows[:max(1, height - 1)] + rows[-1:]
    return "\n".join(rows)


def follow(path):
    """Tail complete JSON lines, including truncation/replacement between runs."""
    handle = None
    identity = None
    try:
        while True:
            try:
                stat = path.stat()
                new_identity = (stat.st_dev, stat.st_ino)
                if handle is None or identity != new_identity or stat.st_size < handle.tell():
                    if handle is not None:
                        handle.close()
                    handle = path.open()
                    identity = new_identity
                position = handle.tell()
                line = handle.readline()
                if line.endswith("\n"):
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(event, dict):
                        yield event
                    continue
                handle.seek(position)
            except FileNotFoundError:
                if handle is not None:
                    handle.close()
                    handle = None
                    identity = None
            yield None
            time.sleep(0.1)
    finally:
        if handle is not None:
            handle.close()


def watch(root):
    root = Path(root)
    state = ViewState()
    terminal = sys.stdout.isatty() and os.environ.get("TERM") != "dumb"
    color = terminal and "NO_COLOR" not in os.environ
    size = None
    dirty = True
    last_frame = None
    if terminal:
        sys.stdout.write("\033[?1049h\033[?25l")
    else:
        print("Waiting for playbook task events. Ctrl-C closes this view.", flush=True)
    try:
        for event in follow(event_path(root)):
            if event is not None:
                dirty = state.apply(event) or dirty
            current_size = shutil.get_terminal_size((110, 36))
            if terminal and (dirty or current_size != size):
                frame = render(state, root, current_size.columns, current_size.lines, color)
                if frame != last_frame:
                    sys.stdout.write("\033[H\033[2J" + frame)
                    sys.stdout.flush()
                    last_frame = frame
                size = current_size
            elif not terminal and event is not None and dirty:
                timestamp = datetime.fromtimestamp(event.get("time", time.time())).strftime("%H:%M:%S")
                if event.get("event") == "task":
                    label = "COLLECTION" if event.get("kind") == "collection" else "rest"
                    print(f"{timestamp} {label} | {status_label(event)} | {component(root, event)} | {clean(event.get('name', ''))}", flush=True)
                elif event.get("event") in ("run_start", "run_end"):
                    print(f"{timestamp} {state.title} | {state.status.upper()}", flush=True)
            dirty = False
    finally:
        if terminal:
            sys.stdout.write("\033[0m\033[?25h\033[?1049l")
            sys.stdout.flush()
