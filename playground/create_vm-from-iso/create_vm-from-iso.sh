#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# create_vm-from-iso.sh
# - Create ONE VM booting from an ISO
# - Requires: govc (https://github.com/vmware/govmomi/tree/main/govc)
# ==========================================================

# =========================
# ENVIRONMENT (defaults)
# =========================
: "${GOVC_URL:=https://myesx.myzone.mytld}"
: "${GOVC_INSECURE:=1}"
export GOVC_URL GOVC_INSECURE

# Placement / hardware defaults
VM_DATASTORE="${VM_DATASTORE:-datastore1}"
ISO_DATASTORE="${ISO_DATASTORE:-datastore2}"
ISO_PATH="${ISO_PATH:-ISO}"
NETWORK="${NETWORK:-myNet}"
ADAPTER="${ADAPTER:-vmxnet3}"

# =========================
# GUEST OS LIST (static)
# =========================
# These IDs are passed to: govc vm.create -g <ID>
GUEST_OS_CHOICES=(
  freebsdGuest
  freebsd64Guest
  redhatGuest
  redhat64Guest
  centosGuest
  centos64Guest
  ubuntuGuest
  ubuntu64Guest
  debianGuest
  fedoraGuest
  fedora64Guest
  otherLinuxGuest
  otherLinux64Guest
  otherGuest
  otherGuest64
)

# =========================
# PROFILES
# =========================
# size|cpu|mem_gb|disk_gb|text
APPLIANCES=(
  "small|1|4|32|1 CPUs, 4GB memory, 32G storage"
  "medium|2|8|64|2 CPUs, 8GB memory, 64G storage"
  "large|4|16|128|4 CPUs, 16GB memory, 128G storage"
)

