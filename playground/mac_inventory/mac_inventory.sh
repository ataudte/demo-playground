#!/usr/bin/env bash

# Collects macOS hardware, operating-system, storage, network, and security data.
# It prints a human-readable summary and saves full details as a private,
# timestamped JSON file in the current directory. It never transmits the data.

set -Eeuo pipefail
export LC_ALL=C

readonly SCRIPT_NAME="${0##*/}"

log() {
    printf '[macOS Inventory] %s\n' "$*" >&2
}

die() {
    log "Error: $*"
    exit 1
}

json_string() {
    local value="${1-}"
    local escaped=''
    local character
    local character_code
    local index

    for ((index = 0; index < ${#value}; index++)); do
        character="${value:index:1}"
        case "$character" in
            '"')    escaped+='\"' ;;
            \\)     escaped+='\\' ;;
            $'\b')  escaped+='\b' ;;
            $'\f')  escaped+='\f' ;;
            $'\n')  escaped+='\n' ;;
            $'\r')  escaped+='\r' ;;
            $'\t')  escaped+='\t' ;;
            *)
                printf -v character_code '%d' "'$character"
                if ((character_code < 32)); then
                    printf -v character '\\u%04x' "$character_code"
                fi
                escaped+="$character"
                ;;
        esac
    done

    printf '"%s"' "$escaped"
}

json_number() {
    local value="${1-}"

    if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$value"
    else
        printf 'null'
    fi
}

profiler_value() {
    local profiler_output="$1"
    local label="$2"

    awk -v label="$label" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            prefix = label ":"
            if (index(line, prefix) == 1) {
                value = substr(line, length(prefix) + 1)
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                print value
                exit
            }
        }
    ' <<< "$profiler_output"
}

first_integer() {
    awk '
        match($0, /[0-9]+/) {
            print substr($0, RSTART, RLENGTH)
            exit
        }
    ' <<< "${1-}"
}

ioreg_integer() {
    local registry_output="$1"
    local property_name="$2"

    awk -v property_name="$property_name" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            prefix = "\"" property_name "\""
            if (index(line, prefix) == 1) {
                sub(/^[^=]*=[[:space:]]*/, "", line)
                if (match(line, /[0-9]+/)) {
                    print substr(line, RSTART, RLENGTH)
                    exit
                }
            }
        }
    ' <<< "$registry_output"
}

battery_health_percentage() {
    local profile_json="$1"
    local registry_output="$2"
    local percentage
    local raw_capacity
    local design_capacity

    percentage=$(awk '
        /"sppower_battery_maximum_capacity"/ {
            if (match($0, /[0-9]+/)) {
                print substr($0, RSTART, RLENGTH)
                exit
            }
        }
    ' <<< "$profile_json")

    if [[ "$percentage" =~ ^[0-9]+$ && "$percentage" -le 100 ]]; then
        printf '%s' "$percentage"
        return
    fi

    raw_capacity=$(ioreg_integer "$registry_output" 'AppleRawMaxCapacity')
    if [[ -z "$raw_capacity" ]]; then
        raw_capacity=$(ioreg_integer "$registry_output" 'NominalChargeCapacity')
    fi
    design_capacity=$(ioreg_integer "$registry_output" 'DesignCapacity')

    if [[ "$raw_capacity" =~ ^[0-9]+$ && "$design_capacity" =~ ^[0-9]+$ \
        && "$raw_capacity" -gt 500 && "$design_capacity" -gt 500 ]]; then
        percentage=$(awk -v current="$raw_capacity" -v design="$design_capacity" '
            BEGIN {
                value = current * 100 / design
                if (value <= 150) {
                    if (value > 100) value = 100
                    printf "%.0f", value
                }
            }
        ')
        if [[ "$percentage" =~ ^[0-9]+$ && "$percentage" -le 100 ]]; then
            printf '%s' "$percentage"
            return
        fi
    fi

    printf 'null'
}

firewall_state_from_output() {
    case "$1" in
        *'State = 0'*|*disabled*)           printf 'false' ;;
        *'State = 1'*|*'State = 2'*|*enabled*) printf 'true' ;;
        *)                                  printf 'null' ;;
    esac
}

stealth_state_from_output() {
    case "$1" in
        *disabled*) printf 'false' ;;
        *enabled*)  printf 'true' ;;
        *)          printf 'null' ;;
    esac
}

