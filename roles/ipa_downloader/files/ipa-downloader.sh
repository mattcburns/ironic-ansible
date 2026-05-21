#!/bin/bash
# =============================================================================
# Ironic Python Agent (IPA) Image Downloader
# =============================================================================
# Downloads IPA kernel and initramfs from upstream OpenStack.
# =============================================================================

set -euo pipefail

# Configuration (overridable via environment)
IPA_BASE_URL="${IPA_BASE_URL:-https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files}"
IPA_IMAGES_DIR="${IPA_IMAGES_DIR:-/var/lib/ironic/http-images/ipa}"
IPA_KERNEL="${IPA_KERNEL:-ipa-centos9-master.kernel}"
IPA_RAMDISK="${IPA_RAMDISK:-ipa-centos9-master.initramfs}"

IPA_FILES=("$IPA_KERNEL" "$IPA_RAMDISK")

log()      { echo "[INFO]  $1"; }
log_warn() { echo "[WARN]  $1"; }
log_error(){ echo "[ERROR] $1"; }

setup_directory() {
    if [ ! -d "$IPA_IMAGES_DIR" ]; then
        log "Creating IPA images directory: $IPA_IMAGES_DIR"
        mkdir -p "$IPA_IMAGES_DIR"
        chmod 755 "$IPA_IMAGES_DIR"
    fi
}

download_file() {
    local filename="$1"
    local source_url="${IPA_BASE_URL}/${filename}"
    local dest_path="${IPA_IMAGES_DIR}/${filename}"

    # Skip if file exists and is less than 24 hours old
    if [ -f "$dest_path" ]; then
        local file_age=$(( $(date +%s) - $(stat -c %Y "$dest_path") ))
        if [ $file_age -lt 86400 ]; then
            log "File ${filename} is recent, skipping download"
            return 0
        fi
    fi

    log "Downloading ${filename} from ${source_url}..."

    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if curl -sSL --fail -o "$dest_path" "$source_url"; then
            if [ -s "$dest_path" ]; then
                log "Successfully downloaded ${filename}"
                chmod 644 "$dest_path"
                return 0
            fi
        fi

        retry_count=$((retry_count + 1))
        log_warn "Download attempt ${retry_count} failed for ${filename}"
        [ $retry_count -lt $max_retries ] && sleep 5
    done

    log_error "Failed to download ${filename} after ${max_retries} attempts"
    return 1
}

verify_downloads() {
    log "Verifying downloaded files..."
    local missing=0

    for f in "${IPA_FILES[@]}"; do
        local path="${IPA_IMAGES_DIR}/${f}"
        if [ ! -f "$path" ] || [ ! -s "$path" ]; then
            log_error "Missing or empty: ${path}"
            missing=$((missing + 1))
        else
            local size=$(stat -c %s "$path")
            log "Verified ${f} (${size} bytes)"
        fi
    done

    [ $missing -gt 0 ] && return 1
    log "All IPA files verified successfully"
    return 0
}

main() {
    log "Starting IPA image downloader..."
    setup_directory

    for f in "${IPA_FILES[@]}"; do
        download_file "$f" || true
    done

    verify_downloads
    log "IPA image downloader completed"
}

main "$@"
