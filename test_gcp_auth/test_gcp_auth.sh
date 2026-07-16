#!/bin/sh

# Test and troubleshoot Google Cloud service account authentication.
# The script creates and signs a JWT, exchanges it for an OAuth access token,
# and can optionally verify access to Cloud DNS managed zones, DNS records,
# and Compute Engine VPC networks.
# POSIX sh compatible.
# Required commands: curl, jq, openssl, date, mktemp, tr, sed, awk.
# The access token is redacted by default. Use --show-token only when needed.

set -eu

PROGRAM=${0##*/}
DEFAULT_SCOPE='https://www.googleapis.com/auth/cloud-platform'
SCOPE=$DEFAULT_SCOPE
VERBOSE=0
SHOW_TOKEN=0
DNS_TEST=0
LIST_ZONES=0
LIST_VPCS=0
DNS_PROJECT=''
DNS_ZONE=''
KEYFILE=''
TMPDIR_PATH=''

usage() {
    cat <<USAGE
Usage: $PROGRAM [options] SERVICE_ACCOUNT_KEY.json

Options:
  --scope SCOPE   OAuth scope to request
                  Default: $DEFAULT_SCOPE
  --verbose       Show request, TLS, and timing diagnostics
  --show-token    Print the access token on success
  --dns-test      Test Cloud DNS access and list managed zones
  --list-zones    List all Cloud DNS managed zones
  --list-vpcs     List all Compute Engine VPC networks
  --inventory     List both Cloud DNS zones and VPC networks
  --project ID    Project to use for the Cloud DNS test
                  Default: project_id from the key file
  --zone NAME     Also test listing records in this managed zone
  -h, --help      Show this help

Examples:
  $PROGRAM service-account.json
  $PROGRAM --verbose service-account.json
  $PROGRAM --scope 'https://www.googleapis.com/auth/dns.readonly' service-account.json
  $PROGRAM --list-zones --project my-project service-account.json
  $PROGRAM --list-vpcs --project my-project service-account.json
  $PROGRAM --inventory --project my-project service-account.json
  $PROGRAM --dns-test --project my-project --zone example-zone service-account.json
USAGE
}

log()  { printf '%s\n' "[INFO] $*" >&2; }
warn() { printf '%s\n' "[WARN] $*" >&2; }
fail() { printf '%s\n' "[FAIL] $*" >&2; exit "${2:-1}"; }

cleanup() {
    if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
        rm -rf "$TMPDIR_PATH"
    fi
}
trap cleanup EXIT HUP INT TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1" 10
}

json_field() {
    field=$1
    jq -er ".${field} | select(type == \"string\" and length > 0)" "$KEYFILE" 2>/dev/null ||
        fail "Missing or invalid JSON field: ${field}" 12
}

b64url_file() {
    openssl base64 -A < "$1" | tr '+/' '-_' | tr -d '='
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --scope)
            [ "$#" -ge 2 ] || fail "--scope requires a value" 2
            SCOPE=$2
            shift 2
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --show-token)
            SHOW_TOKEN=1
            shift
            ;;
        --dns-test)
            DNS_TEST=1
            LIST_ZONES=1
            shift
            ;;
        --list-zones)
            DNS_TEST=1
            LIST_ZONES=1
            shift
            ;;
        --list-vpcs)
            LIST_VPCS=1
            shift
            ;;
        --inventory)
            DNS_TEST=1
            LIST_ZONES=1
            LIST_VPCS=1
            shift
            ;;
        --project)
            [ "$#" -ge 2 ] || fail "--project requires a value" 2
            DNS_PROJECT=$2
            shift 2
            ;;
        --zone)
            [ "$#" -ge 2 ] || fail "--zone requires a value" 2
            DNS_ZONE=$2
            DNS_TEST=1
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            fail "Unknown option: $1" 2
            ;;
        *)
            [ -z "$KEYFILE" ] || fail "Only one key file may be specified" 2
            KEYFILE=$1
            shift
            ;;
    esac
done

[ -n "$KEYFILE" ] || { usage >&2; exit 2; }
[ -f "$KEYFILE" ] || fail "Key file not found: $KEYFILE" 11
[ -r "$KEYFILE" ] || fail "Key file is not readable: $KEYFILE" 11
[ -n "$SCOPE" ] || fail "OAuth scope must not be empty" 2

for command_name in curl jq openssl date mktemp tr sed awk; do
    require_command "$command_name"