manufacture_year_for() {
    local model="$1"
    local model_id="$2"

    if [[ "$model" =~ (19|20)[0-9]{2} ]]; then
        printf '%s' "${BASH_REMATCH[0]}"
        return
    fi

    case "$model_id" in
        # MacBook Air
        MacBookAir7,1|MacBookAir7,2)                              printf '2017' ;;
        MacBookAir8,1)                                            printf '2018' ;;
        MacBookAir8,2)                                            printf '2019' ;;
        MacBookAir9,1|MacBookAir10,1)                             printf '2020' ;;
        Mac14,2|MacBookAir13,1|MacBookAir13,2)                    printf '2022' ;;
        Mac14,15|MacBookAir14,2)                                  printf '2023' ;;
        Mac15,12|Mac15,13)                                       printf '2024' ;;
        Mac16,12|Mac16,13)                                       printf '2025' ;;
        Mac17,3|Mac17,4)                                         printf '2026' ;;

        # MacBook Pro
        MacBookPro13,1|MacBookPro13,2|MacBookPro13,3)             printf '2016' ;;
        MacBookPro14,1|MacBookPro14,2|MacBookPro14,3)             printf '2017' ;;
        MacBookPro15,1|MacBookPro15,2)                            printf '2018' ;;
        MacBookPro15,3|MacBookPro15,4|MacBookPro16,1|MacBookPro16,4) printf '2019' ;;
        MacBookPro16,2|MacBookPro16,3|MacBookPro17,1)             printf '2020' ;;
        MacBookPro18,1|MacBookPro18,2|MacBookPro18,3|MacBookPro18,4) printf '2021' ;;
        Mac14,7)                                                  printf '2022' ;;
        Mac14,5|Mac14,6|Mac14,9|Mac14,10|Mac15,3|Mac15,6|Mac15,7|Mac15,8|Mac15,9|Mac15,10|Mac15,11) printf '2023' ;;
        Mac16,1|Mac16,5|Mac16,6|Mac16,7|Mac16,8)                 printf '2024' ;;
        Mac17,2)                                                  printf '2025' ;;
        Mac17,6|Mac17,7|Mac17,8|Mac17,9)                         printf '2026' ;;

        # MacBook and MacBook Neo
        MacBook9,1)                                               printf '2016' ;;
        MacBook10,1)                                              printf '2017' ;;
        Mac17,5)                                                  printf '2026' ;;

        # Mac mini
        Macmini8,1)                                               printf '2018' ;;
        Macmini9,1)                                               printf '2020' ;;
        Mac14,3|Mac14,12)                                        printf '2023' ;;
        Mac16,10|Mac16,11)                                       printf '2024' ;;

        # iMac and iMac Pro
        iMac18,1|iMac18,2|iMac18,3|iMacPro1,1)                   printf '2017' ;;
        iMac19,1|iMac19,2)                                       printf '2019' ;;
        iMac20,1|iMac20,2)                                       printf '2020' ;;
        iMac21,1|iMac21,2)                                       printf '2021' ;;
        Mac15,4|Mac15,5)                                         printf '2023' ;;
        Mac16,2|Mac16,3)                                         printf '2024' ;;

        # Mac Pro and Mac Studio
        MacPro7,1)                                                printf '2019' ;;
        Mac13,1|Mac13,2)                                         printf '2022' ;;
        Mac14,8|Mac14,13|Mac14,14)                               printf '2023' ;;
        Mac15,14|Mac16,9)                                        printf '2025' ;;
        *)                                                        printf 'null' ;;
    esac
}

machine_type_for() {
    local model="$1"
    local model_id="$2"

    case "$model $model_id" in
        *MacBook*)                              printf 'Laptop' ;;
        *iMac*|*Macmini*|*MacPro*|*Mac\ mini*|*Mac\ Pro*|*Mac\ Studio*)
            printf 'Desktop'
            ;;
        *)                                     printf 'Unknown' ;;
    esac
}

builtin_display_size_for() {
    case "$1" in
        MacBookPro18,1|MacBookPro18,2|Mac14,6|Mac14,10|Mac15,7|Mac15,9|Mac15,11|Mac16,5|Mac16,7|Mac17,7|Mac17,9) printf '16.2' ;;
        MacBookPro16,1|MacBookPro16,4|MacBookPro15,1|MacBookPro15,3) printf '15.4' ;;
        MacBookPro18,3|MacBookPro18,4|Mac14,5|Mac14,9|Mac15,6|Mac15,8|Mac15,10|Mac16,1|Mac16,6|Mac16,8|Mac17,2|Mac17,6|Mac17,8) printf '14.2' ;;
        MacBookPro13,*|MacBookPro14,*|MacBookPro15,2|MacBookPro15,4|MacBookPro16,2|MacBookPro16,3|MacBookPro17,1|Mac14,7) printf '13.3' ;;
        MacBookAir10,1|MacBookAir9,1|MacBookAir8,*|MacBookAir7,2) printf '13.3' ;;
        Mac14,2|Mac15,12|Mac16,12|Mac17,3|MacBookAir13,1|MacBookAir14,2) printf '13.6' ;;
        Mac14,15|Mac15,13|Mac16,13|Mac17,4|MacBookAir13,2) printf '15.3' ;;
        MacBookAir7,1)                                            printf '11.6' ;;
        MacBook9,1|MacBook10,1)                                  printf '12' ;;
        iMac18,1|iMac21,1|iMac21,2|Mac15,4|Mac16,2)             printf '21.5' ;;
        iMac18,2|iMac18,3|iMac19,*|iMac20,*|iMacPro1,1|Mac15,5|Mac16,3) printf '27' ;;
        *)                                                        printf 'null' ;;
    esac
}

