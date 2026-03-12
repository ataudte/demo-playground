#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

IPV4_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
CIDR_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}\b")
MAC_RE = re.compile(r"\b[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5,7}\b")


class McpStdioClient:
    def __init__(self, server_cmd: list[str], env: Optional[Dict[str, str]] = None) -> None:
        self.server_cmd = server_cmd
        self.env = env or os.environ.copy()
        self.proc: Optional[subprocess.Popen[str]] = None
        self._next_id = 1

    def _short_request(self, req: Dict[str, Any]) -> str:
        method = req.get("method", "?")
        request_id = req.get("id", "?")
        params = req.get("params") or {}
        if method == "tools/call":
            name = params.get("name", "?")
            args = params.get("arguments") or {}
            if args:
                arg_preview = ", ".join(f"{k}={v}" for k, v in args.items())
                return f"id={request_id} {method} {name}({arg_preview})"
            return f"id={request_id} {method} {name}()"
        if method == "resources/read":
            return f"id={request_id} {method} {params.get('uri', '?')}"
        return f"id={request_id} {method}"

    def _short_response(self, msg: Dict[str, Any]) -> str:
        request_id = msg.get("id", "?")
        if "error" in msg:
            error = msg.get("error") or {}
            return f"id={request_id} error {error.get('code')}: {error.get('message')}"
        result = msg.get("result") or {}
        if isinstance(result, dict):
            if "serverInfo" in result:
                info = result.get("serverInfo") or {}
                return f"id={request_id} ok initialize {info.get('name', '?')} {info.get('version', '')}".strip()
            if "tools" in result:
                return f"id={request_id} ok tools={len(result.get('tools') or [])}"
            if "resources" in result:
                return f"id={request_id} ok resources={len(result.get('resources') or [])}"
            if "prompts" in result:
                return f"id={request_id} ok prompts={len(result.get('prompts') or [])}"
            if "contents" in result:
                return f"id={request_id} ok resource-read items={len(result.get('contents') or [])}"
            if "content" in result:
                return f"id={request_id} ok tool-response"
        return f"id={request_id} ok"

    def start(self) -> None:
        server_name = Path(self.server_cmd[-1]).name if self.server_cmd else "server"
        print()
        print(f"[MCP   ] starting {server_name}")
        self.proc = subprocess.Popen(
            self.server_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
            bufsize=1,
            env=self.env,
        )
        init_result = self.call("initialize", {})
        info = init_result.get("serverInfo") or {}
        print(f"[MCP   ] ready: {info.get('name', 'server')} {info.get('version', '')}".strip())

    def stop(self) -> None:
        if not self.proc:
            return
        print("[MCP   ] stopping server")
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=1)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass
        self.proc = None

    def call(self, method: str, params: Dict[str, Any]) -> Dict[str, Any]:
        if not self.proc or not self.proc.stdin or not self.proc.stdout:
            raise RuntimeError("MCP server is not running")
        request_id = self._next_id
        self._next_id += 1
        req = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        req_json = json.dumps(req, ensure_ascii=False)
        print(f"[MCP ->] {self._short_request(req)}")
        self.proc.stdin.write(req_json + "\n")
        self.proc.stdin.flush()

        while True:
            line = self.proc.stdout.readline()
            if line == "":
                raise RuntimeError("MCP server closed the connection")
            line = line.strip()
            if not line:
                continue
            msg = json.loads(line)
            print(f"[MCP <-] {self._short_response(msg)}")
            if msg.get("id") != request_id:
                continue
            if "error" in msg:
                error = msg["error"]
                raise RuntimeError(f"MCP error {error.get('code')}: {error.get('message')}")
            return msg.get("result", {})


def extract_first(pattern: re.Pattern[str], text: str) -> Optional[str]:
    m = pattern.search(text)
    return m.group(0) if m else None


def normalize_text(text: str) -> str:
    return " ".join(text.strip().rstrip("?").split())


def strip_filler(text: str) -> str:
    t = normalize_text(text)
    patterns = [
        r"^\s*what\s+do\s+you\s+know\s+about\s+",
        r"^\s*do\s+you\s+know\s+about\s+",
        r"^\s*do\s+you\s+know\s+",
        r"^\s*can\s+you\s+find\s+",
        r"^\s*can\s+you\s+look\s+up\s+",
        r"^\s*tell\s+me\s+about\s+",
        r"^\s*what\s+about\s+",
        r"^\s*where\s+is\s+",
        r"^\s*show\s+me\s+",
        r"^\s*show\s+",
        r"^\s*lookup\s+",
        r"^\s*look\s+up\s+",
        r"^\s*search\s+for\s+",
        r"^\s*search\s+",
        r"^\s*find\s+dns\s+",
        r"^\s*find\s+dhcp\s+",
        r"^\s*find\s+host\s+",
        r"^\s*find\s+subnet\s+",
        r"^\s*find\s+",
        r"^\s*what\s+is\s+",
        r"^\s*who\s+is\s+",
        r"^\s*the\s+ip\s+address\s+of\s+",
        r"^\s*ip\s+address\s+of\s+",
        r"^\s*free\s+ips\s+in\s+",
        r"^\s*free\s+ips\s+of\s+",
        r"^\s*dhcp\s+reservation\s+for\s+",
        r"^\s*dns\s+",
        r"^\s*dhcp\s+",
    ]
    changed = True
    while changed:
        changed = False
        for pattern in patterns:
            new_t = re.sub(pattern, "", t, flags=re.IGNORECASE)
            if new_t != t:
                t = new_t
                changed = True
    return normalize_text(t)


