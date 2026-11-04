# create_vm-from-iso.sh

## Description
Creates a VMware vSphere/ESXi virtual machine using `govc`, attaches an ISO image as a virtual CD-ROM, and powers the VM on.

The script is interactive and guides you through:
- vSphere credentials and VM name
- Guest OS ID selection (or custom entry)
- ISO discovery and selection from a datastore path (optional filter)
- VM sizing profile selection (CPU/RAM/Disk)

---

## Usage

### 1) Prerequisites
- `govc` installed and available in your `PATH`
- Connectivity and permissions to your ESXi host or vCenter

### 2) Optional configuration via environment variables
The script provides sensible defaults you can override:

```bash
export GOVC_URL="https://myesx.myzone.mytld"
export GOVC_INSECURE=1

export VM_DATASTORE="datastore1"
export ISO_DATASTORE="datastore2"
export ISO_PATH="ISO"
export NETWORK="myNet"
export ADAPTER="vmxnet3"
```

Default values (when not set):
- `GOVC_URL=https://myesx.myzone.mytld`
- `GOVC_INSECURE=1`
- `VM_DATASTORE=datastore1`
- `ISO_DATASTORE=datastore2`
- `ISO_PATH=ISO`
- `NETWORK=myNet`
- `ADAPTER=vmxnet3`

### 3) Run
```bash
chmod +x create_vm-from-iso.sh
./create_vm-from-iso.sh
```

You will be prompted for:
- vSphere username (defaults to `root`) and password
- VM name
- Guest OS ID (menu or custom)
- ISO filter (optional) and ISO selection
- Sizing profile (`small`, `medium`, `large`)

---

## Requirements
- Bash
- `govc` (govmomi CLI)

You also need privileges to:
- list ISO files on the ISO datastore/path
- create a VM, attach an ISO, and connect the CD-ROM device
- power on the VM

---

## Input / Output
- **Input:**
  - Interactive prompts (credentials, VM name, guest OS ID, ISO selection, sizing profile)
  - Optional environment variables for placement and defaults
- **Output:**
  - A newly created VM with:
    - selected CPU/RAM/Disk profile
    - network adapter connected to the selected network
    - ISO attached and connected as CD-ROM
  - The VM is powered on at the end

---

## Notes
- **Guest OS IDs:** The guest OS menu is a convenience list. If you don’t see the OS you need, choose the “Custom” option and enter the appropriate guest ID for `govc vm.create -g <ID>`.
- **ISO discovery:** The script searches the ISO datastore path recursively and filters for `*.iso`. If you have many ISOs, use the filter prompt to narrow the list.
- **Sizing profiles:** Profiles are defined in the script as:
  - `small`: 1 CPU, 4 GB RAM, 32 GB disk
  - `medium`: 2 CPU, 8 GB RAM, 64 GB disk
  - `large`: 4 CPU, 16 GB RAM, 128 GB disk
- **Credential handling:** The script exports credentials for `govc` via environment variables after prompting. Be mindful of your environment (shell history, shared terminals, CI logs).

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