apple_silicon_memory_speed() {
    case "$1" in
        *"M1 Pro"*|*"M1 Max"*|*"M1 Ultra"*) printf '6400' ;;
        *M1*)                                  printf '4266' ;;
        *M2*|*M3*)                             printf '6400' ;;
        *M4*)                                  printf '7500' ;;
        *M5*)                                  printf '8533' ;;
        *)                                     printf 'null' ;;
    esac
}

display_rows() {
    local profiler_output="$1"

    awk '
        BEGIN { name = "" }

        /^[[:space:]]+[^:]+:[[:space:]]*$/ {
            candidate = $0
            gsub(/^[[:space:]]+|:[[:space:]]*$/, "", candidate)
            if (candidate != "Displays" && candidate !~ /Graphics/) {
                name = candidate
            }
        }

        /Resolution:/ {
            resolution = $0
            sub(/^[[:space:]]*Resolution:[[:space:]]*/, "", resolution)
            sub(/ Retina.*/, "", resolution)
            gsub(/ x /, "x", resolution)
            if (name == "") {
                name = "Display"
            }
            print name "\t" resolution
            name = ""
        }
    ' <<< "$profiler_output"
}

displays_json() {
    local rows="$1"
    local builtin_size="$2"
    local name
    local resolution
    local size
    local separator=''
    local result='['
    local count=0

    while IFS=$'\t' read -r name resolution; do
        [[ -n "$name$resolution" ]] || continue

        count=$((count + 1))
        if [[ "$name" == "Display" ]]; then
            name="Display $count"
        fi

        size='null'
        if [[ "$count" -eq 1 && "$builtin_size" != 'null' ]]; then
            size="$builtin_size"
        fi

        result+="$separator{\"name\":$(json_string "$name"),\"resolution\":$(json_string "$resolution"),\"size_inch\":$size}"
        separator=','
    done <<< "$rows"

    if [[ "$count" -eq 0 ]]; then
        result+='{"name":"Built-in Display","resolution":"Unknown","size_inch":null}'
    fi

    result+=']'
    printf '%s' "$result"
}

emit_inventory_json() {
    cat <<JSON
{
  "hostname": $(json_string "$HOSTNAME_VALUE"),
  "os_name": "macOS",
  "os_version": $(json_string "macOS $OS_VERSION ($OS_BUILD)"),
  "os_arch": $(json_string "$OS_ARCH"),
  "rosetta_translated": $ROSETTA_TRANSLATED,
  "kernel_version": $(json_string "$KERNEL_VERSION"),
  "manufacturer": "Apple",
  "model": $(json_string "$MODEL ($MODEL_ID)"),
  "serial_number": $(json_string "$SERIAL_NUMBER"),
  "bios_version": "N/A (EFI)",
  "machine_type": $(json_string "$MACHINE_TYPE"),
  "manufacture_year": $(json_number "$MANUFACTURE_YEAR"),
  "purchase_year": $(json_number "$MANUFACTURE_YEAR"),
  "cpu_model": $(json_string "$CPU_MODEL"),
  "cpu_cores": $(json_number "$CPU_CORES"),
  "cpu_threads": $(json_number "$CPU_THREADS"),
  "cpu_speed_mhz": $(json_number "$CPU_SPEED_MHZ"),
  "ram_total_gb": $(json_number "$RAM_TOTAL_GB"),
  "ram_used_gb": $(json_number "$RAM_USED_GB"),
  "ram_slots_total": $(json_number "$RAM_SLOTS_TOTAL"),
  "ram_slots_used": $(json_number "$RAM_SLOTS_USED"),
  "ram_type": $(json_string "$RAM_TYPE"),
  "ram_speed_mhz": $(json_number "$RAM_SPEED_MHZ"),
  "disk_total_gb": $(json_number "$DISK_TOTAL_GB"),
  "disk_used_gb": $(json_number "$DISK_USED_GB"),
  "disk_free_gb": $(json_number "$DISK_FREE_GB"),
  "disk_usage_pct": $(json_number "$DISK_USAGE_PCT"),
  "disk_type": $(json_string "$DISK_TYPE"),
  "disk_model": $(json_string "$DISK_MODEL"),
  "disk_health": $(json_string "$DISK_HEALTH"),
  "disk_reallocated_sectors": $(json_number "$DISK_REALLOCATED"),
  "disk_power_on_hours": $(json_number "$DISK_POWER_ON_HOURS"),
  "mac_address": $(json_string "$MAC_ADDRESS"),
  "ip_address": $(json_string "$IP_ADDRESS"),
  "displays": $DISPLAYS_JSON,
  "battery_present": $BATTERY_PRESENT,
  "battery_health_pct": $(json_number "$BATTERY_HEALTH_PCT"),
  "antivirus": $(json_string "$ANTIVIRUS"),
  "firewall_enabled": $FIREWALL_ENABLED,
  "firewall_stealth_mode": $FIREWALL_STEALTH_MODE,
  "encryption_enabled": $ENCRYPTION_ENABLED,
  "last_os_update": $(json_string "$LAST_OS_UPDATE")
}
JSON
}

