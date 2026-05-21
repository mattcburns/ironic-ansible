#!/bin/bash
# =============================================================================
# Ironic Python Agent (IPA) Image Downloader
# =============================================================================
# This script downloads IPA images from the official metal3-io repository.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IPA_BASE_URL="${IPA_BASE_URL:-https://storage.googleapis.com/opendev.org/x/project-openstack/openstack-ironic-ipa-qemustable}"
IPA_IMAGES_DIR="${IPA_IMAGES_DIR:-/var/lib/ironic/http-images/ipa}"
IPA_IMAGES=(
    "ironic-python-agent.iso"
    "ironic-python-agent.kernel"
    "ironic-python-agent.ramdisk"
    "ironic-python-agent.vmlinuz"
    "ironic-python-agentinitramfs"
)

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create IPA images directory
setup_directory() {
    if [ ! -d "$IPA_IMAGES_DIR" ]; then
        log "Creating IPA images directory: $IPA_IMAGES_DIR"
        mkdir -p "$IPA_IMAGES_DIR"
        chmod 755 "$IPA_IMAGES_DIR"
    else
        log "IPA images directory already exists: $IPA_IMAGES_DIR"
    fi
}

# Download a single file
download_file() {
    local filename="$1"
    local source_url="${IPA_BASE_URL}/${filename}"
    local dest_path="${IPA_IMAGES_DIR}/${filename}"

    log "Downloading ${filename}..."

    # Check if file exists and is recent (within 24 hours)
    if [ -f "$dest_path" ]; then
        local file_age=$(( $(date +%s) - $(stat -c %Y "$dest_path") ))
        if [ $file_age -lt 86400 ]; then
            log "File ${filename} is recent, skipping download"
            return 0
        else
            log_warn "File ${filename} is outdated, re-downloading"
        fi
    fi

    # Download with retry logic
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if curl -sSL -o "$dest_path" "$source_url"; then
            if [ -s "$dest_path" ]; then
                log "Successfully downloaded ${filename}"
                chmod 644 "$dest_path"
                return 0
            fi
        fi

        retry_count=$((retry_count + 1))
        log_warn "Download attempt ${retry_count} failed for ${filename}"

        if [ $retry_count -lt $max_retries ]; then
            sleep 2
        fi
    done

    log_error "Failed to download ${filename} after ${max_retries} attempts"
    return 1
}

# Verify downloads
verify_downloads() {
    log "Verifying downloaded files..."

    local missing_files=0

    for image in "${IPA_IMAGES[@]}"; do
        local file_path="${IPA_IMAGES_DIR}/${image}"

        if [ ! -f "$file_path" ]; then
            log_error "Missing file: ${file_path}"
            missing_files=$((missing_files + 1))
        elif [ ! -s "$file_path" ]; then
            log_error "Empty file: ${file_path}"
            missing_files=$((missing_files + 1))
        else
            local file_size=$(stat -c %s "$file_path")
            log "File ${image} verified (${file_size} bytes)"
        fi
    done

    if [ $missing_files -gt 0 ]; then
        log_error "${missing_files} files are missing or empty"
        return 1
    fi

    log "All files verified successfully"
    return 0
}

# List available files
list_files() {
    log "IPA images in ${IPA_IMAGES_DIR}:"
    ls -lh "$IPA_IMAGES_DIR" 2>/dev/null || echo "No images found"
}

# Main function
main() {
    log "Starting IPA image downloader..."

    # Setup
    setup_directory

    # Download images
    for image in "${IPA_IMAGES[@]}"; do
        download_file "$image" || true
    done

    # Verify
    verify_downloads

    # List results
    list_files

    log "IPA image downloader completed"
}

# Run main function
main "$@"
