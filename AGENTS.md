# AGENTS.md

## Purpose
This file is the operating contract for AI agents working in this repository.
Follow these rules to keep changes safe, minimal, idempotent, and easy to review.

## Audience
- Primary audience: AI coding agents.
- Secondary audience: humans reviewing or coordinating agent work.
- If instructions conflict, prefer direct user instructions first, then this file.

## Repository Overview
- Project type: Ansible-based standalone OpenStack Ironic deployment.
- Core entrypoints:
  - `playbooks/deploy.yml` (full deploy)
  - `playbooks/validate.yml` (health checks)
  - `playbooks/upgrade.yml` (upgrade flow)
  - `playbooks/destroy.yml` / `playbooks/rollback.yml` (teardown/reset)
- Primary configuration:
  - `group_vars/all.yml` (global defaults and feature flags)
  - `inventory.example` (template inventory)
- Ansible config/dependencies:
  - `ansible.cfg`
  - `requirements.yml`
## Agent Execution Protocol
1. Read task scope and identify the smallest viable change.
2. Inspect only the files needed for that scope.
3. Make focused edits; avoid opportunistic refactors.
4. Run the minimum relevant validation commands from this file.
5. Report changed files, what was validated, and any remaining risk.

## Repository Bootstrap (when needed)
1. Install collections:
   - `ansible-galaxy collection install -r requirements.yml`
2. Create inventory:
   - `cp inventory.example inventory`
3. Review host/secrets defaults:
   - `group_vars/all.yml`

## Development Rules

### General
- Keep changes minimal and scoped to the requested task.
- Preserve idempotency in roles and playbooks.
- Prefer explicit module names (`ansible.builtin.*`, `community.docker.*`) as used throughout the repo.
- Avoid introducing breaking variable renames unless all references are updated in the same change.
- Do not alter defaults for auth/interfaces/paths unless explicitly asked.
- Do not reformat unrelated files.

### Secrets and Sensitive Data
- Never commit real credentials.
- Keep secret-bearing templates/tasks protected with `no_log: true` where appropriate.
- Maintain restrictive file modes for sensitive files (for example `0600` for env files).
- Never print or expose secret values in logs, examples, or summaries.

### Playbooks and Roles
- Keep deployment order semantics intact:
  1. `common`
  2. infra (`mariadb`, `rabbitmq`)
  3. `ipa_downloader`
  4. `ironic_common`
  5. services (`ironic_http`, `ironic_api`, `ironic_conductor`)
  6. `ironic_cli`
  7. validation
- If changing conductor behavior, ensure loops over `ironic_conductor_groups` remain correct.
- If changing service templates, ensure handlers reload systemd before service restart/start.
- Preserve role boundaries; avoid cross-role rewrites unless required for correctness.

### Containers/Systemd
- This project manages containers via systemd units (not docker-compose).
- Keep systemd unit paths and names stable unless a migration is intentionally included.
- Ensure ports, container names, and network settings remain aligned with `group_vars/all.yml`.
- Avoid changing data locations under `/etc/ironic` and `/var/lib/ironic` unless explicitly requested.

## Allowed vs. High-Risk Changes for Agents
- Allowed by default:
  - Small bug fixes in tasks/templates/defaults.
  - Validation/doc updates required by behavior changes.
  - Variable wiring needed to complete requested work.
- High-risk (require explicit request):
  - Auth strategy changes (`http_basic` ↔ Keystone).
  - Interface default changes (boot/deploy/network/inspect).
  - Large lifecycle behavior changes (`destroy`/`rollback` semantics).
  - Renaming service units, container names, or persistent paths.

## Validation Expectations
Run these checks for meaningful changes:
1. Syntax check:
   - `ansible-playbook --syntax-check playbooks/deploy.yml -i inventory`
2. Deployment validation playbook:
   - `ansible-playbook playbooks/validate.yml -i inventory`
3. If your change impacts lifecycle flows, also exercise:
   - `ansible-playbook playbooks/upgrade.yml -i inventory` (upgrade-related changes)
   - `ansible-playbook playbooks/destroy.yml -i inventory` (teardown-related changes)

If `inventory` is not available locally, create it from `inventory.example` before running checks.
If local execution is constrained, state exactly which checks were not run and why.

## When Updating Documentation
- Keep docs synchronized with behavior changes in:
  - `README.md`
  - `QUICKSTART.md`
  - `PROJECT_STRUCTURE.md`
- Prefer documenting new variables in `group_vars/all.yml` comments as the source of truth.

## Agent Deliverable Format
In final handoff, include:
1. What changed (high level, 2-6 bullets).
2. Files changed (paths only).
3. Validation run and outcomes.
4. Any follow-up actions or residual risks.
