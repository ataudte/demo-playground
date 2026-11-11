"""Send task metadata to the optional companion; leave console output alone."""

import importlib.util
import os
from pathlib import Path

from ansible.plugins.callback import CallbackBase


DOCUMENTATION = r'''
name: demo_events
type: aggregate
short_description: Task events for the SOLIDserver demo companion
description:
  - Writes local integration task metadata without arguments or result data.
requirements:
  - Enabled by the sds_ansible_demo launcher.
'''

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("_sds_demo_watch", ROOT / "demo_watch.py")
PRESENTATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRESENTATION)


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "demo_events"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        run_id = os.environ.get("SDS_DEMO_RUN_ID")
        self._managed = bool(run_id)
        self._writer = PRESENTATION.EventWriter(ROOT, run_id)
        self._warned = False

    def _emit(self, event, **fields):
        if not self._writer.write(event, **fields) and not self._warned:
            self._display.warning("The companion view cannot write its local task events. The playbook will continue.")
            self._warned = True

    def _task(self, task):
        source, _, line = task.get_path().rpartition(":")
        try:
            relative = Path(source).resolve().relative_to(ROOT)
            if relative.parts[0] != "examples" or relative.suffix not in (".yml", ".yaml"):
                return None
            line = int(line)
        except (ValueError, IndexError):
            return None
        name = task.get_name().strip()
        action = task.action
        if action.startswith("community.efficientip.") or name.startswith("[SOLIDserver collection]"):
            kind = "collection"
        elif action in ("uri", "ansible.builtin.uri", "ansible.legacy.uri"):
            kind = "rest"
        else:
            return None
        return {"task_id": str(task._uuid), "name": name[:200], "kind": kind,
                "action": action, "file": relative.as_posix(), "line": line}

    def _result(self, result, status):
        task = getattr(result, "task", None)
        if task is None:
            task = result._task
        metadata = self._task(task)
        if metadata:
            self._emit("task", status=status, **metadata)
        elif status in ("failed", "unreachable"):
            self._emit("check_failed")

    def v2_playbook_on_start(self, playbook):
        if not self._managed:
            filename = Path(playbook._file_name).name
            self._emit("run_start", step=filename[:2], title=filename)

    def v2_playbook_on_play_start(self, play):
        self._emit("play", title=play.get_name().strip()[:200])

    def v2_playbook_on_task_start(self, task, is_conditional):
        metadata = self._task(task)
        if metadata:
            self._emit("task", status="running", **metadata)

    def v2_runner_on_ok(self, result):
        data = getattr(result, "result", None)
        if data is None:
            data = result._result
        self._result(result, "changed" if data.get("changed") else "ok")

    def v2_runner_on_skipped(self, result):
        self._result(result, "skipped")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._result(result, "failed")

    def v2_runner_on_unreachable(self, result):
        self._result(result, "unreachable")

    def v2_playbook_on_stats(self, stats):
        if not self._managed:
            failed = any(stats.summarize(host)["failures"] or stats.summarize(host)["unreachable"]
                         for host in stats.processed)
            self._emit("run_end", status="failed" if failed else "complete")
