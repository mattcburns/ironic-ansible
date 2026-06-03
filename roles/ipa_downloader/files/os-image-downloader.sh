#!/bin/bash
# =============================================================================
# OS Image Downloader
# =============================================================================
# Downloads Ubuntu LTS and Flatcar deployment images and writes SHA256 checksum files.
# =============================================================================

set -euo pipefail

# Ubuntu LTS image configuration (overridable via environment)
UBUNTU_LTS_IMAGE_ENABLED="${UBUNTU_LTS_IMAGE_ENABLED:-true}"
UBUNTU_LTS_IMAGE_URL="${UBUNTU_LTS_IMAGE_URL:-}"
UBUNTU_LTS_META_RELEASE_URL="${UBUNTU_LTS_META_RELEASE_URL:-https://changelogs.ubuntu.com/meta-release-lts}"
UBUNTU_LTS_IMAGE_ARCH="${UBUNTU_LTS_IMAGE_ARCH:-amd64}"
UBUNTU_LTS_IMAGE_DIR="${UBUNTU_LTS_IMAGE_DIR:-/var/lib/ironic/http-images/ubuntu}"
UBUNTU_LTS_IMAGE_FILENAME="${UBUNTU_LTS_IMAGE_FILENAME:-}"
UBUNTU_LTS_IMAGE_PATH="${UBUNTU_LTS_IMAGE_PATH:-}"
UBUNTU_LTS_IMAGE_CHECKSUM_PATH="${UBUNTU_LTS_IMAGE_CHECKSUM_PATH:-}"

# Flatcar whole-disk image configuration (overridable via environment)
FLATCAR_IMAGE_ENABLED="${FLATCAR_IMAGE_ENABLED:-false}"
FLATCAR_IMAGE_DIR="${FLATCAR_IMAGE_DIR:-/var/lib/ironic/http-images/flatcar}"
FLATCAR_IMAGE_SOURCE_URL="${FLATCAR_IMAGE_SOURCE_URL:-https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_openstack_image.img}"
FLATCAR_IMAGE_FILENAME="${FLATCAR_IMAGE_FILENAME:-}"
FLATCAR_IMAGE_PATH="${FLATCAR_IMAGE_PATH:-}"
FLATCAR_IMAGE_CHECKSUM_PATH="${FLATCAR_IMAGE_CHECKSUM_PATH:-}"

log()      { echo "[INFO]  $1"; }
log_warn() { echo "[WARN]  $1"; }
log_error(){ echo "[ERROR] $1"; }

