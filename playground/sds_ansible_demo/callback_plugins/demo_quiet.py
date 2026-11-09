"""Show demo results; retain Ansible's normal failure diagnostics and no_log handling."""

import json

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
    def _compact(value):
        if isinstance(value, list):
            preview = json.dumps(value[:5], ensure_ascii=False)
            return preview + (f" (+{len(value) - 5} more)" if len(value) > 5 else "")
        if isinstance(value, dict):
            return json.dumps(value, ensure_ascii=False)
        return str(value)

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
        message = data["msg"]
        if isinstance(message, dict):
            for key, value in message.items():
                self._display.display(f"  {key}: {self._compact(value)}")
        else:
            self._display.display(f"  {self._compact(message)}")

    def v2_runner_item_on_ok(self, result):
        self._handle_warnings_and_exception(result)

    def v2_runner_on_skipped(self, result):
        pass

    def v2_runner_item_on_skipped(self, result):
        pass

    def v2_playbook_on_stats(self, stats):
        # The launcher prints OK only after ansible-playbook exits successfully.
        pass
