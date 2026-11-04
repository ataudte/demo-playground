#!/usr/bin/env python3
import ipaddress
import json
from typing import Any, Dict, List, Optional

from solidserver_client import (
    call_service,
    escape_like,
    extract_ip_from_dns_record,
    first_list_item,
    summarize_dhcp_record,
    summarize_dns_record,
    summarize_ip_record,
    summarize_subnet_record,
)


class ToolInputError(ValueError):
    pass


class BackendLookupError(RuntimeError):
    pass


def text_result(obj: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(obj, indent=2, ensure_ascii=False),
            }
        ]
    }


def build_result(
    tool: str,
    input_args: Dict[str, Any],
    title: str,
    primary_finding: str,
    *,
    status: str = "ok",
    matches: Optional[List[Dict[str, Any]]] = None,
    warnings: Optional[List[str]] = None,
    ambiguities: Optional[List[Dict[str, str]]] = None,
    advisory: Optional[Dict[str, Any]] = None,
    raw: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    payload = {
        "status": status,
        "query": {"tool": tool, "input": input_args},
        "summary": {
            "title": title,
            "primary_finding": primary_finding,
        },
        "matches": matches or [],
        "warnings": warnings or [],
        "ambiguities": ambiguities or [],
    }
    if advisory:
        payload["advisory"] = advisory
    if raw is not None:
        payload["raw"] = raw
    return text_result(payload)


TOOLS: List[Dict[str, Any]] = [
    {
        "name": "lookup_host_identity",
        "description": "Look up a host by DNS name and correlate related DNS, IPAM, and DHCP information where available. Use this when the user asks what a hostname is, what IP it has, or whether it exists in DDI.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "investigate_ip",
        "description": "Investigate an IP address across IPAM, subnet, DNS, and DHCP context where available.",
        "inputSchema": {
            "type": "object",
            "properties": {"ip": {"type": "string"}},
            "required": ["ip"],
            "additionalProperties": False,
        },
    },
    {
        "name": "summarize_subnet",
        "description": "Summarize a subnet by CIDR including subnet metadata and any available context.",
        "inputSchema": {
            "type": "object",
            "properties": {"cidr": {"type": "string"}},
            "required": ["cidr"],
            "additionalProperties": False,
        },
    },
    {
        "name": "find_candidate_free_ip",
        "description": "Find the next candidate free IP address in a subnet. Advisory only. This does not reserve or lock the address.",
        "inputSchema": {
            "type": "object",
            "properties": {"cidr": {"type": "string"}},
            "required": ["cidr"],
            "additionalProperties": False,
        },
    },
    {
        "name": "find_dns_records",
        "description": "Find DNS records by hostname, FQDN, or IP-like value and return grouped record context.",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "name": "lookup_dhcp_binding",
        "description": "Look up a DHCP lease or static reservation by IP, MAC, or hostname-like value.",
        "inputSchema": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "name": "get_system_summary",
        "description": "Get a compact read-only summary of available IPAM inventory counts and sample site coverage.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
]


def get_resource_templates() -> List[Dict[str, Any]]:
    return [
        {
            "uri": "solidserver://about",
            "name": "About this MCP",
            "description": "What this read-only SOLIDserver MCP demo is for.",
            "mimeType": "application/json",
        },
        {
            "uri": "solidserver://safety",
            "name": "Safety semantics",
            "description": "Read-only guardrails and advisory semantics for this server.",
            "mimeType": "application/json",
        },
        {
            "uri": "solidserver://capabilities",
            "name": "Capabilities",
            "description": "Advertised tools and resource model for this demo.",
            "mimeType": "application/json",
        },
        {
            "uri": "solidserver://tool-guide",
            "name": "Tool guide",
            "description": "When to use each tool exposed by this MCP server.",
            "mimeType": "application/json",
        },
    ]


PROMPTS: List[Dict[str, Any]] = [
    {
        "name": "investigate-host",
        "description": "Guide an assistant to investigate a hostname using DNS, IPAM, and DHCP context.",
        "arguments": [{"name": "name", "required": True}],
    },
    {
        "name": "investigate-ip",
        "description": "Guide an assistant to investigate an IP across IPAM, subnet, DNS, and DHCP context.",
        "arguments": [{"name": "ip", "required": True}],
    },
]


def get_prompt(name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    if name == "investigate-host":
        host = arguments.get("name", "")
        text = (
            f"Investigate host '{host}'. First use lookup_host_identity. "
            f"If the result is ambiguous, inspect related DNS and DHCP evidence and state the ambiguity clearly. "
            f"Summarize what the host appears to be, what IPs it has, and any caveats."
        )
    elif name == "investigate-ip":
        ip = arguments.get("ip", "")
        text = (
            f"Investigate IP '{ip}'. Use investigate_ip first. "
            f"Summarize the likely owner or purpose of the address, related subnet context, DNS evidence, "
            f"and DHCP evidence. Highlight missing or ambiguous data explicitly."
        )
    else:
        raise ToolInputError(f"Unknown prompt: {name}")

    return {
        "description": name,
        "messages": [
            {
                "role": "user",
                "content": {
                    "type": "text",
                    "text": text,
                },
            }
        ],
    }


_RESOURCE_PAYLOADS: Dict[str, Dict[str, Any]] = {
    "solidserver://about": {
        "name": "solidserver-readonly-mcp",
        "purpose": "Minimal working v2 MCP demo for read-only SOLIDserver exploration.",
        "focus": [
            "task-oriented DDI lookups",
            "consistent result schema",
            "read-only guardrails",
            "resources and prompts in addition to tools",
        ],
    },
    "solidserver://safety": {
        "read_only": True,
        "writes_supported": False,
        "reservations_created": False,
        "advisories": [
            "find_candidate_free_ip is advisory only and does not reserve or lock the address",
            "results may become stale immediately after lookup",
            "multiple views, zones, or duplicate records may cause ambiguity",
        ],
    },
    "solidserver://capabilities": {
        "tools": [tool["name"] for tool in TOOLS],
        "resources": [r["uri"] for r in get_resource_templates()],
        "prompts": [p["name"] for p in PROMPTS],
    },
    "solidserver://tool-guide": {
        "lookup_host_identity": "Use for hostname-centric investigations.",
        "investigate_ip": "Use for IP-centric investigations.",
        "summarize_subnet": "Use for CIDR-centric subnet checks.",
        "find_candidate_free_ip": "Use to get an advisory next free address candidate only.",
        "find_dns_records": "Use when the user asks specifically about DNS records.",
        "lookup_dhcp_binding": "Use when the user asks about leases, reservations, MACs, or DHCP mappings.",
        "get_system_summary": "Use for quick inventory counts and sample site coverage.",
    },
}


def read_resource(uri: str) -> Dict[str, Any]:
    if uri not in _RESOURCE_PAYLOADS:
        raise ToolInputError(f"Unknown resource: {uri}")
    return {
        "contents": [
            {
                "uri": uri,
                "mimeType": "application/json",
                "text": json.dumps(_RESOURCE_PAYLOADS[uri], indent=2, ensure_ascii=False),
            }
        ]
    }


# Legacy compatibility wrappers ------------------------------------------------

def _safe_ip(value: str):
    try:
        return ipaddress.ip_address(value)
    except Exception:
        return None


def _safe_network(cidr: str):
    try:
        return ipaddress.ip_network(cidr, strict=False)
    except Exception:
        return None


def _extract_candidate_ips_from_free_row(row: Dict[str, Any]) -> List[str]:
    if not isinstance(row, dict):
        return []

    candidates: List[str] = []
    for key in (
        "hostaddr",
        "free_start_hostaddr",
        "free_end_hostaddr",
        "ip",
        "ip_addr",
        "start_hostaddr",
        "end_hostaddr",
    ):
        value = row.get(key)
        if isinstance(value, str) and "." in value:
            candidates.append(value)
    return candidates


def _filter_free_ips_for_subnet(ip_values: List[str], cidr: str, limit: int) -> List[str]:
    network = _safe_network(cidr)
    deduped: List[str] = []
    seen = set()
    for value in ip_values:
        ip_obj = _safe_ip(value)
        if not ip_obj:
            continue
        if network and ip_obj not in network:
            continue
        if network and ip_obj == network.network_address:
            continue
        if network and hasattr(network, "broadcast_address") and ip_obj == network.broadcast_address:
            continue
        ip_str = str(ip_obj)
        if ip_str not in seen:
            seen.add(ip_str)
            deduped.append(ip_str)
        if len(deduped) >= limit:
            break
    return deduped


def _filter_dhcp_rows_client_side(rows: Any, query: str) -> List[Dict[str, Any]]:
    q = query.strip().lower()
    filtered: List[Dict[str, Any]] = []
    is_ip = _safe_ip(query) is not None
    is_mac = ":" in query and all(part for part in query.split(":"))

    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        haystack = " ".join(
            [
                str(row.get("dhcphost_mac_addr", "")),
                str(row.get("dhcphost_addr", "")),
                str(row.get("db_hostname", "")),
                str(row.get("dhcphost_name", "")),
                str(row.get("dhcphost_domain", "")),
                str(row.get("dhcpscope_name", "")),
                str(row.get("dhcp_name", "")),
            ]
        ).lower()

        if is_mac and row.get("dhcphost_mac_addr", "").lower() == q:
            filtered.append(row)
        elif is_ip and (row.get("dhcphost_addr", "").lower() == q or row.get("db_hostname", "").lower() == q):
            filtered.append(row)
        elif (not is_ip and not is_mac) and q in haystack:
            filtered.append(row)
    return filtered


def _dns_lookup(q_raw: str) -> Dict[str, Any]:
    q = escape_like(q_raw.strip())
    try:
        ipaddress.ip_address(q_raw)
        is_ip_query = True
    except Exception:
        is_ip_query = False

    variants = (
        [
            {"WHERE": f"value1 LIKE '%{q}%'", "limit": 50},
            {"WHERE": f"rr_full_name LIKE '%{q}%'", "limit": 50},
        ]
        if is_ip_query
        else [
            {"WHERE": f"rr_full_name LIKE '%{q}%'", "limit": 50},
            {"WHERE": f"value1 LIKE '%{q}%'", "limit": 50},
        ]
    )
    attempts = []
    for params in variants + [{"limit": 20}]:
        try:
            data = call_service("dns_rr_list", params)
            return {"data": data, "params_used": params, "notes": attempts}
        except Exception as exc:
            attempts.append({"params": params, "error": str(exc)})
    raise BackendLookupError("No DNS query variant worked")


def _ip_lookup(ip: str) -> Dict[str, Any]:
    data = call_service("ip_address_list", {"WHERE": f"hostaddr='{escape_like(ip)}'", "limit": 20})
    return {"data": data}


def _subnet_lookup(cidr: str) -> Dict[str, Any]:
    if "/" not in cidr:
        raise ToolInputError("CIDR required, e.g. 10.0.0.0/24")
    addr, prefix = cidr.split("/", 1)
    addr = escape_like(addr.strip())
    prefix = escape_like(prefix.strip())
    variants = [
        {"WHERE": f"subnet_addr='{addr}' AND subnet_prefix='{prefix}'", "limit": 50},
        {"WHERE": f"subnet_start_hostaddr='{addr}' AND subnet_prefix='{prefix}'", "limit": 50},
        {"WHERE": f"subnet_name LIKE '%{escape_like(cidr)}%'", "limit": 50},
        {"limit": 500},
    ]
    attempts = []
    for params in variants:
        try:
            data = call_service("ip_block_subnet_list", params)
            if isinstance(data, list):
                exact = []
                for row in data:
                    subnet_addr = row.get("subnet_addr") or row.get("subnet_start_hostaddr") or row.get("subnet_start_ip_addr")
                    subnet_prefix = row.get("subnet_prefix")
                    if subnet_addr and subnet_prefix and f"{subnet_addr}/{subnet_prefix}" == cidr:
                        exact.append(row)
                if exact:
                    return {"data": exact, "params_used": params, "notes": attempts}
                if first_list_item(data) and "WHERE" in params:
                    return {"data": data, "params_used": params, "notes": attempts}
        except Exception as exc:
            attempts.append({"params": params, "error": str(exc)})
    raise BackendLookupError("No subnet query variant worked")


def _dhcp_lookup(query: str) -> Dict[str, Any]:
    q = escape_like(query)
    variants = [
        {"service": "dhcp_range_lease_list", "params": {"WHERE": f"ip_address='{q}' OR mac_addr='{q}'", "limit": 100}},
        {"service": "dhcp_range_lease_list", "params": {"WHERE": f"ip_addr='{q}' OR mac_addr='{q}'", "limit": 100}},
        {"service": "dhcp_static_list", "params": {"limit": 200}},
    ]
    attempts = []
    for variant in variants:
        try:
            data = call_service(variant["service"], variant["params"])
            filtered = _filter_dhcp_rows_client_side(data, query)
            if filtered:
                return {
                    "data": filtered,
                    "matched_via": variant["service"],
                    "params_used": variant["params"],
                    "notes": attempts,
                }
            attempts.append({"service": variant["service"], "params": variant["params"], "error": "No client-side match found in returned rows"})
        except Exception as exc:
            attempts.append({"service": variant["service"], "params": variant["params"], "error": str(exc)})
    raise BackendLookupError("No DHCP match found")


def tool_find_dns_records(args: Dict[str, Any]) -> Dict[str, Any]:
    q_raw = args["query"].strip()
    dns = _dns_lookup(q_raw)
    rows = dns.get("data") if isinstance(dns.get("data"), list) else []
    summaries = [summarize_dns_record(r) for r in rows if summarize_dns_record(r)]
    title = "DNS record lookup"
    primary = f"Found {len(summaries)} DNS record(s) for '{q_raw}'."
    ambiguities = []
    if len(summaries) > 1:
        ambiguities.append({"type": "multiple_dns_records", "message": f"{len(summaries)} DNS records matched the query."})
    return build_result(
        "find_dns_records",
        {"query": q_raw},
        title,
        primary,
        matches=[{"type": "dns_record", "confidence": "medium" if len(summaries) > 1 else "high", "data": s} for s in summaries[:10]],
        ambiguities=ambiguities,
        raw=dns,
    )


def tool_investigate_ip(args: Dict[str, Any]) -> Dict[str, Any]:
    ip = args["ip"].strip()
    ip_data = _ip_lookup(ip)
    ip_rows = ip_data.get("data") if isinstance(ip_data.get("data"), list) else []
    ip_summary = summarize_ip_record(first_list_item(ip_rows))

    dns_matches: List[Dict[str, Any]] = []
    dhcp_summary = None
    warnings: List[str] = []
    try:
        dns_payload = json.loads(tool_find_dns_records({"query": ip})["content"][0]["text"])
        dns_matches = dns_payload.get("matches", [])
    except Exception as exc:
        warnings.append(f"DNS correlation failed: {exc}")

    try:
        dhcp = _dhcp_lookup(ip)
        dhcp_summary = summarize_dhcp_record(first_list_item(dhcp.get("data")))
    except Exception:
        pass

    subnet_summary = None
    if ip_summary and ip_summary.get("subnet"):
        try:
            subnet = _subnet_lookup(ip_summary["subnet"])
            subnet_summary = summarize_subnet_record(first_list_item(subnet.get("data")))
        except Exception as exc:
            warnings.append(f"Subnet correlation failed: {exc}")

    matches: List[Dict[str, Any]] = []
    if ip_summary:
        matches.append({"type": "ipam_address", "confidence": "high", "data": ip_summary})
    if subnet_summary:
        matches.append({"type": "subnet", "confidence": "high", "data": subnet_summary})
    matches.extend(dns_matches[:5])
    if dhcp_summary:
        matches.append({"type": "dhcp_binding", "confidence": "medium", "data": dhcp_summary})

    if ip_summary:
        primary = f"IP {ip} appears in IPAM"
        if subnet_summary and subnet_summary.get("subnet"):
            primary += f" within subnet {subnet_summary['subnet']}"
        primary += "."
        status = "ok"
    else:
        primary = f"No IPAM record was found for {ip}."
        status = "not_found"
        warnings.append("No IPAM match found. DNS or DHCP evidence may still be partial.")

    return build_result(
        "investigate_ip",
        {"ip": ip},
        "IP investigation",
        primary,
        status=status,
        matches=matches,
        warnings=warnings,
        raw={"ip": ip_data, "dns_count": len(dns_matches), "has_dhcp": bool(dhcp_summary)},
    )


def tool_summarize_subnet(args: Dict[str, Any]) -> Dict[str, Any]:
    cidr = args["cidr"].strip()
    subnet = _subnet_lookup(cidr)
    rows = subnet.get("data") if isinstance(subnet.get("data"), list) else []
    summaries = [summarize_subnet_record(r) for r in rows if summarize_subnet_record(r)]
    ambiguities = []
    if len(summaries) > 1:
        ambiguities.append({"type": "multiple_subnet_matches", "message": f"{len(summaries)} subnet rows matched {cidr}."})
    status = "ok" if summaries else "not_found"
    primary = f"Found {len(summaries)} subnet match(es) for {cidr}." if summaries else f"No subnet match found for {cidr}."
    return build_result(
        "summarize_subnet",
        {"cidr": cidr},
        "Subnet summary",
        primary,
        status=status,
        matches=[{"type": "subnet", "confidence": "medium" if len(summaries) > 1 else "high", "data": s} for s in summaries[:10]],
        ambiguities=ambiguities,
        raw=subnet,
    )


def tool_find_candidate_free_ip(args: Dict[str, Any]) -> Dict[str, Any]:
    cidr = args["cidr"].strip()
    if "/" not in cidr:
        raise ToolInputError("CIDR required, e.g. 10.0.0.0/24")
    addr, prefix = cidr.split("/", 1)
    variants = [
        {"WHERE": f"subnet_addr='{escape_like(addr.strip())}' AND subnet_prefix='{escape_like(prefix.strip())}'", "limit": 20},
        {"WHERE": f"subnet_start_hostaddr='{escape_like(addr.strip())}' AND subnet_prefix='{escape_like(prefix.strip())}'", "limit": 20},
        {"WHERE": f"subnet_name LIKE '%{escape_like(cidr)}%'", "limit": 20},
        {"limit": 50},
    ]
    attempts = []
    for params in variants:
        try:
            data = call_service("ip_free_address_list", params)
            raw_candidates: List[str] = []
            if isinstance(data, list):
                for row in data:
                    raw_candidates.extend(_extract_candidate_ips_from_free_row(row))
            free_ips = _filter_free_ips_for_subnet(raw_candidates, cidr, 3)
            if free_ips:
                return build_result(
                    "find_candidate_free_ip",
                    {"cidr": cidr},
                    "Candidate free IP lookup",
                    f"Found candidate free IP {free_ips[0]} in {cidr}.",
                    matches=[{"type": "free_ip_candidate", "confidence": "medium", "data": {"subnet": cidr, "ip": ip}} for ip in free_ips],
                    advisory={
                        "read_only": True,
                        "reservation_created": False,
                        "guarantee": "none",
                        "note": "The returned IP was available at lookup time only and may no longer be available.",
                    },
                    raw={"params_used": params, "notes": attempts},
                )
            attempts.append({"params": params, "error": "No usable free IP found in returned rows"})
        except Exception as exc:
            attempts.append({"params": params, "error": str(exc)})
    return build_result(
        "find_candidate_free_ip",
        {"cidr": cidr},
        "Candidate free IP lookup",
        f"No candidate free IP was found for {cidr}.",
        status="not_found",
        warnings=["No usable free IP was found in the returned SOLIDserver rows."],
        advisory={
            "read_only": True,
            "reservation_created": False,
            "guarantee": "none",
            "note": "This operation is advisory only.",
        },
        raw={"notes": attempts},
    )


def tool_lookup_dhcp_binding(args: Dict[str, Any]) -> Dict[str, Any]:
    query = args["query"].strip()
    dhcp = _dhcp_lookup(query)
    rows = dhcp.get("data") if isinstance(dhcp.get("data"), list) else []
    summaries = [summarize_dhcp_record(r) for r in rows if summarize_dhcp_record(r)]
    ambiguities = []
    if len(summaries) > 1:
        ambiguities.append({"type": "multiple_dhcp_matches", "message": f"{len(summaries)} DHCP rows matched the query."})
    return build_result(
        "lookup_dhcp_binding",
        {"query": query},
        "DHCP binding lookup",
        f"Found {len(summaries)} DHCP match(es) for '{query}'." if summaries else f"No DHCP match found for '{query}'.",
        status="ok" if summaries else "not_found",
        matches=[{"type": "dhcp_binding", "confidence": "medium" if len(summaries) > 1 else "high", "data": s} for s in summaries[:10]],
        ambiguities=ambiguities,
        raw=dhcp,
    )


def tool_lookup_host_identity(args: Dict[str, Any]) -> Dict[str, Any]:
    name = args["name"].strip()
    dns = _dns_lookup(name)
    dns_rows = dns.get("data") if isinstance(dns.get("data"), list) else []
    dns_summaries = [summarize_dns_record(r) for r in dns_rows if summarize_dns_record(r)]
    candidate_ips = []
    for row in dns_rows[:10]:
        ip = extract_ip_from_dns_record(row)
        if ip and ip not in candidate_ips:
            candidate_ips.append(ip)

    matches: List[Dict[str, Any]] = [
        {"type": "dns_record", "confidence": "medium" if len(dns_summaries) > 1 else "high", "data": s}
        for s in dns_summaries[:10]
    ]
    warnings: List[str] = []
    ambiguities: List[Dict[str, str]] = []

    ip_summaries = []
    for ip in candidate_ips[:3]:
        try:
            ip_payload = json.loads(tool_investigate_ip({"ip": ip})["content"][0]["text"])
            ip_summaries.append(ip_payload)
            for match in ip_payload.get("matches", []):
                if match.get("type") in {"ipam_address", "subnet", "dhcp_binding"}:
                    matches.append(match)
        except Exception as exc:
            warnings.append(f"IP enrichment failed for {ip}: {exc}")

    if len(dns_summaries) > 1:
        ambiguities.append({"type": "multiple_dns_records", "message": f"{len(dns_summaries)} DNS records matched the hostname."})
    if len(candidate_ips) > 1:
        ambiguities.append({"type": "multiple_related_ips", "message": f"{len(candidate_ips)} candidate IPs were extracted from DNS results."})

    if dns_summaries:
        primary = f"Host '{name}' resolved to {len(candidate_ips)} candidate IP(s) across {len(dns_summaries)} DNS record(s)."
        status = "ok"
    else:
        primary = f"No DNS-based host identity was found for '{name}'."
        status = "not_found"
        warnings.append("Host lookup currently starts from DNS evidence. Non-DNS-only objects may not be discovered.")

    return build_result(
        "lookup_host_identity",
        {"name": name},
        "Host identity lookup",
        primary,
        status=status,
        matches=matches,
        warnings=warnings,
        ambiguities=ambiguities,
        raw={"dns": dns, "candidate_ips": candidate_ips, "enriched_ip_count": len(ip_summaries)},
    )


def tool_get_system_summary(args: Dict[str, Any]) -> Dict[str, Any]:
    sites = call_service("ip_site_list", {"limit": 20})
    subnet_count = call_service("ip_block_subnet_count")
    ip_count = call_service("ip_address_count")

    total_subnets = None
    total_ips = None
    used_ips = None
    free_ips = None
    if isinstance(subnet_count, list) and subnet_count and isinstance(subnet_count[0], dict):
        total_subnets = subnet_count[0].get("total")
    if isinstance(ip_count, list) and ip_count and isinstance(ip_count[0], dict):
        total_ips = ip_count[0].get("total")
        used_ips = ip_count[0].get("count0")
        free_ips = ip_count[0].get("count1")

    matches = [
        {
            "type": "inventory_summary",
            "confidence": "high",
            "data": {
                "sampled_sites": len(sites) if isinstance(sites, list) else None,
                "total_subnets": total_subnets,
                "total_ip_addresses": total_ips,
                "used_ip_addresses": used_ips,
                "free_ip_addresses": free_ips,
            },
        }
    ]
    return build_result(
        "get_system_summary",
        {},
        "System summary",
        "Returned a compact inventory summary for the current SOLIDserver dataset.",
        matches=matches,
        raw={"sites_sample": sites, "subnet_count_raw": subnet_count, "ip_address_count_raw": ip_count},
    )


TOOL_HANDLERS = {
    "lookup_host_identity": tool_lookup_host_identity,
    "investigate_ip": tool_investigate_ip,
    "summarize_subnet": tool_summarize_subnet,
    "find_candidate_free_ip": tool_find_candidate_free_ip,
    "find_dns_records": tool_find_dns_records,
    "lookup_dhcp_binding": tool_lookup_dhcp_binding,
    "get_system_summary": tool_get_system_summary,
}