is_true() {
    case "${1,,}" in
        true|1|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_directory() {
    local dir_path="$1"
    local label="$2"
    if [ ! -d "$dir_path" ]; then
        log "Creating ${label} directory: ${dir_path}"
        mkdir -p "$dir_path"
        chmod 755 "$dir_path"
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

set_flatcar_target_paths() {
    local source_filename
    source_filename="$(basename "${FLATCAR_IMAGE_SOURCE_URL%%\?*}")"

    if [ -z "$source_filename" ]; then
        log_error "Unable to derive Flatcar image filename from source URL: ${FLATCAR_IMAGE_SOURCE_URL}"
        return 1
    fi

    if [ -n "$FLATCAR_IMAGE_FILENAME" ] && [ "$FLATCAR_IMAGE_FILENAME" != "$source_filename" ]; then
        log_warn "Overriding Flatcar image filename ${FLATCAR_IMAGE_FILENAME} with upstream filename ${source_filename}"
    fi

    FLATCAR_IMAGE_FILENAME="$source_filename"
    FLATCAR_IMAGE_PATH="${FLATCAR_IMAGE_DIR}/${FLATCAR_IMAGE_FILENAME}"
    FLATCAR_IMAGE_CHECKSUM_PATH="${FLATCAR_IMAGE_PATH}.sha256"
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

process_ubuntu_lts_image() {
    ensure_directory "$UBUNTU_LTS_IMAGE_DIR" "Ubuntu LTS image"

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
}

process_flatcar_image() {
    if [ -z "$FLATCAR_IMAGE_SOURCE_URL" ]; then
        log_error "Flatcar mirror is enabled but FLATCAR_IMAGE_SOURCE_URL is empty"
        return 1
    fi
    ensure_directory "$FLATCAR_IMAGE_DIR" "Flatcar image"

    if set_flatcar_target_paths; then
        download_url "$FLATCAR_IMAGE_SOURCE_URL" "$FLATCAR_IMAGE_PATH" "$FLATCAR_IMAGE_FILENAME" || true
        write_checksum "$FLATCAR_IMAGE_PATH" "$FLATCAR_IMAGE_CHECKSUM_PATH" || true
    else
        log_error "Failed to derive Flatcar target filename/path values from source URL"
        return 1
    fi
}

verify_downloads() {
    log "Verifying downloaded artifacts..."
    local missing=0

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
            local ubuntu_expected_checksum ubuntu_actual_checksum
            ubuntu_expected_checksum="$(sha256sum "$UBUNTU_LTS_IMAGE_PATH" | awk '{print $1}')"
            ubuntu_actual_checksum="$(tr -d '[:space:]' < "$UBUNTU_LTS_IMAGE_CHECKSUM_PATH")"
            if [ "$ubuntu_expected_checksum" != "$ubuntu_actual_checksum" ]; then
                log_error "Checksum mismatch for ${UBUNTU_LTS_IMAGE_PATH}"
                missing=$((missing + 1))
            else
                log "Verified checksum file ${UBUNTU_LTS_IMAGE_CHECKSUM_PATH}"
            fi
        fi
    fi

    if is_true "$FLATCAR_IMAGE_ENABLED"; then
        if [ ! -f "$FLATCAR_IMAGE_PATH" ] || [ ! -s "$FLATCAR_IMAGE_PATH" ]; then
            log_error "Missing or empty: ${FLATCAR_IMAGE_PATH}"
            missing=$((missing + 1))
        else
            local flatcar_size
            flatcar_size=$(stat -c %s "$FLATCAR_IMAGE_PATH")
            log "Verified Flatcar image ${FLATCAR_IMAGE_PATH} (${flatcar_size} bytes)"
        fi

        if [ ! -f "$FLATCAR_IMAGE_CHECKSUM_PATH" ] || [ ! -s "$FLATCAR_IMAGE_CHECKSUM_PATH" ]; then
            log_error "Missing or empty: ${FLATCAR_IMAGE_CHECKSUM_PATH}"
            missing=$((missing + 1))
        else
            local flatcar_expected_checksum flatcar_actual_checksum
            flatcar_expected_checksum="$(sha256sum "$FLATCAR_IMAGE_PATH" | awk '{print $1}')"
            flatcar_actual_checksum="$(tr -d '[:space:]' < "$FLATCAR_IMAGE_CHECKSUM_PATH")"
            if [ "$flatcar_expected_checksum" != "$flatcar_actual_checksum" ]; then
                log_error "Checksum mismatch for ${FLATCAR_IMAGE_PATH}"
                missing=$((missing + 1))
            else
                log "Verified checksum file ${FLATCAR_IMAGE_CHECKSUM_PATH}"
            fi
        fi
    fi

    [ $missing -gt 0 ] && return 1
    log "All enabled OS image artifacts verified successfully"
    return 0
}

main() {
    log "Starting OS image downloader..."

    if ! is_true "$UBUNTU_LTS_IMAGE_ENABLED" && ! is_true "$FLATCAR_IMAGE_ENABLED"; then
        log "OS image mirroring is disabled for both Ubuntu and Flatcar; nothing to download"
        return 0
    fi

    if is_true "$UBUNTU_LTS_IMAGE_ENABLED"; then
        process_ubuntu_lts_image
    else
        log "Ubuntu LTS image mirroring is disabled"
    fi

    if is_true "$FLATCAR_IMAGE_ENABLED"; then
        process_flatcar_image
    else
        log "Flatcar image mirroring is disabled"
    fi

    verify_downloads
    log "OS image downloader completed"
}

main "$@"
