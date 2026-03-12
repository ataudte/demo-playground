# demo-playground
Experimental scripts used for live demos, workshops, and presentations. A playground for showcasing ideas, testing concepts, and explaining technical behavior. Not intended for production use.

---

## DNS Security

<details>
  <summary>dns_dga-demo</summary>

* [dns_dga-demo.sh](dns_dga-demo)

Minimal, deterministic **Domain Generation Algorithm (DGA)** demo script. It generates time-based domain names in fixed slots and marks a deterministic subset of them as **REGISTERED**, while the rest resolve to **NXDOMAIN**.  It is intended for demos, testing, and teaching DNS behavior, *not* for real malware simulation.

</details>

<details>
  <summary>dns_ip-serial</summary>

* [dns_ip-serial.sh](dns_ip-serial)

Small utility script to convert between an IPv4 address in dotted-quad notation (e.g. `192.168.1.1`) and its **32-bit integer representation** (often called “serial”, “decimal IP”, or “IPv4 as integer”)

</details>

<details>
  <summary>dns_look-a-like</summary>

* [dns_look-a-like.sh](dns_look-a-like)

Generates **look-a-like (homoglyph) domain variants** and prints their **Punycode** representation.

</details>

<details>
  <summary>dns_n-gram</summary>

* [dns_n-gram.sh](dns_n-gram)

Demo script for **analyzing domain labels using bi-grams and tri-grams** and comparing them against an English dictionary.

</details>

<details>
  <summary>dns_straying</summary>

* [dns_straying.sh](dns_straying)

Interactive demo script that simulates **DNS straying queries** by sending random, non-existent hostnames for a given zone to its authoritative name servers.

</details>

<details>
  <summary>dns_tunnel</summary>

* [dns_tunnel.sh](dns_tunnel)

Bash demo script that simulates **DNS tunneling** by encoding a file into a list of DNS-style hostnames (client mode) and reconstructing the original file from that hostname log (server mode).

</details>

<details>
  <summary>dnscrypt-proxy_ctrl</summary>

* [dnscrypt-proxy_ctrl.sh](dnscrypt-proxy_ctrl)

Small control script to manage a **dnscrypt-proxy** instance that is started with a specific `dnscrypt-proxy.toml` config.

</details>

---

## Lab Environment 

<details>
  <summary>create_vm-from-iso</summary>

* [create_vm-from-iso.sh](create_vm-from-iso)

Creates a VMware vSphere/ESXi virtual machine using `govc`, attaches an ISO image as a virtual CD-ROM, and powers the VM on.

</details>

<details>
  <summary>ms_demo-data</summary>

* [ms_demo-data.ps1](ms_demo-data)

Seeds a Windows Server (2019+) with example **DNS** and **DHCP** data for lab / demo use.

</details>

<details>
  <summary>ms_lab-cleanup</summary>

* [ms_lab-cleanup.ps1](ms_lab-cleanup)

Destructive lab cleanup helper for **Windows Server DNS and DHCP**.

</details>

<details>
  <summary>quad9_dig</summary>

* [quad9_dig.sh](quad9_dig)

Fetches the latest Quad9 top 500 domains JSON file from the `Quad9DNS/quad9-domains-top500` GitHub repository, extracts the domain names, and resolves each domain with `dig` against a chosen DNS server. The script stores the downloaded JSON, extracted domain list, and resolution results in a date-based temporary folder.

</details>

<details>
  <summary>sds_mcp_prototype</summary>

* [ask-solidserver.sh](sds_mcp_prototype)
* [ask_solidserver.py](sds_mcp_prototype)
* [run-solidserver-mcp.sh](sds_mcp_prototype)
* [solidserver_client.py](sds_mcp_prototype)
* [solidserver_mcp.py](sds_mcp_prototype)
* [solidserver_tools.py](sds_mcp_prototype)

This package contains a small read-only SOLIDserver demo built around the Model Context Protocol (MCP).

</details>

---

## Nonsense

<details>
  <summary>gen_phrase</summary>

* [gen_phrase.sh](gen_phrase)

Generates **10 random corporate-buzzword phrases** by combining an adjective, a noun, a verb, and an adverb, then prints them to stdout (one per line).

</details>

<details>
  <summary>no-as-a-service</summary>

* [no-as-a-service.sh](no-as-a-service)

Answers any valid yes/no question with a **firm “No”** and a randomly generated, nonsense justification.

</details>

