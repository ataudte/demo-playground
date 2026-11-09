# sds_ansible_demo

This SOLIDserver and Ansible demo uses the official [EfficientIP Ansible collection](https://gitlab.com/efficientip/efficientip-ansible-collection) and the SOLIDserver REST API to demonstrate an application endpoint lifecycle.

Six numbered playbooks connect to SOLIDserver, inspect IPAM, create a network and host with DNS, create an application alias, verify the resources and clean up. All examples are in [examples/](examples/). Integration tasks are labelled `[SOLIDserver collection]` or `[SOLIDserver REST]`.

## Requirements and scope

- An Ansible control machine with Python 3, `venv`, `pip` and Git. Use a Python version supported by your chosen `ansible-core` release; see the [Ansible installation guide](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html).
- An active Python virtual environment with Ansible installed, as shown below.
- A reachable SOLIDserver manager using Basic authentication over HTTPS.
- An API account that can read the selected context and create/delete the demo network, address and DNS records. Cleanup also needs visibility of used addresses and pools in the child network, and any matching reverse DNS record.
- An existing IPAM space and parent IPv4 network, plus a DNS server or Smart and an existing forward zone in the default DNS view.
- A dedicated child subnet within that parent, a usable IPv4 address, a hostname and a distinct application alias.

All playbooks run locally and access SOLIDserver over HTTPS. Steps 02, 03 and 05 change SOLIDserver resources. The demo covers one host A record and one application CNAME, matching reruns and applying the selected TTL. Changes to an existing host address, record type or CNAME target are outside this flow.

## Start

From the demo directory, create a Python virtual environment and install Ansible:

```bash
cd /path/to/sds_ansible_demo
python3 -m venv .venv
source .venv/bin/activate
python -m pip install ansible-core
./sds_ansible_demo
```

If you already have an active virtual environment with Ansible installed, run `./sds_ansible_demo` directly. The launcher installs `SOLIDserverRest==2.14.0` and the EfficientIP collection automatically when first needed. The collection is pinned in `requirements.yml` to version 1.2.0, commit `e893d61ff6cc13945859900d3763a0316b80c732`.

On first run, answer the prompts for the manager, API credentials, TLS verification, optional CA bundle, IPAM space, parent network, demo network/address, DNS server, zone, hostname, application alias and TTL. The TTL defaults to 300 seconds and applies to the host A record and application CNAME.

Settings are saved in `config.json` and reused. The password is hidden during entry. The file contains credentials, has owner-only permissions (`0600`) and is ignored by Git. Change saved settings with:

```bash
./sds_ansible_demo config
```

Press Enter to retain saved values. In later sessions, activate your virtual environment before running the launcher. Enter `q` to leave the demo menu and `deactivate` to leave the virtual environment.

## Run the examples

Choose a numbered step from the menu, or run it directly:

```bash
./sds_ansible_demo 00     # Connect and list IPAM spaces
./sds_ansible_demo 01     # Inspect the IPAM space and parent network
./sds_ansible_demo 02     # Create the demo network, host address and host A record
./sds_ansible_demo 03     # Create the application CNAME alias
./sds_ansible_demo 04     # Verify the demo resources and save result.json
./sds_ansible_demo 05     # Remove the alias, host A/PTR records, address and empty child network
```

To execute steps 00–04 in sequence:

```bash
./sds_ansible_demo run
```

Cleanup is a separate step. In interactive mode, the menu appears once per session; enter `menu` to show it again.

## Host DNS and application DNS

Step 02 creates or reuses the network and persistent host address. If IPAM-to-DNS automation already registered the host A record, the playbook reuses it and applies the selected TTL. Otherwise, it creates the A record.

Step 03 creates a separate application CNAME pointing to that host. This gives the application its own DNS name without allocating another address.

The setup defaults are `ansible-demo-network` for the child network, `ansible-demo-host` for the hostname and `ansible-demo-host-app` for the application alias. With `example.com` as the configured zone:

```dns
ansible-demo-host.example.com.     300 IN A     10.20.30.40
ansible-demo-host-app.example.com. 300 IN CNAME ansible-demo-host.example.com.
```

The application alias is one DNS label and defaults to the hostname plus `-app`. It must differ from the hostname. Matching reruns reuse the records and skip unchanged TTL updates. Conflicting resource identities stop the playbook.

## Quiet and verbose output

The global setting near the top of the `sds_ansible_demo` launcher is:

```python
VERBOSE = False
```

Quiet mode shows the step title, its result message and `OK` after success. Task banners, successful task details, skipped tasks and Ansible recaps are hidden. Lists show at most five entries. For example:

```text
02 — Create the demo network, host address and host A record
  Network 10.20.30.0/24, host ansible-demo-host.example.com -> 10.20.30.40, TTL=300.
  OK

03 — Create the application CNAME alias
  ansible-demo-host-app.example.com CNAME ansible-demo-host.example.com. TTL=300.
  OK
```

Set `VERBOSE = True` to show full Ansible task output, complete lists, the verified handoff and dependency installation logs. Use a Python boolean without quotes. The setting applies to individual steps and `run`.

When `solidserver.check_tls` is explicitly `false`, quiet mode suppresses urllib3's repeated `InsecureRequestWarning` about unverified HTTPS. Verbose mode shows it again. Other warnings and failure diagnostics remain visible, and a failed step stops the run. Failed dependency installs also show their output.

The callback in `callback_plugins/demo_quiet.py` formats console output and preserves Ansible's `no_log` handling.

## TLS certificates

Certificate verification is enabled by default. For a private CA or self-signed certificate, provide a trusted PEM CA bundle at the setup prompt. The configured manager hostname or IP must match the certificate's Subject Alternative Name.

For a controlled lab, you can explicitly disable verification. Run:

```bash
./sds_ansible_demo config
```

At `Verify TLS certificate (no for a self-signed lab)`, enter `no`. This saves `solidserver.check_tls` as the JSON boolean `false`. All six examples use this setting. HTTPS remains in use, but the appliance certificate and identity are not checked.

If step 00 failed with `CERTIFICATE_VERIFY_FAILED`, review these settings and retry it after saving the configuration.

## Where SOLIDserver is integrated

| Example | Integration used |
| --- | --- |
| [00_connect_and_inventory.yml](examples/00_connect_and_inventory.yml) | EfficientIP `solidserver_ipam_ip_space_list` lookup |
| [01_find_space_and_networks.yml](examples/01_find_space_and_networks.yml) | EfficientIP `solidserver_ipam_ip_network_list` lookup |
| [02_create_network_and_address.yml](examples/02_create_network_and_address.yml) | EfficientIP network/IP modules, host A record and TTL handling |
| [03_publish_dns_record.yml](examples/03_publish_dns_record.yml) | EfficientIP `solidserver_dns_rr` creates the application CNAME; REST verifies its target and TTL |
| [04_verify_and_recap.yml](examples/04_verify_and_recap.yml) | Independent REST reads using `ansible.builtin.uri` |
| [05_cleanup.yml](examples/05_cleanup.yml) | EfficientIP DNS/IP modules remove the CNAME, A record and address; REST removes any remaining matching PTR and the verified empty child network, then confirms absence |

For example, step 02 contains the collection call directly:

```yaml
- name: '[SOLIDserver collection] Ensure the demo network exists'
  community.efficientip.solidserver_ipam_network:
    provider: '{{ solidserver }}'
    space: '{{ space }}'
    parent: '{{ parent_network }}'
    subnet: '{{ network }}'
    name: '{{ network_name }}'
    is_terminal: true
    update: false
    state: present
```

The Python launcher handles prompts, saved settings, dependencies, playbook selection and output settings. SOLIDserver operations run in the playbooks. The EfficientIP collection is used without modifications. No custom roles, custom collections or metadata classes are required.

## Verify and clean up

Run 00 and 01 first, then 02, 03 and 04. Step 04 reads back the network, address, host A record and application CNAME. It writes their actual IDs and verified values to `result.json` only after the checks pass.

Verification covers the SOLIDserver API. Query the authoritative DNS server separately to confirm DNS publication and resolution.

Repeat 02, 03 and 04 with the same settings to demonstrate matching reruns. Resource creation and unchanged TTL updates should be skipped.

Step 05 removes the application CNAME, host A record and IPAM address. It then removes any remaining matching host PTR and the empty child network. Cleanup verifies that these resources are absent before removing `result.json`. A child network containing used addresses or pools is retained. The parent network and DNS zones are retained. A second cleanup should make no remote changes.

After a failed step, inspect the actual state before continuing; there is no automatic rollback. A `result.json` from an earlier run does not verify a failed run. Saved credentials, results, virtual environments and installed dependencies stay local and are ignored by Git.

Licensed under the [MIT License](LICENSE).
