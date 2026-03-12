# SOLIDserver Read-only MCP Demo

## Description
This package contains a small read-only SOLIDserver demo built around the Model Context Protocol (MCP).

It includes:
- an MCP server that exposes tools, resources, and prompts over stdio JSON-RPC
- a Python example client that starts the MCP server as a subprocess and calls it interactively
- a SOLIDserver API client wrapper for HTTP communication
- a DDI-oriented tool layer that maps SOLIDserver API calls into higher-level read-only investigation workflows
- two shell entrypoints for interactive use

The overall goal is to demonstrate how a DDI backend can be exposed through MCP in a safer, more task-oriented way than a raw API wrapper alone.

---

## Architecture Overview
- `solidserver_client.py`
  - Low-level SOLIDserver HTTP client
  - Handles authentication, TLS mode, requests, and basic response parsing
- `solidserver_tools.py`
  - Read-only DDI logic layer
  - Implements task-oriented lookups such as host, IP, subnet, DNS, DHCP, and overview queries
  - Also defines MCP resources and prompts
- `solidserver_mcp.py`
  - MCP stdio server
  - Exposes `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, and `prompts/get`
- `ask_solidserver.py`
  - Example MCP client
  - Starts `solidserver_mcp.py` as a subprocess and talks to it over JSON-RPC via stdio
  - Accepts natural-language style test prompts and renders responses for a human user
- `ask-solidserver.sh`
  - Interactive shell launcher for the example MCP client
- `run-solidserver-mcp.sh`
  - Interactive shell launcher for the raw MCP server
  - Accepts pasted JSON-RPC requests and prints JSON-RPC responses

---

## Usage

### 1. Run the example MCP client
This is the easiest way to use the demo interactively.

```bash
./ask-solidserver.sh
```

Example prompts:
```text
Do you know laptop39396?
What do you know about 10.0.0.3
Show subnet 10.0.0.0/24
Next available IP of 10.0.0.0/24
Find DNS laptop39396
Find DHCP 01:02:00:5e:00:00:0a
Give me an overview
tools
resources
resource about
resource safety
prompts
exit
```

### 2. Run the raw MCP server session
Use this if you want to test JSON-RPC requests directly.

```bash
./run-solidserver-mcp.sh
```

Example JSON-RPC requests:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lookup_host_identity","arguments":{"name":"laptop39396"}}}
```

Type `exit` or `quit` to close the raw MCP session.

### 3. Run the Python entrypoints directly

```bash
python3 solidserver_mcp.py
python3 ask_solidserver.py
```

Both approaches require valid SOLIDserver environment variables.

---

## Requirements
- Python 3.10+
- zsh for the provided shell launchers
- External Python modules:
  - `requests`
- Vendor-specific dependency:
  - EfficientIP SOLIDserver REST API

The scripts expect the following environment variables:
- `SOLIDSERVER_URL`
- `SOLIDSERVER_USER`
- `SOLIDSERVER_PASSWORD`
- `SOLIDSERVER_INSECURE_TLS`

The shell launchers prompt for host, username, and password if these are not already set.

---

## Script Details

### `ask_solidserver.py`

## Description
Interactive example MCP client for this demo.

It starts `solidserver_mcp.py` as a subprocess, sends JSON-RPC requests over stdio, prints compact MCP request and response traces, and converts natural-language style prompts into MCP tool calls.

## Usage
```bash
python3 ask_solidserver.py
```

Usually launched through:
```bash
./ask-solidserver.sh
```

## Requirements
- Python 3.10+
- Access to `solidserver_mcp.py` in the same directory
- Valid `SOLIDSERVER_*` environment variables

## Input / Output
- **Input:** Interactive terminal commands or natural-language style prompts
- **Output:** Human-readable summaries of MCP tool results, plus short MCP client/server interaction traces

## Notes
- This is an example client, not a full generic MCP client
- It uses stdio transport and starts its own MCP server subprocess for the session
- It is intended for demo and validation purposes rather than production use

---

### `solidserver_client.py`

## Description
Low-level SOLIDserver API client wrapper.

It is responsible for HTTP requests, authentication, TLS handling, request logging to stderr, and returning parsed API responses to higher layers.

## Usage
Used as a library by `solidserver_tools.py`.

```bash
python3 -c "from solidserver_client import SolidServerClient; print(SolidServerClient().base_url)"
```

## Requirements
- Python 3.10+
- `requests`
- Access to the SOLIDserver REST API

## Input / Output
- **Input:** Method calls from the tool layer plus SOLIDserver credentials from environment variables
- **Output:** Parsed Python dictionaries and lists from SOLIDserver API responses