def route_question(client: McpStdioClient, question: str) -> Dict[str, Any]:
    q = normalize_text(question)
    ql = q.lower()

    if ql in ("tools", "tool list"):
        return client.call("tools/list", {})
    if ql in ("resources", "resource list"):
        return client.call("resources/list", {})
    if ql in ("prompts", "prompt list"):
        return client.call("prompts/list", {})
    if ql.startswith("resource "):
        name = q.split(" ", 1)[1].strip().lower().replace(" ", "-")
        return client.call("resources/read", {"uri": f"solidserver://{name}"})

    if (
        ql in ("overview", "summary", "ipam overview", "give me an overview")
        or "overview" in ql
        or "summary" in ql
    ):
        return client.call("tools/call", {"name": "get_system_summary", "arguments": {}})

    cidr = extract_first(CIDR_RE, q)
    mac = extract_first(MAC_RE, q)
    ip = extract_first(IPV4_RE, q)
    cleaned = strip_filler(q)

    if (("next" in ql and "available" in ql and "ip" in ql and cidr) or ("available" in ql and "ip" in ql and cidr)):
        return client.call("tools/call", {"name": "find_candidate_free_ip", "arguments": {"cidr": cidr}})
    if cidr:
        return client.call("tools/call", {"name": "summarize_subnet", "arguments": {"cidr": cidr}})
    if "dns" in ql or "record" in ql:
        return client.call("tools/call", {"name": "find_dns_records", "arguments": {"query": cleaned}})
    if mac:
        return client.call("tools/call", {"name": "lookup_dhcp_binding", "arguments": {"query": mac}})
    if "dhcp" in ql or "lease" in ql or "reservation" in ql or "static" in ql:
        return client.call("tools/call", {"name": "lookup_dhcp_binding", "arguments": {"query": cleaned}})
    if ip:
        return client.call("tools/call", {"name": "investigate_ip", "arguments": {"ip": ip}})
    return client.call("tools/call", {"name": "lookup_host_identity", "arguments": {"name": cleaned}})


def _print_mapping(mapping: Dict[str, Any], indent: str = "  ") -> None:
    for key, value in mapping.items():
        if value in (None, "", [], {}):
            continue
        print(f"{indent}{key}: {value}")


def print_result(result: Dict[str, Any]) -> None:
    if "tools" in result:
        print("Available tools")
        for tool in result["tools"]:
            print(f"  {tool.get('name')}: {tool.get('description')}")
        return
    if "resources" in result:
        print("Available resources")
        for resource in result["resources"]:
            print(f"  {resource.get('uri')}: {resource.get('description')}")
        return
    if "prompts" in result:
        print("Available prompts")
        for prompt in result["prompts"]:
            print(f"  {prompt.get('name')}: {prompt.get('description')}")
        return
    if "contents" in result:
        contents = result.get("contents") or []
        for item in contents:
            print(item.get("uri", "resource"))
            text = item.get("text")
            if not text:
                continue
            try:
                payload = json.loads(text)
                print(json.dumps(payload, indent=2, ensure_ascii=False))
            except Exception:
                print(text)
        return

    content = result.get("content") or []
    if not content:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    text = content[0].get("text", "")
    try:
        payload = json.loads(text)
    except Exception:
        print(text)
        return

    summary = payload.get("summary", {})
    title = summary.get("title") or payload.get("status") or "Result"
    print(title)
    if summary.get("primary_finding"):
        print(f"  {summary['primary_finding']}")

    for match in payload.get("matches", []):
        mtype = match.get("type", "match")
        print(f"  [{mtype}]")
        data = match.get("data") or {}
        if isinstance(data, dict):
            _print_mapping(data, indent="    ")
        else:
            print(f"    {data}")

    for warning in payload.get("warnings", []):
        print(f"  warning: {warning}")
    for ambiguity in payload.get("ambiguities", []):
        message = ambiguity.get("message") if isinstance(ambiguity, dict) else str(ambiguity)
        print(f"  ambiguity: {message}")
    if payload.get("advisory"):
        note = payload["advisory"].get("note")
        if note:
            print(f"  advisory: {note}")


def interactive_loop(client: McpStdioClient) -> None:
    print()
    print("[ SOLIDserver MCP Prototype ]")
    print()
    print("[ Try things like: ]")
    print("  Where is laptop39396")
    print("  Do you know laptop39396")
    print("  What do you know about 10.0.0.3")
    print("  Show subnet 10.0.0.0/24")
    print("  Next available IP of 10.0.0.0/24")
    print("  Find DNS laptop39396")
    print("  Find DHCP 01:02:00:5e:00:00:0a")
    print("  Give me an overview")
    print("  tools")
    print("  resources")
    print("  resource about")
    print("  resource safety")
    print("  prompts")
    print("  exit")
    print()

    while True:
        try:
            question = input("> ").strip()
        except (KeyboardInterrupt, EOFError):
            print()
            break
        if not question:
            continue
        if question.lower().strip() in ("exit", "quit", "q"):
            break
        try:
            result = route_question(client, question)
            print_result(result)
        except Exception as exc:
            print(f"Error: {exc}")


def main() -> None:
    missing = [name for name in ("SOLIDSERVER_URL", "SOLIDSERVER_USER", "SOLIDSERVER_PASSWORD") if not os.environ.get(name)]
    if missing:
        print("Missing environment variables: " + ", ".join(missing), file=sys.stderr)
        sys.exit(1)

    script_dir = Path(__file__).resolve().parent
    server_path = script_dir / "solidserver_mcp.py"
    client = McpStdioClient([sys.executable, str(server_path)])
    try:
        client.start()
        interactive_loop(client)
    finally:
        client.stop()


if __name__ == "__main__":
    main()
