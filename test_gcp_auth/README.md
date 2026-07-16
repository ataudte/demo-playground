# test_gcp_auth.sh

## Description

Tests Google Cloud service account authentication without using the Google Cloud CLI.

The script creates and signs a JWT, exchanges it for an OAuth 2.0 access token, and can optionally test access to:

* Cloud DNS managed zones
* Cloud DNS record sets
* Compute Engine VPC networks

## Usage

```bash
chmod +x test_gcp_auth.sh
./test_gcp_auth.sh [options] SERVICE_ACCOUNT_KEY.json
```

Examples:

```bash
# Test authentication
./test_gcp_auth.sh service-account.json

# Show detailed connection diagnostics
./test_gcp_auth.sh --verbose service-account.json

# List Cloud DNS managed zones
./test_gcp_auth.sh --list-zones --project my-project service-account.json

# List records in a managed zone
./test_gcp_auth.sh --dns-test --project my-project --zone example-zone service-account.json

# List VPC networks
./test_gcp_auth.sh --list-vpcs --project my-project service-account.json

# List Cloud DNS zones and VPC networks
./test_gcp_auth.sh --inventory --project my-project service-account.json
```

Available options:

```text
--scope SCOPE   OAuth scope to request
--verbose       Show request, TLS, and timing diagnostics
--show-token    Print the access token on success
--dns-test      Test Cloud DNS access and list managed zones
--list-zones    List all Cloud DNS managed zones
--list-vpcs     List all Compute Engine VPC networks
--inventory     List Cloud DNS zones and VPC networks
--project ID    Project used for Cloud DNS and VPC requests
--zone NAME     List records in the specified managed zone
-h, --help      Show help
```

## Requirements

* POSIX compatible shell
* `curl`
* `jq`
* `openssl`
* `date`
* `mktemp`
* `tr`
* `sed`
* `awk`

The Google Cloud CLI is not required.

## Service Account JSON File

The required JSON file is a private key for a Google Cloud service account.

It is created in the Google Cloud Console:

1. Open **IAM & Admin**.
2. Open **Service Accounts**.
3. Select or create a service account.
4. Open the **Keys** tab.
5. Select **Add key**, **Create new key**, and **JSON**.
6. Store the downloaded file securely.

The file may also be supplied by an administrator through an approved secrets management process.

The script uses the following fields:

* `client_email` as the JWT issuer
* `private_key` to sign the JWT
* `private_key_id` to identify the signing key
* `token_uri` as the OAuth token endpoint
* `project_id` as the default project for inventory requests
* `type` to verify that the file is a service account key

The JSON file contains a private key. Do not commit it to the repository.

Recommended file permissions:

```bash
chmod 600 service-account.json
```

## Input / Output

Input:

* Google Cloud service account key in JSON format
* Optional project, zone, scope, and diagnostic parameters

Output:

* Authentication result
* HTTP status and remote address
* DNS, TCP, TLS, and total request timings
* Token type and expiration time
* Optional Cloud DNS or VPC inventory in tab separated format

The access token is hidden unless `--show-token` is used.

Example output redirection:

```bash
./test_gcp_auth.sh --list-zones service-account.json > zones.tsv
```

## Notes

* Accurate system time is required for JWT validation.
* Authentication does not automatically confirm access to Cloud DNS or Compute Engine.
* The service account requires the relevant IAM permissions.
* The corresponding Google Cloud APIs must be enabled.
* Use `--show-token` only in controlled troubleshooting sessions.
* Temporary private key files are removed when the script exits.

## License

This script is covered under the repository's main [MIT License](../LICENSE).