done

jq -e . "$KEYFILE" >/dev/null 2>&1 || fail "Key file is not valid JSON" 12

KEY_TYPE=$(jq -r '.type // empty' "$KEYFILE")
[ "$KEY_TYPE" = 'service_account' ] || fail "Expected a service_account key, found type: ${KEY_TYPE:-<missing>}" 12

EMAIL=$(json_field client_email)
KEY_ID=$(json_field private_key_id)
TOKEN_URI=$(json_field token_uri)
PROJECT_ID=$(jq -r '.project_id // empty' "$KEYFILE")
[ -n "$DNS_PROJECT" ] || DNS_PROJECT=$PROJECT_ID
if { [ "$DNS_TEST" -eq 1 ] || [ "$LIST_VPCS" -eq 1 ]; } && [ -z "$DNS_PROJECT" ]; then
    fail "Cloud inventory tests require --project or a project_id in the key file" 2
fi

case $TOKEN_URI in
    https://*) ;;
    *) fail "token_uri must use HTTPS: $TOKEN_URI" 12 ;;
esac

TMPDIR_PATH=$(mktemp -d "${TMPDIR:-/tmp}/gcp-auth.XXXXXX") || fail "Could not create temporary directory" 13
chmod 700 "$TMPDIR_PATH"
PRIVATE_KEY_FILE=$TMPDIR_PATH/private-key.pem
HEADER_JSON=$TMPDIR_PATH/header.json
CLAIMS_JSON=$TMPDIR_PATH/claims.json
SIGNING_INPUT=$TMPDIR_PATH/signing-input.txt
SIGNATURE_FILE=$TMPDIR_PATH/signature.bin
RESPONSE_BODY=$TMPDIR_PATH/response.json
RESPONSE_HEADERS=$TMPDIR_PATH/response.headers
CURL_DIAGNOSTICS=$TMPDIR_PATH/curl.stderr
DNS_RESPONSE_BODY=$TMPDIR_PATH/dns-response.json
DNS_CURL_DIAGNOSTICS=$TMPDIR_PATH/dns-curl.stderr
VPC_RESPONSE_BODY=$TMPDIR_PATH/vpc-response.json
VPC_CURL_DIAGNOSTICS=$TMPDIR_PATH/vpc-curl.stderr

umask 077
jq -er '.private_key | select(type == "string" and length > 0)' "$KEYFILE" > "$PRIVATE_KEY_FILE" 2>/dev/null ||
    fail "Missing or invalid JSON field: private_key" 12

openssl pkey -in "$PRIVATE_KEY_FILE" -noout -check >/dev/null 2>"$TMPDIR_PATH/key-check.stderr" || {
    warn "OpenSSL rejected the private key"
    sed 's/^/       /' "$TMPDIR_PATH/key-check.stderr" >&2
    exit 14
}

NOW=$(date +%s) || fail "Could not read system time" 15
EXP=$((NOW + 3600))
NOW_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s' "$NOW")

jq -cn --arg kid "$KEY_ID" '{alg:"RS256",typ:"JWT",kid:$kid}' > "$HEADER_JSON"
jq -cn \
    --arg iss "$EMAIL" \
    --arg scope "$SCOPE" \
    --arg aud "$TOKEN_URI" \
    --argjson iat "$NOW" \
    --argjson exp "$EXP" \
    '{iss:$iss,scope:$scope,aud:$aud,iat:$iat,exp:$exp}' > "$CLAIMS_JSON"

HEADER=$(b64url_file "$HEADER_JSON")
CLAIMS=$(b64url_file "$CLAIMS_JSON")
printf '%s.%s' "$HEADER" "$CLAIMS" > "$SIGNING_INPUT"

openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" -out "$SIGNATURE_FILE" "$SIGNING_INPUT" 2>"$TMPDIR_PATH/sign.stderr" || {
    warn "JWT signing failed"
    sed 's/^/       /' "$TMPDIR_PATH/sign.stderr" >&2
    exit 16
}

SIGNATURE=$(b64url_file "$SIGNATURE_FILE")
JWT="${HEADER}.${CLAIMS}.${SIGNATURE}"

log "Service account: $EMAIL"
[ -n "$PROJECT_ID" ] && log "Project: $PROJECT_ID"
log "Key ID: $KEY_ID"
log "Token endpoint: $TOKEN_URI"
log "Requested scope: $SCOPE"
log "Local UTC time: $NOW_UTC"