## Notes
- This is the wrapper layer, not the MCP layer
- It should stay transport-focused and not contain MCP protocol logic
- Logging goes to stderr to avoid corrupting stdio protocol output in the MCP server

---

### `solidserver_mcp.py`

## Description
Read-only MCP stdio server for SOLIDserver.

It exposes tools, resources, and prompts using JSON-RPC over stdin and stdout.

## Usage
```bash
python3 solidserver_mcp.py
```

Usually launched through:
```bash
./run-solidserver-mcp.sh
```

## Requirements
- Python 3.10+
- `solidserver_tools.py`
- Valid `SOLIDSERVER_*` environment variables

## Input / Output
- **Input:** JSON-RPC requests on stdin
- **Output:** JSON-RPC responses on stdout

Supported methods:
- `initialize`
- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `prompts/list`
- `prompts/get`

## Notes
- Stdout is reserved for protocol output only
- Errors and diagnostics should go to stderr
- This server is read-only by design

---

### `solidserver_tools.py`

## Description
Read-only DDI tool and resource layer for the demo.

It provides higher-level functions that correlate SOLIDserver data across DNS, IPAM, subnet, and DHCP contexts and returns MCP-friendly result envelopes.

## Usage
Used as a library by `solidserver_mcp.py`.

Exposed tool names include:
- `lookup_host_identity`
- `investigate_ip`
- `summarize_subnet`
- `find_candidate_free_ip`
- `find_dns_records`
- `lookup_dhcp_binding`
- `get_system_summary`

## Requirements
- Python 3.10+
- `solidserver_client.py`
- Access to SOLIDserver data via API

## Input / Output
- **Input:** Tool arguments such as hostname, IP, MAC address, CIDR, or DNS query
- **Output:** Structured dictionaries with fields such as:
  - `status`
  - `summary`
  - `matches`
  - `warnings`
  - `ambiguities`

It also provides MCP resources and prompts.

## Notes
- This is the domain logic layer between raw API access and the MCP server
- The implementation is read-only and intended for lookup and investigation use cases
- Some legacy compatibility wrappers are still present to preserve older command styles

---

### `ask-solidserver.sh`

## Description
Convenience shell launcher for the example MCP client.

It prompts for SOLIDserver host, username, and password when needed, exports the required environment variables, and starts `ask_solidserver.py`.

## Usage
```bash
./ask-solidserver.sh
```

## Requirements
- zsh
- Python 3 available via `/usr/bin/env python3`

## Input / Output
- **Input:** Interactive credential prompts and user questions
- **Output:** Launches the Python MCP client and displays formatted results in the terminal

## Notes
- Sets `SOLIDSERVER_INSECURE_TLS=true` by default
- Credentials are only prompted if `SOLIDSERVER_URL` is not already set in the environment

---

### `run-solidserver-mcp.sh`

## Description
Convenience shell launcher for a raw interactive MCP server session.

It prompts for SOLIDserver credentials when needed, prints example JSON-RPC requests, starts `solidserver_mcp.py`, and lets you paste one JSON-RPC request per line. It also supports `exit` and `quit` to close the session.

## Usage
```bash
./run-solidserver-mcp.sh
```

## Requirements
- zsh
- Python 3 available via `/usr/bin/env python3`

## Input / Output
- **Input:** Interactive credential prompts plus one-line JSON-RPC requests
- **Output:** One-line JSON-RPC responses from the MCP server

## Notes
- Sets `SOLIDSERVER_INSECURE_TLS=true` by default
- Uses FIFOs to connect the shell wrapper to the stdio MCP server process
- Intended for manual protocol testing, not for production deployment

---

## Input / Output Summary
- **Input:**
  - SOLIDserver credentials through environment variables or shell prompts
  - natural-language style interactive questions in `ask_solidserver.py`
  - JSON-RPC requests in `run-solidserver-mcp.sh`
- **Output:**
  - formatted CLI investigation results from the example client
  - JSON-RPC responses from the MCP server
  - read-only DDI summaries, lookup results, warnings, and ambiguities

---

## Notes
- This demo is intentionally read-only
- `find_candidate_free_ip` is advisory only and does not reserve or lock an address
- Results can become stale immediately after lookup in a live DDI environment
- Multiple views, zones, duplicate records, or overlapping data can produce ambiguity
- `SOLIDSERVER_INSECURE_TLS=true` is convenient for a lab demo but should be reconsidered for customer-facing or production-like usage

---

## License
This README describes the scripts in the current demo package. License handling should follow the repository or package license used for the rest of the project.
