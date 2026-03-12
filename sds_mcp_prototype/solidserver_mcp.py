#!/usr/bin/env python3
import json
import sys
from typing import Any, Dict

from solidserver_tools import (
    PROMPTS,
    TOOLS,
    TOOL_HANDLERS,
    ToolInputError,
    get_prompt,
    get_resource_templates,
    read_resource,
)

SERVER_INFO = {
    "name": "solidserver-readonly-mcp",
    "version": "2.0.0",
}


def log(msg: str) -> None:
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def send(msg: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def send_result(msg_id: Any, result: Dict[str, Any]) -> None:
    send({"jsonrpc": "2.0", "id": msg_id, "result": result})


def send_error(msg_id: Any, code: int, message: str) -> None:
    send({"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}})


def handle_request(req: Dict[str, Any]) -> None:
    msg_id = req.get("id")
    method = req.get("method")
    params = req.get("params", {}) or {}

    if method == "initialize":
        send_result(
            msg_id,
            {
                "protocolVersion": "2025-06-18",
                "serverInfo": SERVER_INFO,
                "capabilities": {
                    "tools": {},
                    "resources": {},
                    "prompts": {},
                },
            },
        )
        return

    if method == "tools/list":
        send_result(msg_id, {"tools": TOOLS})
        return

    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments", {})
        if name not in TOOL_HANDLERS:
            raise ToolInputError(f"Unknown tool: {name}")
        send_result(msg_id, TOOL_HANDLERS[name](arguments))
        return

    if method == "resources/list":
        send_result(msg_id, {"resources": get_resource_templates()})
        return

    if method == "resources/read":
        uri = params.get("uri")
        if not uri:
            raise ToolInputError("resources/read requires 'uri'")
        send_result(msg_id, read_resource(uri))
        return

    if method == "prompts/list":
        send_result(msg_id, {"prompts": PROMPTS})
        return

    if method == "prompts/get":
        name = params.get("name")
        if not name:
            raise ToolInputError("prompts/get requires 'name'")
        arguments = params.get("arguments", {}) or {}
        send_result(msg_id, get_prompt(name, arguments))
        return

    send_error(msg_id, -32601, f"Method not found: {method}")


def main() -> None:
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except json.JSONDecodeError as exc:
                log(f"Ignoring invalid JSON input: {exc}")
                continue
            try:
                handle_request(req)
            except ToolInputError as exc:
                send_error(req.get("id"), -32602, str(exc))
            except Exception as exc:
                log(f"Unhandled server error: {exc}")
                send_error(req.get("id"), -32000, str(exc))
    except KeyboardInterrupt:
        log("Server interrupted")


if __name__ == "__main__":
    main()