CURL_VERBOSE=''
[ "$VERBOSE" -eq 1 ] && CURL_VERBOSE='-v'

# curl exit status and HTTP status are handled separately so network and OAuth
# failures are distinguishable.
set +e
# shellcheck disable=SC2086
HTTP_RESULT=$(curl $CURL_VERBOSE \
    --silent --show-error \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 1 \
    --retry-delay 1 \
    --retry-connrefused \
    --dump-header "$RESPONSE_HEADERS" \
    --output "$RESPONSE_BODY" \
    --write-out '%{http_code} %{remote_ip} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_total}' \
    --request POST \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Accept: application/json' \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
    --data-urlencode "assertion=${JWT}" \
    "$TOKEN_URI" 2>"$CURL_DIAGNOSTICS")
CURL_STATUS=$?
set -e

if [ "$VERBOSE" -eq 1 ] && [ -s "$CURL_DIAGNOSTICS" ]; then
    printf '\n[CURL]\n' >&2
    # Redact the JWT if curl happens to print request data.
    sed "s/${JWT}/<redacted-jwt>/g; s/^/       /" "$CURL_DIAGNOSTICS" >&2
fi

set -- $HTTP_RESULT
HTTP_STATUS=${1:-000}
REMOTE_IP=${2:--}
DNS_TIME=${3:--}
CONNECT_TIME=${4:--}
TLS_TIME=${5:--}
TOTAL_TIME=${6:--}

if [ "$CURL_STATUS" -ne 0 ]; then
    warn "Network or TLS request failed (curl exit $CURL_STATUS)"
    [ -s "$CURL_DIAGNOSTICS" ] && sed 's/^/       /' "$CURL_DIAGNOSTICS" >&2
    case $CURL_STATUS in
        6)  warn "DNS resolution failed for the token endpoint" ;;
        7)  warn "TCP connection to the token endpoint failed" ;;
        28) warn "The request timed out" ;;
        35|51|58|60|77|80|82|83|90|91) warn "TLS or certificate validation failed" ;;
    esac
    exit 20
fi

log "HTTP status: $HTTP_STATUS"
log "Remote IP: $REMOTE_IP"
log "Timing seconds: DNS=$DNS_TIME connect=$CONNECT_TIME TLS=$TLS_TIME total=$TOTAL_TIME"

if [ "$VERBOSE" -eq 1 ]; then
    printf '\n[RESPONSE HEADERS]\n' >&2
    sed 's/^/       /' "$RESPONSE_HEADERS" >&2
fi