# =========================
# HELPERS
# =========================
die() {
  echo "ERROR: $*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

lower() {
  tr '[:upper:]' '[:lower:]'
}

require_govc() {
  have_cmd govc || die "govc not found in PATH"
}

print_appliances() {
  echo
  echo "# Available machine sizes:"
  for entry in "${APPLIANCES[@]}"; do
    IFS="|" read -r size cpu mem disk text <<< "$entry"
    printf "  %-6s  %2s CPU  %3s GB RAM  %3s GB Disk\n" "$size" "$cpu" "$mem" "$disk"
  done
  echo
}

choose_appliance() {
  local options=()
  for entry in "${APPLIANCES[@]}"; do
    IFS="|" read -r size _ <<< "$entry"
    options+=("$size")
  done
  options+=("Quit")

  while true; do
    PS3="# Machine size: "
    select selection in "${options[@]}"; do
      [[ "${selection:-}" == "Quit" ]] && exit 0

      for entry in "${APPLIANCES[@]}"; do
        IFS="|" read -r size cpu mem disk text <<< "$entry"
        if [[ "$size" == "${selection:-}" ]]; then
          APP_SIZE="$size"
          CPU="$cpu"
          MEM_GB="$mem"
          DISK_GB="$disk"
          APP_TEXT="$text"
          return 0
        fi
      done

      echo "# Invalid selection."
      break
    done
  done
}

choose_guest_os() {
  local options=("${GUEST_OS_CHOICES[@]}" "Custom (enter guest ID)" "Quit")

  while true; do
    echo
    echo "# Select guest OS (govc vm.create -g <ID>):"
    PS3="# Guest OS: "
    select selection in "${options[@]}"; do
      [[ "${selection:-}" == "Quit" ]] && exit 0

      if [[ "${selection:-}" == "Custom (enter guest ID)" ]]; then
        local custom
        read -r -p "# Guest OS ID: " custom
        [[ -n "$custom" ]] || { echo "# Guest OS ID cannot be empty."; break; }
        GUEST_OS="$custom"
        return 0
      fi

      if [[ -n "${selection:-}" ]]; then
        GUEST_OS="$selection"
        return 0
      fi

      echo "# Invalid selection."
      break
    done
  done
}

list_iso_files() {
  govc datastore.ls -ds="$ISO_DATASTORE" -R "$ISO_PATH" 2>/dev/null \
    | grep -Ei '\.iso$' || true
}

choose_iso() {
  local iso_all=()
  mapfile -t iso_all < <(list_iso_files)

  ((${#iso_all[@]} > 0)) || die "No ISO files found in [${ISO_DATASTORE}] ${ISO_PATH}"

  local filter
  read -r -p "# ISO filter (optional, e.g. ubuntu, debian): " filter

  local options=()
  if [[ -n "${filter}" ]]; then
    local f
    f="$(printf '%s' "$filter" | lower)"
    for iso in "${iso_all[@]}"; do
      if [[ "$(printf '%s' "$iso" | lower)" == *"$f"* ]]; then
        options+=("$iso")
      fi
    done
  else
    options=("${iso_all[@]}")
  fi

  ((${#options[@]} > 0)) || die "No ISO files matched filter: $filter"
  options+=("Quit")

  while true; do
    echo
    echo "# Available ISO files in [${ISO_DATASTORE}] ${ISO_PATH}:"
    PS3="# ISO: "
    select selection in "${options[@]}"; do
      [[ "${selection:-}" == "Quit" ]] && exit 0

      if [[ -n "${selection:-}" ]]; then
        if [[ "$selection" == /* ]]; then
          ISO_FILE_PATH="$selection"
        elif [[ "$selection" == "$ISO_PATH" || "$selection" == "$ISO_PATH/"* ]]; then
          ISO_FILE_PATH="$selection"
        else
          ISO_FILE_PATH="${ISO_PATH}/${selection}"
        fi
        return 0
      fi

      echo "# Invalid selection."
      break
    done
  done
}

create_vm() {
  local vm_name="$1"
  local mem_mb=$((MEM_GB * 1024))

  echo
  echo "# Creating VM:  '$vm_name' on $GOVC_URL"
  echo "  - profile:    $APP_SIZE ($APP_TEXT)"
  echo "  - datastore:  $VM_DATASTORE"
  echo "  - iso:        [${ISO_DATASTORE}] ${ISO_FILE_PATH}"
  echo "  - guest:      $GUEST_OS"
  echo "  - hardware:   $CPU CPU(s), ${MEM_GB}GB memory, ${DISK_GB}GB disk"
  echo "  - network:    $NETWORK / $ADAPTER"

  govc vm.create \
    -ds="$VM_DATASTORE" \
    -iso="$ISO_FILE_PATH" \
    -iso-datastore="$ISO_DATASTORE" \
    -on=false \
    -g="$GUEST_OS" \
    -c="$CPU" \
    -m="$mem_mb" \
    -disk="${DISK_GB}GB" \
    -net="$NETWORK" \
    -net.adapter="$ADAPTER" \
    "$vm_name"

  echo "# Checking VM   '$vm_name' on $GOVC_URL"
  govc vm.info "$vm_name" | grep -E '^(Name:|  UUID:|  Power state:|  IP address:)' || true

  echo "# Starting VM:  '$vm_name' on $GOVC_URL"
  govc vm.power -on "$vm_name"

  echo "# Running VM:   '$vm_name' on $GOVC_URL"
  govc vm.info "$vm_name" | grep -E '^(Name:|  UUID:|  Power state:|  IP address:)' || true

  echo "# Done with VM: '$vm_name' on $GOVC_URL"
}

# =========================
# MAIN
# =========================
require_govc

read -r -p "# Username (default: root): " GOVC_USERNAME_IN
export GOVC_USERNAME="${GOVC_USERNAME_IN:-root}"

read -r -s -p "# Password: " GOVC_PASSWORD
echo
export GOVC_PASSWORD

read -r -p "# VM name: " VM_NAME
[[ -n "$VM_NAME" ]] || die "VM name cannot be empty."

choose_guest_os
choose_iso

print_appliances
choose_appliance

create_vm "$VM_NAME"

echo
echo "# All done. Created and started VM: $VM_NAME"
