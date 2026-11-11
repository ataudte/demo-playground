"""Show demo results; retain Ansible's normal failure diagnostics and no_log handling."""

from collections.abc import Mapping
import re
import shutil
import textwrap

from ansible.plugins.callback.default import CallbackModule as DefaultCallback
from ansible.plugins.callback.default import DOCUMENTATION as DEFAULT_DOCUMENTATION


DOCUMENTATION = DEFAULT_DOCUMENTATION.replace("name: default", "name: demo_quiet", 1)


class CallbackModule(DefaultCallback):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "demo_quiet"

    def v2_playbook_on_play_start(self, play):
        # The launcher disables ok/skipped task banners. Keep the play context
        # so inherited failure handlers can still show the failing task.
        self._play = play

    @staticmethod
    def _wrap(value, width, prefix):
        text = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(value))
        return textwrap.wrap(text, width=width, initial_indent=prefix,
                             subsequent_indent=" " * len(prefix),
                             break_on_hyphens=False) or [prefix.rstrip()]

    @classmethod
    def _summary_lines(cls, value, width, indent=2):
        prefix = " " * indent + "- "
        if isinstance(value, Mapping):
            for key, item in value.items():
                if isinstance(item, (Mapping, list)):
                    yield from cls._wrap(f"{key}:" + (" (none)" if not item else ""), width, prefix)
                    if item:
                        yield from cls._summary_lines(item, width, indent + 4)
                else:
                    yield from cls._wrap(f"{key}: {item}", width, prefix)
        elif isinstance(value, list):
            for item in value[:5]:
                yield from cls._summary_lines(item, width, indent)
            if len(value) > 5:
                yield from cls._wrap(f"... (+{len(value) - 5} more)", width, " " * indent)
        else:
            yield from cls._wrap(value, width, prefix)

    def v2_runner_on_ok(self, result):
        self._handle_warnings_and_exception(result)
        # Support both the current callback result API and earlier Ansible cores.
        task = getattr(result, "task", None)
        if task is None:
            task = result._task
        data = getattr(result, "result", None)
        if data is None:
            data = result._result
        if task.no_log or data.get("_ansible_no_log"):
            return
        if task.action not in ("debug", "ansible.builtin.debug", "ansible.legacy.debug"):
            return
        # Only explicit summary messages are shown. Debug variables, including
        # the full step-04 handoff, remain available with VERBOSE = True.
        if "msg" not in data:
            return
        width = max(20, shutil.get_terminal_size((80, 24)).columns - 1)
        for line in self._summary_lines(data["msg"], width):
            self._display.display(line)

    def v2_runner_item_on_ok(self, result):
        self._handle_warnings_and_exception(result)

    def v2_runner_on_skipped(self, result):
        pass

    def v2_runner_item_on_skipped(self, result):
        pass

    def v2_playbook_on_stats(self, stats):
        # The launcher prints OK only after ansible-playbook exits successfully.
        pass