if [ "$HTTP_STATUS" -ge 200 ] 2>/dev/null && [ "$HTTP_STATUS" -lt 300 ] 2>/dev/null; then
    jq -e '.access_token and .token_type and .expires_in' "$RESPONSE_BODY" >/dev/null 2>&1 || {
        warn "Token endpoint returned HTTP $HTTP_STATUS but the response is incomplete"
        jq . "$RESPONSE_BODY" 2>/dev/null || cat "$RESPONSE_BODY"
        exit 22
    }

    TOKEN_TYPE=$(jq -r '.token_type' "$RESPONSE_BODY")
    EXPIRES_IN=$(jq -r '.expires_in' "$RESPONSE_BODY")
    ACCESS_TOKEN=$(jq -r '.access_token' "$RESPONSE_BODY")
    log "Authentication succeeded"
    printf 'token_type=%s\nexpires_in=%s\n' "$TOKEN_TYPE" "$EXPIRES_IN"
    if [ "$SHOW_TOKEN" -eq 1 ]; then
        printf 'access_token=%s\n' "$ACCESS_TOKEN"
    else
        printf 'access_token=<redacted; use --show-token to display>\n'
    fi

    INVENTORY_FAILED=0

    if [ "$DNS_TEST" -eq 1 ]; then
        DNS_PATH="projects/${DNS_PROJECT}/managedZones"
        DNS_LABEL="managed zones in project ${DNS_PROJECT}"
        if [ -n "$DNS_ZONE" ]; then
            DNS_PATH="projects/${DNS_PROJECT}/managedZones/${DNS_ZONE}/rrsets"
            DNS_LABEL="record sets in zone ${DNS_ZONE}"
        fi
        DNS_URL="https://dns.googleapis.com/dns/v1/${DNS_PATH}"
        log "Testing Cloud DNS access: $DNS_LABEL"

        set +e
        DNS_HTTP_RESULT=$(curl \
            --silent --show-error \
            --connect-timeout 10 \
            --max-time 30 \
            --retry 1 \
            --retry-delay 1 \
            --retry-connrefused \
            --output "$DNS_RESPONSE_BODY" \
            --write-out '%{http_code} %{remote_ip} %{time_total}' \
            --header "Authorization: Bearer ${ACCESS_TOKEN}" \
            --header 'Accept: application/json' \
            "$DNS_URL" 2>"$DNS_CURL_DIAGNOSTICS")
        DNS_CURL_STATUS=$?
        set -e

        set -- $DNS_HTTP_RESULT
        DNS_HTTP_STATUS=${1:-000}
        DNS_REMOTE_IP=${2:--}
        DNS_TOTAL_TIME=${3:--}

        if [ "$DNS_CURL_STATUS" -ne 0 ]; then
            warn "Cloud DNS request failed (curl exit $DNS_CURL_STATUS)"
            [ -s "$DNS_CURL_DIAGNOSTICS" ] && sed 's/^/       /' "$DNS_CURL_DIAGNOSTICS" >&2
            INVENTORY_FAILED=1
        elif [ "$DNS_HTTP_STATUS" -ge 200 ] 2>/dev/null && [ "$DNS_HTTP_STATUS" -lt 300 ] 2>/dev/null; then
            log "Cloud DNS HTTP status: $DNS_HTTP_STATUS"
            log "Cloud DNS remote IP: $DNS_REMOTE_IP"
            log "Cloud DNS total time: ${DNS_TOTAL_TIME}s"
            if [ -n "$DNS_ZONE" ]; then
                DNS_COUNT=$(jq '.rrsets | length' "$DNS_RESPONSE_BODY" 2>/dev/null || printf '?')
                log "Cloud DNS record-set access succeeded (${DNS_COUNT} record sets returned)"
                jq -r '(["NAME","TYPE","TTL","DATA"], (.rrsets[]? | [.name, .type, (.ttl|tostring), (.rrdatas|join(", "))])) | @tsv' "$DNS_RESPONSE_BODY"
            else
                DNS_COUNT=$(jq '.managedZones | length' "$DNS_RESPONSE_BODY" 2>/dev/null || printf '?')
                log "Cloud DNS managed-zone access succeeded (${DNS_COUNT} zones returned)"
                jq -r '(["ZONE","DNS_NAME","VISIBILITY","DESCRIPTION"], (.managedZones[]? | [.name, .dnsName, (.visibility // "public"), (.description // "")])) | @tsv' "$DNS_RESPONSE_BODY"
            fi
            printf 'cloud_dns_access=ok\ncloud_dns_http_status=%s\n' "$DNS_HTTP_STATUS" >&2
        else
            warn "Cloud DNS access failed (HTTP $DNS_HTTP_STATUS)"
            if jq -e . "$DNS_RESPONSE_BODY" >/dev/null 2>&1; then
                DNS_MESSAGE=$(jq -r '.error.message // "No error message returned"' "$DNS_RESPONSE_BODY")
                DNS_REASON=$(jq -r '.error.errors[0].reason // "unknown"' "$DNS_RESPONSE_BODY")
                printf 'cloud_dns_access=failed\ncloud_dns_http_status=%s\ncloud_dns_reason=%s\ncloud_dns_error=%s\n' \
                    "$DNS_HTTP_STATUS" "$DNS_REASON" "$DNS_MESSAGE" >&2
            else
                sed 's/^/       /' "$DNS_RESPONSE_BODY" >&2
            fi
            case $DNS_HTTP_STATUS in
                401) warn "The access token was rejected or expired" ;;
                403) warn "Check Cloud DNS API enablement and IAM permissions such as roles/dns.reader" ;;
                404) warn "Check the project ID and managed-zone name" ;;
            esac
            INVENTORY_FAILED=1
        fi
    fi

    if [ "$LIST_VPCS" -eq 1 ]; then
        VPC_URL="https://compute.googleapis.com/compute/v1/projects/${DNS_PROJECT}/global/networks"
        log "Testing Compute Engine network access and listing VPCs in project ${DNS_PROJECT}"

        set +e
        VPC_HTTP_RESULT=$(curl \
            --silent --show-error \
            --connect-timeout 10 \
            --max-time 30 \
            --retry 1 \
            --retry-delay 1 \
            --retry-connrefused \
            --output "$VPC_RESPONSE_BODY" \
            --write-out '%{http_code} %{remote_ip} %{time_total}' \
            --header "Authorization: Bearer ${ACCESS_TOKEN}" \
            --header 'Accept: application/json' \
            "$VPC_URL" 2>"$VPC_CURL_DIAGNOSTICS")
        VPC_CURL_STATUS=$?
        set -e

        set -- $VPC_HTTP_RESULT
        VPC_HTTP_STATUS=${1:-000}
        VPC_REMOTE_IP=${2:--}
        VPC_TOTAL_TIME=${3:--}

        if [ "$VPC_CURL_STATUS" -ne 0 ]; then
            warn "VPC request failed (curl exit $VPC_CURL_STATUS)"
            [ -s "$VPC_CURL_DIAGNOSTICS" ] && sed 's/^/       /' "$VPC_CURL_DIAGNOSTICS" >&2
            INVENTORY_FAILED=1
        elif [ "$VPC_HTTP_STATUS" -ge 200 ] 2>/dev/null && [ "$VPC_HTTP_STATUS" -lt 300 ] 2>/dev/null; then
            VPC_COUNT=$(jq '.items | length' "$VPC_RESPONSE_BODY" 2>/dev/null || printf '0')
            log "VPC access succeeded (${VPC_COUNT} networks returned)"
            log "Compute API remote IP: $VPC_REMOTE_IP"
            log "Compute API total time: ${VPC_TOTAL_TIME}s"
            jq -r '(["VPC","MODE","ROUTING_MODE","MTU","IPV6_MODE","DESCRIPTION"], (.items[]? | [.name, (if .autoCreateSubnetworks then "AUTO" else "CUSTOM" end), (.routingConfig.routingMode // "REGIONAL"), ((.mtu // 1460)|tostring), (.enableUlaInternalIpv6|tostring), (.description // "")])) | @tsv' "$VPC_RESPONSE_BODY"
            printf 'vpc_access=ok\nvpc_http_status=%s\n' "$VPC_HTTP_STATUS" >&2
        else
            warn "VPC access failed (HTTP $VPC_HTTP_STATUS)"
            if jq -e . "$VPC_RESPONSE_BODY" >/dev/null 2>&1; then
                VPC_MESSAGE=$(jq -r '.error.message // "No error message returned"' "$VPC_RESPONSE_BODY")
                VPC_REASON=$(jq -r '.error.errors[0].reason // "unknown"' "$VPC_RESPONSE_BODY")
                printf 'vpc_access=failed\nvpc_http_status=%s\nvpc_reason=%s\nvpc_error=%s\n' \
                    "$VPC_HTTP_STATUS" "$VPC_REASON" "$VPC_MESSAGE" >&2
            else
                sed 's/^/       /' "$VPC_RESPONSE_BODY" >&2
            fi
            case $VPC_HTTP_STATUS in
                401) warn "The access token was rejected or expired" ;;
                403) warn "Check Compute Engine API enablement and compute.networks.list permission" ;;
                404) warn "Check the project ID" ;;
            esac
            INVENTORY_FAILED=1
        fi
    fi

    [ "$INVENTORY_FAILED" -eq 0 ] || exit 31

    exit 0
fi

warn "Authentication failed"
if jq -e . "$RESPONSE_BODY" >/dev/null 2>&1; then
    ERROR_NAME=$(jq -r '.error // "unknown_error"' "$RESPONSE_BODY")
    ERROR_DESCRIPTION=$(jq -r '.error_description // .error.message // "No description returned"' "$RESPONSE_BODY")
    printf 'error=%s\nerror_description=%s\n' "$ERROR_NAME" "$ERROR_DESCRIPTION" >&2
else
    warn "Non-JSON response body:"
    sed 's/^/       /' "$RESPONSE_BODY" >&2
fi

case $(jq -r '.error_description // ""' "$RESPONSE_BODY" 2>/dev/null || true) in
    *'Invalid JWT Signature'*)
        warn "Check that private_key_id and private_key belong to the same active service-account key"
        ;;
    *'Token must be a short-lived token'*|*'iat'*|*'exp'*)
        warn "Check system time synchronization; JWT validity depends on accurate iat and exp timestamps"
        ;;
    *'Invalid grant'*|*'invalid_grant'*)
        warn "Check clock synchronization, key status, service-account identity, and token_uri"
        ;;
esac

exit 21
