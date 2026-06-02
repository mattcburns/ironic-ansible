#!/bin/bash
# =============================================================================
# Ironic Python Agent (IPA) Image Downloader
# =============================================================================
# Downloads IPA kernel and initramfs from upstream OpenStack.
# Downloads optional ESP image artifact for UEFI virtual-media ISO creation.
# =============================================================================

set -euo pipefail

# Configuration (overridable via environment)
IPA_BASE_URL="${IPA_BASE_URL:-https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files}"
IPA_IMAGES_DIR="${IPA_IMAGES_DIR:-/var/lib/ironic/http-images/ipa}"
IPA_KERNEL="${IPA_KERNEL:-ipa-centos9-master.kernel}"
IPA_RAMDISK="${IPA_RAMDISK:-ipa-centos9-master.initramfs}"
ESP_IMAGE_URL="${ESP_IMAGE_URL:-}"
ESP_IMAGE_PATH="${ESP_IMAGE_PATH:-/var/lib/ironic/http-images/esp.img}"

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
    if [ -n "$ESP_IMAGE_URL" ]; then
        local esp_dir
        esp_dir="$(dirname "$ESP_IMAGE_PATH")"
        if [ ! -d "$esp_dir" ]; then
            log "Creating ESP image directory: $esp_dir"
            mkdir -p "$esp_dir"
            chmod 755 "$esp_dir"
        fi
    fi
}

download_url() {
    local source_url="$1"
    local dest_path="$2"
    local label="$3"

    # Skip if file exists and is less than 24 hours old
    if [ -f "$dest_path" ]; then
        local file_age=$(( $(date +%s) - $(stat -c %Y "$dest_path") ))
        if [ $file_age -lt 86400 ]; then
            log "File ${label} is recent, skipping download"
            return 0
        fi
    fi

    log "Downloading ${label} from ${source_url}..."

    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if curl -sSL --fail -o "$dest_path" "$source_url"; then
            if [ -s "$dest_path" ]; then
                log "Successfully downloaded ${label}"
                chmod 644 "$dest_path"
                return 0
            fi
        fi

        retry_count=$((retry_count + 1))
        log_warn "Download attempt ${retry_count} failed for ${label}"
        [ $retry_count -lt $max_retries ] && sleep 5
    done

    log_error "Failed to download ${label} after ${max_retries} attempts"
    return 1
}

download_file() {
    local filename="$1"
    local source_url="${IPA_BASE_URL}/${filename}"
    local dest_path="${IPA_IMAGES_DIR}/${filename}"
    download_url "$source_url" "$dest_path" "$filename"
}


verify_downloads() {
    log "Verifying downloaded artifacts..."
    local missing=0

    for f in "${IPA_FILES[@]}"; do
        local path="${IPA_IMAGES_DIR}/${f}"
        if [ ! -f "$path" ] || [ ! -s "$path" ]; then
            log_error "Missing or empty: ${path}"
            missing=$((missing + 1))
        else
            local size
            size=$(stat -c %s "$path")
            log "Verified ${f} (${size} bytes)"
        fi
    done
    if [ -n "$ESP_IMAGE_URL" ]; then
        if [ ! -f "$ESP_IMAGE_PATH" ] || [ ! -s "$ESP_IMAGE_PATH" ]; then
            log_error "Missing or empty: ${ESP_IMAGE_PATH}"
            missing=$((missing + 1))
        else
            local esp_size
            esp_size=$(stat -c %s "$ESP_IMAGE_PATH")
            log "Verified ESP image ${ESP_IMAGE_PATH} (${esp_size} bytes)"
        fi
    fi

    [ $missing -gt 0 ] && return 1
    log "All download artifacts verified successfully"
    return 0
}

main() {
    log "Starting IPA image downloader..."
    setup_directory

    for f in "${IPA_FILES[@]}"; do
        download_file "$f" || true
    done
    if [ -n "$ESP_IMAGE_URL" ]; then
        download_url "$ESP_IMAGE_URL" "$ESP_IMAGE_PATH" "$(basename "$ESP_IMAGE_PATH")" || true
    fi

    verify_downloads
    log "IPA image downloader completed"
}

main "$@"
