#!/bin/bash
# =============================================================================
# Ironic Python Agent (IPA) Image Downloader
# =============================================================================
# Downloads IPA kernel and initramfs from upstream OpenStack.
# Downloads optional ESP image artifact for UEFI virtual-media ISO creation.
# Downloads optional Ubuntu LTS cloud image and checksum for provisioning.
# =============================================================================

set -euo pipefail

# Configuration (overridable via environment)
IPA_BASE_URL="${IPA_BASE_URL:-https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files}"
IPA_IMAGES_DIR="${IPA_IMAGES_DIR:-/var/lib/ironic/http-images/ipa}"
IPA_KERNEL="${IPA_KERNEL:-ipa-centos9-master.kernel}"
IPA_RAMDISK="${IPA_RAMDISK:-ipa-centos9-master.initramfs}"
ESP_IMAGE_URL="${ESP_IMAGE_URL:-}"
ESP_IMAGE_PATH="${ESP_IMAGE_PATH:-/var/lib/ironic/http-images/esp.img}"
UBUNTU_LTS_IMAGE_ENABLED="${UBUNTU_LTS_IMAGE_ENABLED:-true}"
UBUNTU_LTS_IMAGE_URL="${UBUNTU_LTS_IMAGE_URL:-}"
UBUNTU_LTS_META_RELEASE_URL="${UBUNTU_LTS_META_RELEASE_URL:-https://changelogs.ubuntu.com/meta-release-lts}"
UBUNTU_LTS_IMAGE_ARCH="${UBUNTU_LTS_IMAGE_ARCH:-amd64}"
UBUNTU_LTS_IMAGE_DIR="${UBUNTU_LTS_IMAGE_DIR:-/var/lib/ironic/http-images/ubuntu}"
UBUNTU_LTS_IMAGE_FILENAME="${UBUNTU_LTS_IMAGE_FILENAME:-}"
UBUNTU_LTS_IMAGE_PATH="${UBUNTU_LTS_IMAGE_PATH:-}"
UBUNTU_LTS_IMAGE_CHECKSUM_PATH="${UBUNTU_LTS_IMAGE_CHECKSUM_PATH:-}"

IPA_FILES=("$IPA_KERNEL" "$IPA_RAMDISK")

log()      { echo "[INFO]  $1"; }
log_warn() { echo "[WARN]  $1"; }
log_error(){ echo "[ERROR] $1"; }

