Put .env and configure-services.sh in the same directory.

🚀 Usage Examples:
# Quick setup with all services using auto-detected network
sudo ./configure-services.sh --services all

# Use custom .env file
sudo ./configure-services.sh --env-file production.env --services all

# Dry run to see what would be configured
sudo ./configure-services.sh --dry-run --services all

# Configure only NFS with custom path
sudo ./configure-services.sh --enable-nfs --nfs-export-path /shared

The script is now optimized for your environment with smart auto-detection and the specific requirements you requested!