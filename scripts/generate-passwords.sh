#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ./scripts/generate-passwords.sh [path/to/group_vars/all.yml]

Generates strong random passwords and updates:
  - mariadb_password
  - mariadb_root_password
  - rabbitmq_password
  - ironic_admin_password

Environment variables:
  PASSWORD_LENGTH  Password length (default: 32, minimum: 16)
EOF
  exit 0
fi

TARGET_FILE="${1:-group_vars/all.yml}"
PASSWORD_LENGTH="${PASSWORD_LENGTH:-32}"

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "Error: target file not found: ${TARGET_FILE}" >&2
  exit 1
fi

if ! [[ "${PASSWORD_LENGTH}" =~ ^[0-9]+$ ]] || (( PASSWORD_LENGTH < 16 )); then
  echo "Error: PASSWORD_LENGTH must be an integer >= 16 (got: ${PASSWORD_LENGTH})" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required but not installed." >&2
  exit 1
fi

python3 - "${TARGET_FILE}" "${PASSWORD_LENGTH}" <<'PY'
import pathlib
import re
import secrets
import string
import sys

target_path = pathlib.Path(sys.argv[1])
password_length = int(sys.argv[2])

keys = [
    "mariadb_password",
    "mariadb_root_password",
    "rabbitmq_password",
    "ironic_admin_password",
]

content = target_path.read_text(encoding="utf-8")
original_content = content

missing_keys = []
for key in keys:
    key_pattern = re.compile(
        rf'^(?P<prefix>\s*{re.escape(key)}\s*:\s*)"[^"]*"(?P<suffix>\s*(?:#.*)?)$',
        re.MULTILINE,
    )
    if key_pattern.search(content) is None:
        missing_keys.append(key)

if missing_keys:
    print(
        f"Error: missing expected key(s) in {target_path}: {', '.join(missing_keys)}",
        file=sys.stderr,
    )
    sys.exit(1)

alphabet = string.ascii_letters + string.digits + "-_"

for key in keys:
    generated_password = "".join(
        secrets.choice(alphabet) for _ in range(password_length)
    )
    replace_pattern = re.compile(
        rf'^(?P<prefix>\s*{re.escape(key)}\s*:\s*)"[^"]*"(?P<suffix>\s*(?:#.*)?)$',
        re.MULTILINE,
    )
    content, replacement_count = replace_pattern.subn(
        lambda match, value=generated_password: f'{match.group("prefix")}{value}"{match.group("suffix")}',
        content,
        count=1,
    )
    if replacement_count != 1:
        print(
            f"Error: failed to update key {key} in {target_path}",
            file=sys.stderr,
        )
        sys.exit(1)

backup_path = target_path.with_name(f"{target_path.name}.bak")
backup_path.write_text(original_content, encoding="utf-8")
target_path.write_text(content, encoding="utf-8")

print(f"Updated passwords in {target_path}")
print(f"Backup written to {backup_path}")
print("Regenerated keys:")
for key in keys:
    print(f" - {key}")
PY
