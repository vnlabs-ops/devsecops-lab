#!/bin/bash

# ==== DNS HOOKS FOR LETSENCRYPT WILDCARD CERTIFICATES ====
# This script handles DNS challenge validation for Let's Encrypt certificates
# Supports: GCP Cloud DNS and AWS Route53
#
# Usage:
#   ./dns-hooks.sh auth <domain> <validation_token>
#   ./dns-hooks.sh cleanup <domain> <validation_token>
#
# Environment Variables Required:
# For GCP Cloud DNS:
#   - GCP_PROJECT_ID: Your GCP project ID
#   - GCP_ZONE_NAME: Your DNS zone name in Cloud DNS
#   - GOOGLE_APPLICATION_CREDENTIALS: Path to service account key file
#
# For AWS Route53:
#   - AWS_ACCESS_KEY_ID: Your AWS access key
#   - AWS_SECRET_ACCESS_KEY: Your AWS secret key
#   - AWS_DEFAULT_REGION: Your AWS region (e.g., us-east-1)
#   - AWS_HOSTED_ZONE_ID: Your Route53 hosted zone ID
#
# DNS_PROVIDER: Set to "gcp" or "aws"

set -e

# Configuration
DNS_PROVIDER="${DNS_PROVIDER:-}"
RECORD_NAME_PREFIX="_acme-challenge"
TTL=60
SLEEP_TIME=30

# Load environment from .env file if it exists
if [[ -f ".env" ]]; then
    source .env
fi

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to detect DNS provider if not set
detect_dns_provider() {
    if [[ -n "$GCP_PROJECT_ID" && -n "$GCP_ZONE_NAME" ]]; then
        DNS_PROVIDER="gcp"
        log "Auto-detected DNS provider: GCP Cloud DNS"
    elif [[ -n "$AWS_HOSTED_ZONE_ID" ]]; then
        DNS_PROVIDER="aws"
        log "Auto-detected DNS provider: AWS Route53"
    else
        log "ERROR: Cannot detect DNS provider. Please set DNS_PROVIDER environment variable."
        log "Required variables:"
        log "  For GCP: GCP_PROJECT_ID, GCP_ZONE_NAME"
        log "  For AWS: AWS_HOSTED_ZONE_ID"
        exit 1
    fi
}

# Function to validate dependencies
validate_dependencies() {
    case "$DNS_PROVIDER" in
        "gcp")
            if ! command -v gcloud &> /dev/null; then
                log "ERROR: gcloud CLI not found. Please install Google Cloud CLI:"
                log "  sudo dnf install -y google-cloud-cli"
                exit 1
            fi
            
            if [[ -z "$GCP_PROJECT_ID" || -z "$GCP_ZONE_NAME" ]]; then
                log "ERROR: Missing GCP configuration. Required variables:"
                log "  GCP_PROJECT_ID, GCP_ZONE_NAME"
                exit 1
            fi
            ;;
        "aws")
            if ! command -v aws &> /dev/null; then
                log "ERROR: AWS CLI not found. Please install AWS CLI:"
                log "  sudo dnf install -y awscli"
                exit 1
            fi
            
            if [[ -z "$AWS_HOSTED_ZONE_ID" ]]; then
                log "ERROR: Missing AWS configuration. Required variable:"
                log "  AWS_HOSTED_ZONE_ID"
                exit 1
            fi
            ;;
        *)
            log "ERROR: Unsupported DNS provider: $DNS_PROVIDER"
            log "Supported providers: gcp, aws"
            exit 1
            ;;
    esac
}

# Function to create DNS TXT record for GCP
gcp_create_record() {
    local domain="$1"
    local validation="$2"
    local record_name="${RECORD_NAME_PREFIX}.${domain}."
    
    log "Creating GCP Cloud DNS TXT record: $record_name"
    
    gcloud dns record-sets create "$record_name" \
        --project="$GCP_PROJECT_ID" \
        --zone="$GCP_ZONE_NAME" \
        --type="TXT" \
        --ttl="$TTL" \
        --rrdatas="\"$validation\"" \
        --quiet
    
    log "GCP DNS record created successfully"
}

