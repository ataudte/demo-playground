# demo-playground
Experimental scripts used for live demos, workshops, and presentations. A playground for showcasing ideas, testing concepts, and explaining technical behavior. Not intended for production use.

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

Demo script for generating **look‑alike domain names** (homoglyph / typo‑style variants) based on a legitimate base domain.

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