is_true() {
    case "${1,,}" in
        true|1|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

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
    if is_true "$UBUNTU_LTS_IMAGE_ENABLED" && [ ! -d "$UBUNTU_LTS_IMAGE_DIR" ]; then
        log "Creating Ubuntu LTS image directory: $UBUNTU_LTS_IMAGE_DIR"
        mkdir -p "$UBUNTU_LTS_IMAGE_DIR"
        chmod 755 "$UBUNTU_LTS_IMAGE_DIR"
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

resolve_ubuntu_lts_image_url() {
    if [ -n "$UBUNTU_LTS_IMAGE_URL" ]; then
        printf '%s\n' "$UBUNTU_LTS_IMAGE_URL"
        return 0
    fi

    local distro_codename
    distro_codename="$(curl -sSL --fail "$UBUNTU_LTS_META_RELEASE_URL" | awk '/^Dist: /{dist=$2} END{print dist}')"

    if [ -z "$distro_codename" ]; then
        log_error "Unable to resolve latest Ubuntu LTS codename from ${UBUNTU_LTS_META_RELEASE_URL}"
        return 1
    fi

    printf 'https://cloud-images.ubuntu.com/%s/current/%s-server-cloudimg-%s.img\n' \
        "$distro_codename" "$distro_codename" "$UBUNTU_LTS_IMAGE_ARCH"
}

set_ubuntu_lts_target_paths() {
    local source_url="$1"
    local source_filename
    source_filename="$(basename "${source_url%%\?*}")"

    if [ -z "$source_filename" ]; then
        log_error "Unable to derive Ubuntu LTS filename from source URL: ${source_url}"
        return 1
    fi

    if [ -n "$UBUNTU_LTS_IMAGE_FILENAME" ] && [ "$UBUNTU_LTS_IMAGE_FILENAME" != "$source_filename" ]; then
        log_warn "Overriding Ubuntu LTS filename ${UBUNTU_LTS_IMAGE_FILENAME} with upstream filename ${source_filename}"
    fi

    UBUNTU_LTS_IMAGE_FILENAME="$source_filename"
    UBUNTU_LTS_IMAGE_PATH="${UBUNTU_LTS_IMAGE_DIR}/${UBUNTU_LTS_IMAGE_FILENAME}"
    UBUNTU_LTS_IMAGE_CHECKSUM_PATH="${UBUNTU_LTS_IMAGE_PATH}.sha256"
}

write_checksum() {
    local image_path="$1"
    local checksum_path="$2"

    if [ ! -s "$image_path" ]; then
        log_warn "Skipping checksum generation; missing image ${image_path}"
        return 1
    fi

    sha256sum "$image_path" | awk '{print $1}' > "$checksum_path"
    chmod 644 "$checksum_path"
    log "Wrote checksum file ${checksum_path}"
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
    if is_true "$UBUNTU_LTS_IMAGE_ENABLED"; then
        if [ ! -f "$UBUNTU_LTS_IMAGE_PATH" ] || [ ! -s "$UBUNTU_LTS_IMAGE_PATH" ]; then
            log_error "Missing or empty: ${UBUNTU_LTS_IMAGE_PATH}"
            missing=$((missing + 1))
        else
            local ubuntu_size
            ubuntu_size=$(stat -c %s "$UBUNTU_LTS_IMAGE_PATH")
            log "Verified Ubuntu LTS image ${UBUNTU_LTS_IMAGE_PATH} (${ubuntu_size} bytes)"
        fi

        if [ ! -f "$UBUNTU_LTS_IMAGE_CHECKSUM_PATH" ] || [ ! -s "$UBUNTU_LTS_IMAGE_CHECKSUM_PATH" ]; then
            log_error "Missing or empty: ${UBUNTU_LTS_IMAGE_CHECKSUM_PATH}"
            missing=$((missing + 1))
        else
            local expected_checksum actual_checksum
            expected_checksum="$(sha256sum "$UBUNTU_LTS_IMAGE_PATH" | awk '{print $1}')"
            actual_checksum="$(tr -d '[:space:]' < "$UBUNTU_LTS_IMAGE_CHECKSUM_PATH")"
            if [ "$expected_checksum" != "$actual_checksum" ]; then
                log_error "Checksum mismatch for ${UBUNTU_LTS_IMAGE_PATH}"
                missing=$((missing + 1))
            else
                log "Verified checksum file ${UBUNTU_LTS_IMAGE_CHECKSUM_PATH}"
            fi
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
    if is_true "$UBUNTU_LTS_IMAGE_ENABLED"; then
        local ubuntu_source_url
        if ubuntu_source_url="$(resolve_ubuntu_lts_image_url)"; then
            if set_ubuntu_lts_target_paths "$ubuntu_source_url"; then
                download_url "$ubuntu_source_url" "$UBUNTU_LTS_IMAGE_PATH" "$UBUNTU_LTS_IMAGE_FILENAME" || true
                write_checksum "$UBUNTU_LTS_IMAGE_PATH" "$UBUNTU_LTS_IMAGE_CHECKSUM_PATH" || true
            else
                log_error "Failed to derive Ubuntu LTS target filename/path from source URL"
            fi
        else
            log_error "Failed to resolve Ubuntu LTS image URL"
        fi
    fi

    verify_downloads
    log "IPA image downloader completed"
}

main "$@"