human_value() {
    local value="${1-}"

    if [[ -z "$value" || "$value" == 'null' ]]; then
        printf 'Not available'
    else
        printf '%s' "$value"
    fi
}

human_boolean() {
    case "${1-}" in
        true)  printf 'Yes' ;;
        false) printf 'No' ;;
        *)     printf 'Not available' ;;
    esac
}

print_field() {
    local label="$1"
    local value="$2"

    printf '  %-24s %s\n' "$label:" "$(human_value "$value")"
}

print_measurement() {
    local label="$1"
    local value="$2"
    local unit="$3"

    if [[ -z "$value" || "$value" == 'null' ]]; then
        print_field "$label" 'null'
    elif [[ "$unit" == '%' ]]; then
        print_field "$label" "${value}%"
    else
        print_field "$label" "$value $unit"
    fi
}

print_human_summary() {
    local output_file="$1"
    local rows="$2"
    local builtin_size="$3"
    local display_count=0
    local display_name
    local resolution
    local display_details
    local architecture_details="$OS_ARCH"

    if [[ "$ROSETTA_TRANSLATED" == 'true' ]]; then
        architecture_details+=' (Rosetta 2)'
    fi

    printf '\nmacOS Inventory\n'
    printf '%s\n' '==============='

    printf '\nSystem\n'
    print_field 'Hostname' "$HOSTNAME_VALUE"
    print_field 'Operating system' "macOS $OS_VERSION ($OS_BUILD)"
    print_field 'Architecture' "$architecture_details"
    print_field 'Kernel' "$KERNEL_VERSION"

    printf '\nHardware\n'
    print_field 'Manufacturer' 'Apple'
    print_field 'Model' "$MODEL ($MODEL_ID)"
    print_field 'Serial number' "$SERIAL_NUMBER"
    print_field 'Machine type' "$MACHINE_TYPE"
    print_field 'Model year' "$MANUFACTURE_YEAR"
    print_field 'Firmware' 'EFI'

    printf '\nProcessor\n'
    print_field 'Model' "$CPU_MODEL"
    print_field 'Physical cores' "$CPU_CORES"
    print_field 'Logical threads' "$CPU_THREADS"
    if [[ "$CPU_SPEED_MHZ" != 'null' ]]; then
        print_measurement 'Speed' "$CPU_SPEED_MHZ" 'MHz'
    fi

    printf '\nMemory\n'
    print_measurement 'Total' "$RAM_TOTAL_GB" 'GB'
    print_measurement 'Used' "$RAM_USED_GB" 'GB'
    print_field 'Type' "$RAM_TYPE"
    if [[ "$RAM_SPEED_MHZ" != 'null' ]]; then
        print_measurement 'Speed' "$RAM_SPEED_MHZ" 'MT/s'
    fi
    if [[ "$RAM_SLOTS_USED" != 'null' && "$RAM_SLOTS_TOTAL" != 'null' ]]; then
        print_field 'Slots used / total' "$RAM_SLOTS_USED / $RAM_SLOTS_TOTAL"
    fi

    printf '\nStorage\n'
    print_field 'Model' "$DISK_MODEL"
    print_field 'Type' "$DISK_TYPE"
    print_measurement 'Capacity' "$DISK_TOTAL_GB" 'GB'
    print_measurement 'Used' "$DISK_USED_GB" 'GB'
    print_measurement 'Free' "$DISK_FREE_GB" 'GB'
    print_measurement 'Usage' "$DISK_USAGE_PCT" '%'
    print_field 'Health' "$DISK_HEALTH"
    if [[ "$DISK_REALLOCATED" != 'null' ]]; then
        print_field 'Reallocated sectors' "$DISK_REALLOCATED"
    fi
    if [[ "$DISK_POWER_ON_HOURS" != 'null' ]]; then
        print_measurement 'Power-on time' "$DISK_POWER_ON_HOURS" 'hours'
    fi

    printf '\nNetwork\n'
    print_field 'MAC address' "$MAC_ADDRESS"
    print_field 'IP address' "$IP_ADDRESS"

    printf '\nDisplays\n'
    while IFS=$'\t' read -r display_name resolution; do
        [[ -n "$display_name$resolution" ]] || continue

        display_count=$((display_count + 1))
        if [[ "$display_name" == 'Display' ]]; then
            display_name="Display $display_count"
        fi

        display_details="$resolution"
        if [[ "$display_count" -eq 1 && "$builtin_size" != 'null' ]]; then
            display_details+=" (${builtin_size} in)"
        fi
        print_field "$display_name" "$display_details"
    done <<< "$rows"
    if [[ "$display_count" -eq 0 ]]; then
        print_field 'Display' 'Unknown'
    fi

    printf '\nBattery and security\n'
    print_field 'Battery present' "$(human_boolean "$BATTERY_PRESENT")"
    if [[ "$BATTERY_PRESENT" == 'true' ]]; then
        print_measurement 'Battery health' "$BATTERY_HEALTH_PCT" '%'
    fi
    print_field 'Antivirus' "$ANTIVIRUS"
    print_field 'Firewall enabled' "$(human_boolean "$FIREWALL_ENABLED")"
    if [[ "$FIREWALL_ENABLED" == 'true' && "$FIREWALL_STEALTH_MODE" != 'null' ]]; then
        print_field 'Firewall stealth mode' "$(human_boolean "$FIREWALL_STEALTH_MODE")"
    fi
    print_field 'FileVault enabled' "$(human_boolean "$ENCRYPTION_ENABLED")"
    print_field 'Last OS update' "$LAST_OS_UPDATE"

    printf '\nOutput\n'
    print_field 'JSON file' "$output_file"
    printf '\n'
}