# Function to delete DNS TXT record for GCP
gcp_delete_record() {
    local domain="$1"
    local validation="$2"
    local record_name="${RECORD_NAME_PREFIX}.${domain}."
    
    log "Deleting GCP Cloud DNS TXT record: $record_name"
    
    gcloud dns record-sets delete "$record_name" \
        --project="$GCP_PROJECT_ID" \
        --zone="$GCP_ZONE_NAME" \
        --type="TXT" \
        --quiet 2>/dev/null || true
    
    log "GCP DNS record deleted successfully"
}

# Function to create DNS TXT record for AWS
aws_create_record() {
    local domain="$1"
    local validation="$2"
    local record_name="${RECORD_NAME_PREFIX}.${domain}"
    
    log "Creating AWS Route53 TXT record: $record_name"
    
    local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "CREATE",
        "ResourceRecordSet": {
            "Name": "$record_name",
            "Type": "TXT",
            "TTL": $TTL,
            "ResourceRecords": [{"Value": "\"$validation\""}]
        }
    }]
}
EOF
)
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$AWS_HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --output text > /dev/null
    
    log "AWS Route53 record created successfully"
}

# Function to delete DNS TXT record for AWS
aws_delete_record() {
    local domain="$1"
    local validation="$2"
    local record_name="${RECORD_NAME_PREFIX}.${domain}"
    
    log "Deleting AWS Route53 TXT record: $record_name"
    
    local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
            "Name": "$record_name",
            "Type": "TXT",
            "TTL": $TTL,
            "ResourceRecords": [{"Value": "\"$validation\""}]
        }
    }]
}
EOF
)
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$AWS_HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --output text > /dev/null 2>/dev/null || true
    
    log "AWS Route53 record deleted successfully"
}

# Main function
main() {
    local action="$1"
    local domain="$2"
    local validation="$3"
    
    if [[ $# -ne 3 ]]; then
        echo "Usage: $0 <auth|cleanup> <domain> <validation_token>"
        echo ""
        echo "Environment Variables:"
        echo "  DNS_PROVIDER: 'gcp' or 'aws'"
        echo ""
        echo "For GCP Cloud DNS:"
        echo "  GCP_PROJECT_ID: Your GCP project ID"
        echo "  GCP_ZONE_NAME: Your DNS zone name"
        echo "  GOOGLE_APPLICATION_CREDENTIALS: Path to service account key"
        echo ""
        echo "For AWS Route53:"
        echo "  AWS_ACCESS_KEY_ID: Your AWS access key"
        echo "  AWS_SECRET_ACCESS_KEY: Your AWS secret key"
        echo "  AWS_DEFAULT_REGION: Your AWS region"
        echo "  AWS_HOSTED_ZONE_ID: Your Route53 hosted zone ID"
        exit 1
    fi
    
    # Auto-detect DNS provider if not set
    if [[ -z "$DNS_PROVIDER" ]]; then
        detect_dns_provider
    fi
    
    # Validate dependencies
    validate_dependencies
    
    case "$action" in
        "auth")
            log "Starting DNS challenge authentication for domain: $domain"
            case "$DNS_PROVIDER" in
                "gcp")
                    gcp_create_record "$domain" "$validation"
                    ;;
                "aws")
                    aws_create_record "$domain" "$validation"
                    ;;
            esac
            log "Waiting $SLEEP_TIME seconds for DNS propagation..."
            sleep $SLEEP_TIME
            log "DNS challenge authentication completed"
            ;;
        "cleanup")
            log "Starting DNS challenge cleanup for domain: $domain"
            case "$DNS_PROVIDER" in
                "gcp")
                    gcp_delete_record "$domain" "$validation"
                    ;;
                "aws")
                    aws_delete_record "$domain" "$validation"
                    ;;
            esac
            log "DNS challenge cleanup completed"
            ;;
        *)
            log "ERROR: Invalid action: $action. Use 'auth' or 'cleanup'"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