main() {
    if [[ $# -ne 0 ]]; then
        die "This script does not accept arguments. Usage: $SCRIPT_NAME"
    fi

    if [[ "$(uname -s)" != 'Darwin' ]]; then
        die 'This script requires macOS.'
    fi

    log 'Collecting system information...'

    HOSTNAME_VALUE=$(hostname 2>/dev/null || true)
    HOSTNAME_VALUE="${HOSTNAME_VALUE:-Unknown}"
    OS_VERSION=$(sw_vers -productVersion 2>/dev/null || true)
    OS_VERSION="${OS_VERSION:-Unknown}"
    OS_BUILD=$(sw_vers -buildVersion 2>/dev/null || true)
    OS_BUILD="${OS_BUILD:-Unknown}"
    local process_arch
    local rosetta_state
    local arm64_supported
    process_arch=$(uname -m 2>/dev/null || true)
    process_arch="${process_arch:-Unknown}"
    rosetta_state=$(sysctl -in sysctl.proc_translated 2>/dev/null || true)
    arm64_supported=$(sysctl -n hw.optional.arm64 2>/dev/null || true)
    ROSETTA_TRANSLATED='false'
    OS_ARCH="$process_arch"
    if [[ "$rosetta_state" == '1' ]]; then
        ROSETTA_TRANSLATED='true'
        OS_ARCH='arm64'
    elif [[ "$arm64_supported" == '1' ]]; then
        OS_ARCH='arm64'
    fi
    KERNEL_VERSION=$(uname -r 2>/dev/null || true)
    KERNEL_VERSION="${KERNEL_VERSION:-Unknown}"

    local hardware_profile
    hardware_profile=$(system_profiler SPHardwareDataType 2>/dev/null || true)
    MODEL=$(profiler_value "$hardware_profile" 'Model Name')
    MODEL="${MODEL:-Unknown}"
    MODEL_ID=$(profiler_value "$hardware_profile" 'Model Identifier')
    MODEL_ID="${MODEL_ID:-Unknown}"
    SERIAL_NUMBER=$(profiler_value "$hardware_profile" 'Serial Number (system)')
    if [[ -z "$SERIAL_NUMBER" ]]; then
        SERIAL_NUMBER=$(profiler_value "$hardware_profile" 'Serial Number')
    fi
    SERIAL_NUMBER="${SERIAL_NUMBER:-Unknown}"
    MANUFACTURE_YEAR=$(manufacture_year_for "$MODEL" "$MODEL_ID")
    MACHINE_TYPE=$(machine_type_for "$MODEL" "$MODEL_ID")

    CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
    if [[ -z "$CPU_MODEL" ]]; then
        CPU_MODEL=$(profiler_value "$hardware_profile" 'Chip')
    fi
    if [[ -z "$CPU_MODEL" ]]; then
        CPU_MODEL=$(profiler_value "$hardware_profile" 'Processor Name')
    fi
    CPU_MODEL="${CPU_MODEL:-Unknown}"

    CPU_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || true)
    CPU_THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null || true)

    local cpu_frequency_hz
    local processor_speed
    cpu_frequency_hz=$(sysctl -n hw.cpufrequency 2>/dev/null || true)
    CPU_SPEED_MHZ='null'
    if [[ "$cpu_frequency_hz" =~ ^[0-9]+$ && "$cpu_frequency_hz" -gt 0 ]]; then
        CPU_SPEED_MHZ=$(awk -v hz="$cpu_frequency_hz" 'BEGIN { printf "%.0f", hz / 1000000 }')
    else
        processor_speed=$(profiler_value "$hardware_profile" 'Processor Speed')
        if [[ "$processor_speed" == *GHz* ]]; then
            CPU_SPEED_MHZ=$(awk -v speed="$processor_speed" '
                match(speed, /[0-9]+([.][0-9]+)?/) {
                    printf "%.0f", substr(speed, RSTART, RLENGTH) * 1000
                }
            ')
        elif [[ "$processor_speed" == *MHz* ]]; then
            CPU_SPEED_MHZ=$(first_integer "$processor_speed")
        fi
        CPU_SPEED_MHZ="${CPU_SPEED_MHZ:-null}"
    fi

    local ram_bytes
    local memory_profile
    local vm_statistics
    local page_size
    local pages_active
    local pages_wired
    local slot_counts
    ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
    RAM_TOTAL_GB='null'
    if [[ "$ram_bytes" =~ ^[0-9]+$ && "$ram_bytes" -gt 0 ]]; then
        RAM_TOTAL_GB=$(awk -v bytes="$ram_bytes" 'BEGIN { printf "%.0f", bytes / 1073741824 }')
    fi

    vm_statistics=$(vm_stat 2>/dev/null || true)
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || true)
    pages_active=$(awk '/^Pages active:/ { gsub(/\./, "", $3); print $3; exit }' <<< "$vm_statistics")
    pages_wired=$(awk '/^Pages wired down:/ { gsub(/\./, "", $4); print $4; exit }' <<< "$vm_statistics")
    RAM_USED_GB='null'
    if [[ "$page_size" =~ ^[0-9]+$ && "$pages_active" =~ ^[0-9]+$ && "$pages_wired" =~ ^[0-9]+$ ]]; then
        RAM_USED_GB=$(awk -v active="$pages_active" -v wired="$pages_wired" -v size="$page_size" \
            'BEGIN { printf "%.2f", (active + wired) * size / 1073741824 }')
    fi

    memory_profile=$(system_profiler SPMemoryDataType 2>/dev/null || true)
    RAM_TYPE=$(profiler_value "$memory_profile" 'Type')
    RAM_TYPE="${RAM_TYPE:-Unknown}"
    RAM_SPEED_MHZ=$(first_integer "$(profiler_value "$memory_profile" 'Speed')")
    RAM_SPEED_MHZ="${RAM_SPEED_MHZ:-null}"
    slot_counts=$(awk '
        /^[[:space:]]*[^:]*DIMM[^:]*:[[:space:]]*$/ {
            total++
            reading_slot = 1
            next
        }
        reading_slot && /^[[:space:]]*Size:/ {
            if ($0 !~ /Empty/) {
                used++
            }
            reading_slot = 0
        }
        END { print total + 0, used + 0 }
    ' <<< "$memory_profile")
    read -r RAM_SLOTS_TOTAL RAM_SLOTS_USED <<< "$slot_counts"

    if [[ "$OS_ARCH" == 'arm64' ]]; then
        if [[ "$RAM_TYPE" == 'Unknown' ]]; then
            RAM_TYPE='Unified'
        fi
        RAM_SLOTS_TOTAL=0
        RAM_SLOTS_USED=0
        if [[ "$RAM_SPEED_MHZ" == 'null' ]]; then
            RAM_SPEED_MHZ=$(apple_silicon_memory_speed "$CPU_MODEL")
        fi
    elif [[ "$RAM_SLOTS_TOTAL" == '0' ]]; then
        RAM_SLOTS_TOTAL='null'
        RAM_SLOTS_USED='null'
    fi

    local data_volume='/System/Volumes/Data'
    local disk_blocks_total
    local disk_blocks_free
    local disk_blocks_used
    local disk_fields
    [[ -d "$data_volume" ]] || data_volume='/'
    disk_fields=$(df -kP "$data_volume" 2>/dev/null | awk 'NR == 2 { print $2, $4 }' || true)
    read -r disk_blocks_total disk_blocks_free <<< "$disk_fields"

    DISK_TOTAL_GB='null'
    DISK_USED_GB='null'
    DISK_FREE_GB='null'
    DISK_USAGE_PCT='null'
    if [[ "${disk_blocks_total:-}" =~ ^[0-9]+$ && "${disk_blocks_free:-}" =~ ^[0-9]+$ && "$disk_blocks_total" -gt 0 ]]; then
        disk_blocks_used=$((disk_blocks_total - disk_blocks_free))
        DISK_TOTAL_GB=$(awk -v kib="$disk_blocks_total" 'BEGIN { printf "%.0f", kib / 1048576 }')
        DISK_USED_GB=$(awk -v kib="$disk_blocks_used" 'BEGIN { printf "%.0f", kib / 1048576 }')
        DISK_FREE_GB=$(awk -v kib="$disk_blocks_free" 'BEGIN { printf "%.0f", kib / 1048576 }')
        DISK_USAGE_PCT=$(awk -v used="$disk_blocks_used" -v total="$disk_blocks_total" \
            'BEGIN { printf "%.0f", used * 100 / total }')
    fi

    local storage_profile
    local disk_medium
    local disk_protocol
    storage_profile=$(system_profiler SPStorageDataType 2>/dev/null || true)
    DISK_MODEL=$(profiler_value "$storage_profile" 'Device Name')
    DISK_MODEL="${DISK_MODEL:-Unknown}"
    disk_medium=$(profiler_value "$storage_profile" 'Medium Type')
    disk_protocol=$(profiler_value "$storage_profile" 'Protocol')
    DISK_TYPE='Unknown'
    case "$disk_protocol $disk_medium" in
        *NVMe*|*NVMExpress*)              DISK_TYPE='NVMe' ;;
        *Solid*|*SSD*)                    DISK_TYPE='SSD' ;;
        *Rotational*|*HDD*|*Hard\ Disk*) DISK_TYPE='HDD' ;;
    esac
    if [[ "$OS_ARCH" == 'arm64' && "$DISK_TYPE" == 'Unknown' ]]; then
        DISK_TYPE='NVMe'
    fi

    DISK_REALLOCATED='null'
    DISK_POWER_ON_HOURS='null'
    if command -v smartctl >/dev/null 2>&1; then
        local smart_output
        smart_output=$(smartctl -a /dev/disk0 2>/dev/null || true)
        DISK_POWER_ON_HOURS=$(awk '
            /Power On Hours/ {
                for (i = NF; i > 0; i--) {
                    value = $i
                    gsub(/,/, "", value)
                    if (value ~ /^[0-9]+$/) {
                        print value
                        exit
                    }
                }
            }
        ' <<< "$smart_output")
        DISK_POWER_ON_HOURS="${DISK_POWER_ON_HOURS:-null}"
        DISK_REALLOCATED=$(awk '
            /Reallocated_Sector_Ct|Media and Data Integrity Errors/ {
                for (i = NF; i > 0; i--) {
                    if ($i ~ /^[0-9]+$/) {
                        print $i
                        exit
                    }
                }
            }
        ' <<< "$smart_output")
        DISK_REALLOCATED="${DISK_REALLOCATED:-null}"
    fi

    local smart_status
    smart_status=$(diskutil info /dev/disk0 2>/dev/null | awk -F: '
        /SMART Status/ {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' || true)
    case "$smart_status" in
        Verified) DISK_HEALTH='Good' ;;
        Failing)  DISK_HEALTH='Bad' ;;
        *)        DISK_HEALTH='Unknown' ;;
    esac

    local network_interface
    network_interface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }' || true)
    MAC_ADDRESS='Unknown'
    IP_ADDRESS='Unknown'
    if [[ -n "$network_interface" ]]; then
        MAC_ADDRESS=$(ifconfig "$network_interface" 2>/dev/null | awk '/ether/ { print $2; exit }' || true)
        MAC_ADDRESS="${MAC_ADDRESS:-Unknown}"
        IP_ADDRESS=$(ipconfig getifaddr "$network_interface" 2>/dev/null || true)
        if [[ -z "$IP_ADDRESS" ]]; then
            IP_ADDRESS=$(ifconfig "$network_interface" 2>/dev/null | awk '/inet / { print $2; exit }' || true)
        fi
        IP_ADDRESS="${IP_ADDRESS:-Unknown}"
    fi

    local displays_profile
    local builtin_display_size
    local display_rows_output
    displays_profile=$(system_profiler SPDisplaysDataType 2>/dev/null || true)
    builtin_display_size=$(builtin_display_size_for "$MODEL_ID")
    display_rows_output=$(display_rows "$displays_profile")
    DISPLAYS_JSON=$(displays_json "$display_rows_output" "$builtin_display_size")

    BATTERY_PRESENT='false'
    BATTERY_HEALTH_PCT='null'
    if pmset -g batt 2>/dev/null | grep -q 'Battery'; then
        local battery_profile_json
        local battery_registry
        BATTERY_PRESENT='true'
        battery_profile_json=$(system_profiler -json SPPowerDataType 2>/dev/null || true)
        battery_registry=$(ioreg -r -c AppleSmartBattery 2>/dev/null || true)
        BATTERY_HEALTH_PCT=$(battery_health_percentage "$battery_profile_json" "$battery_registry")
    fi

    ANTIVIRUS='None detected'
    local antivirus_candidates=(
        '/Applications/Moonlock.app|Moonlock (MacPaw)'
        '/Library/Application Support/Moonlock|Moonlock (MacPaw)'
        '/Applications/CleanMyMac.app|CleanMyMac + Moonlock Engine'
        '/Applications/CleanMyMac X.app|CleanMyMac X'
        '/Applications/Malwarebytes.app|Malwarebytes'
        '/Applications/Bitdefender.app|Bitdefender'
        '/Applications/Norton 360.app|Norton 360'
        '/Applications/Avast.app|Avast'
        '/Applications/AVG AntiVirus.app|AVG'
        '/Applications/ESET Cyber Security.app|ESET'
        '/Applications/Intego|Intego'
        '/Applications/Microsoft Defender.app|Microsoft Defender'
        '/Applications/Sophos|Sophos'
        '/Applications/CrowdStrike|CrowdStrike'
        '/Applications/Falcon.app|CrowdStrike Falcon'
        '/Applications/SentinelOne|SentinelOne'
        '/Library/Sentinel|SentinelOne'
        '/Applications/Carbon Black|Carbon Black'
    )
    local candidate
    local antivirus_path
    for candidate in "${antivirus_candidates[@]}"; do
        antivirus_path="${candidate%%|*}"
        if [[ -d "$antivirus_path" ]]; then
            ANTIVIRUS="${candidate#*|}"
            break
        fi
    done
    if [[ "$ANTIVIRUS" == 'None detected' ]] && command -v clamscan >/dev/null 2>&1; then
        ANTIVIRUS='ClamAV'
    fi

    ENCRYPTION_ENABLED='false'
    if fdesetup status 2>/dev/null | grep -q 'FileVault is On'; then
        ENCRYPTION_ENABLED='true'
    fi

    local firewall_tool='/usr/libexec/ApplicationFirewall/socketfilterfw'
    local firewall_output=''
    local stealth_output=''
    local firewall_preference=''
    local stealth_preference=''
    FIREWALL_ENABLED='null'
    FIREWALL_STEALTH_MODE='null'
    if [[ -x "$firewall_tool" ]]; then
        firewall_output=$("$firewall_tool" --getglobalstate 2>/dev/null || true)
        stealth_output=$("$firewall_tool" --getstealthmode 2>/dev/null || true)
        FIREWALL_ENABLED=$(firewall_state_from_output "$firewall_output")
        FIREWALL_STEALTH_MODE=$(stealth_state_from_output "$stealth_output")
    fi

    if [[ "$FIREWALL_ENABLED" == 'null' ]]; then
        firewall_preference=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || true)
        case "$firewall_preference" in
            0)   FIREWALL_ENABLED='false' ;;
            1|2) FIREWALL_ENABLED='true' ;;
        esac
    fi
    if [[ "$FIREWALL_STEALTH_MODE" == 'null' ]]; then
        stealth_preference=$(defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null || true)
        case "$stealth_preference" in
            0) FIREWALL_STEALTH_MODE='false' ;;
            1) FIREWALL_STEALTH_MODE='true' ;;
        esac
    fi

    LAST_OS_UPDATE=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate LastSuccessfulDate 2>/dev/null | awk '{ print $1; exit }' || true)
    LAST_OS_UPDATE="${LAST_OS_UPDATE:-Unknown}"

    local timestamp
    local output_file
    local json_payload
    timestamp=$(date '+%Y%m%d-%H%M%S')
    output_file="${PWD}/mac_inventory_${timestamp}.json"
    json_payload=$(emit_inventory_json)

    if ! (umask 077; set -o noclobber; printf '%s\n' "$json_payload" > "$output_file"); then
        die "Could not write inventory to $output_file"
    fi

    log 'Collection complete.'
    print_human_summary "$output_file" "$display_rows_output" "$builtin_display_size"
}

main "$@"
