# Initial Phased Plan: Standalone OpenStack Ironic Deployment with Ansible

## Project Overview

This project will create an Ansible-based deployment framework for OpenStack Ironic in standalone mode using:
- Docker containers from metal3-io
- Standard MariaDB and RabbitMQ containers
- Systemd units/services to manage containers
- Systemd unit templates for scalable ironic-conductor instances (e.g., `ironic-conductor@group1`, `ironic-conductor@group2`)
- Basic authentication (http_basic) with option for Keystone integration later
- **Virtual media boot (redfish-virtual-media) and UEFI HTTP boot (redfish-https)** - No PXE/DHCP/TFTP
- IPA (Ironic Python Agent) image download from metal3

**Prerequisites**: Docker must be installed and running on the target host(s).

## Design Decisions

### Container Runtime
- **Choice**: Docker
- **Rationale**: Standard on Ubuntu, well-documented, metal3 containers tested with Docker

### Container Management
- **Choice**: Systemd service units (managing Docker containers)
- **Rationale**: More transparent configuration, easier Ansible management, better logging integration, containers persist across reboots

### Database
- **Choice**: MariaDB container (not SQLite)
- **Rationale**: Production-ready, persistent storage, better for multi-conductor setups

### Messaging
- **Choice**: RabbitMQ container
- **Rationale**: Required for conductor communication and scaling

### Authentication
- **Choice**: http_basic with htpasswd
- **Rationale**: Simple standalone auth, easy migration to Keystone later

### Conductor Scaling
- **Choice**: Systemd templates (`ironic-conductor@.service`)
- **Rationale**: Clean scaling model, instance-specific configuration via `%i` specifier

---

## Phase 1: Project Skeleton and Structure

### Objective
Create the foundational Ansible project structure with all necessary directories, variables, and configuration templates.

### Tasks
1. Create directory structure:
   - `group_vars/`
   - `host_vars/`
   - `playbooks/`
   - `roles/` (with sub-roles for each component)
   - `templates/` (Jinja2 templates for systemd units and configs)
   - `files/` (static files if needed)
   - `inventory/` (example inventory files)

2. Create main Ansible playbooks:
   - `site.yml` - Main entry point
   - `deploy.yml` - Full deployment playbook
   - `upgrade.yml` - Upgrade playbook
   - `destroy.yml` - Cleanup playbook

3. Define global variables in `group_vars/all.yml`:
   - Container image registries and versions
   - Network configuration defaults
   - Authentication settings
   - Feature flags (enable/disable interfaces)

4. Create inventory templates:
   - Single-node inventory example
   - Multi-node inventory example

5. Create project documentation:
   - `README.md` with quick start guide
   - `vars.md` documenting all variables

### Deliverables
- Complete Ansible project structure
- Working inventory examples
- Documentation for variable configuration

### Validation
- `ansible-playbook --syntax-check site.yml` passes
- Directory structure matches plan

---

## Phase 2: Dependency Containers Role (MariaDB & RabbitMQ)

### Objective
Deploy and configure MariaDB and RabbitMQ containers as systemd services.

### Tasks
1. Create `roles/ironic-dependencies/`:
   - Download MariaDB container image (quay.io/metal3-io/mariadb)
   - Download RabbitMQ container image (standard rabbitmq:3-management)
   
2. Create systemd service units:
   - `mariadb.service` template
   - `rabbitmq.service` template
   - Services should support:
     - Container restart policies
     - Health checks
     - Volume mounts for data persistence
     - Network configuration (host mode)

3. Configure MariaDB:
   - Create ironic database
   - Set up authentication
   - Configure for container persistence

4. Configure RabbitMQ:
   - Set up default vhost and users
   - Configure for Ironic messaging

5. Create Jinja2 templates:
   - `mariadb.service.j2`
   - `rabbitmq.service.j2`
   - Environment file templates

### Deliverables
- MariaDB container running as systemd service
- RabbitMQ container running as systemd service
- Persistent data storage configured
- Services start on boot

### Validation
- `systemctl status mariadb` shows running
- `systemctl status rabbitmq` shows running
- MariaDB accepts connections and has ironic database
- RabbitMQ web interface accessible

---

## Phase 3: IPA Downloader Role

### Objective
Download the Ironic Python Agent (IPA) kernel and ramdisk images from metal3.

### Tasks
1. Create `roles/ipa-downloader/`:
   - Download IPA downloader container (quay.io/metal3-io/ironic-ipa-downloader)
   - Create temporary container to download IPA images
   - Extract and place images in correct location

2. Configure IPA sources:
   - Support for different architectures (x86_64, aarch64)
   - Download from quay.io or custom IPA_BASEURI
   - Place images in `/var/lib/ironic/html/images/`

3. Create systemd service or one-shot task:
   - Run on initial deployment
   - Option to re-download on upgrade

4. Handle checksums:
   - Verify downloaded images
   - Create checksum files for ironic-http

### Deliverables
- IPA kernel and ramdisk images downloaded
- Images placed in correct directory
- Checksums generated

### Validation
- `ironic-python-agent.kernel` exists in images directory
- `ironic-python-agent.initramfs` exists in images directory
- Files have correct permissions

---

## Phase 4: Ironic API Container Role

### Objective
Deploy the ironic-api container as a systemd service.

### Tasks
1. Create `roles/ironic-api/`:
   - Download ironic container (quay.io/metal3-io/ironic)
   - Create systemd service unit template
   - Configure ironic-api specific settings

2. Configure ironic-api:
   - Set up WSGI application
   - Configure authentication (http_basic)
   - Set up htpasswd file for basic auth
   - Configure API endpoint and ports

3. Create configuration files:
   - `ironic.conf` with API-specific settings
   - Environment variables for container
   - Volume mounts for configuration

4. Create Jinja2 templates:
   - `ironic-api.service.j2`
   - `ironic-api.conf.j2`
   - `htpasswd.j2` (for basic auth users)

### Deliverables
- ironic-api container running as systemd service
- Basic authentication configured
- API accessible on configured port

### Validation
- `systemctl status ironic-api` shows running
- API responds to health check
- Basic authentication works
- `openstack baremetal version` command works (with proper env)

---

## Phase 5: Ironic HTTP Container Role

### Objective
Deploy ironic-http container for serving IPA images and boot ISOs.

### Tasks
1. Create `roles/ironic-http/`:
   - Configure ironic-http container
   - Set up HTTP server for IPA kernel and ramdisk images
   - Configure HTTP server for generated boot ISOs (virtual media)
   - Configure port and binding

2. Create systemd service unit:
   - `ironic-http.service` template
   - Configure for serving files over HTTP/HTTPS

3. Configure file serving:
   - Serve IPA images from `/var/lib/ironic/html/images/`
   - Set up HTTP endpoints for conductor configuration
   - Configure `http_url` and `http_root` for ironic configuration

4. Create Jinja2 templates:
   - `ironic-http.service.j2`
   - Environment file template

### Deliverables
- ironic-http container running and serving files
- HTTP endpoints accessible for IPA and ISO serving

### Validation
- HTTP server responds on configured port
- IPA images downloadable via HTTP
- Boot ISOs can be served from HTTP endpoint

---

## Phase 6: Ironic Conductor Template Role

### Objective
Deploy scalable ironic-conductor instances using systemd unit templates.

### Tasks
1. Create `roles/ironic-conductor/`:
   - Download ironic container image
   - Create systemd template unit `ironic-conductor@.service`
   - Support multiple conductor groups/instances

2. Configure conductor scaling:
   - Define conductor groups in variables
   - Each instance uses `%i` specifier for unique configuration
   - Support for host-specific conductor configurations

3. Create conductor configuration:
   - `ironic-conductor.conf.j2` template
   - Per-instance configuration files
   - Environment files per instance

4. Configure conductor groups:
   - Variable for conductor groups (e.g., `group1`, `group2`)
   - Each group can have different settings
   - Support for discovery vs deployment conductors

5. Create systemd template:
   - `ironic-conductor@.service.j2`
   - Uses `%i` for instance-specific paths and configs
   - Proper dependencies on MariaDB and RabbitMQ

### Deliverables
- Systemd template unit for ironic-conductor
- Ability to start multiple conductor instances
- Instance-specific configuration support

### Validation
- `systemctl start ironic-conductor@group1` works
- `systemctl start ironic-conductor@group2` works
- Both conductors register in Ironic
- Conductors can be managed independently

---

## Phase 7: Ironic Configuration and Integration

### Objective
Create comprehensive ironic.conf configuration integrating all components.

### Tasks
1. Create `roles/ironic-config/`:
   - Generate complete ironic.conf
   - Integrate database, messaging, and interface settings
   - Configure for standalone operation
   - Set up HTTP server configuration (http_url, http_root)

2. Configure interfaces:
   - Enable **redfish hardware type**
   - Enable **redfish-virtual-media boot interface** (primary)
   - Enable **redfish-https boot interface** (UEFI HTTP boot)
   - Enable **ramdisk deploy interface**
   - Enable **agent inspect interface** (built-in, no separate service needed)
   - Enable **noop network interface** (no networking required for virtual media)
   - **Disable PXE/iPXE components** (not needed)

3. Configure conductor settings:
   - Set deploy_kernel and deploy_ramdisk URLs (pointing to ironic-http)
   - Configure rescue images
   - Set up automated cleaning
   - Configure `deploy.http_url` for serving ISOs
   - Configure **inspector section** for built-in inspection:
     - `inspector.extra_kernel_params` for IPA inspection collectors
     - Enable managed inspection for virtual media boot

4. Configure authentication:
   - http_basic authentication strategy
   - htpasswd file location
   - User credentials management

5. Create Jinja2 templates:
   - `ironic.conf.j2` - Main configuration
   - Support for overrides per role
   - Configure `enabled_boot_interfaces = redfish-virtual-media,redfish-https`
   - Configure `enabled_deploy_interfaces = ramdisk`
   - Configure `enabled_inspect_interfaces = agent,no-inspect`
   - Configure `enabled_network_interfaces = noop`
   - Configure `[inspector]` section for built-in inspection

### Deliverables
- Complete ironic.conf configuration
- All components properly integrated
- Redfish virtual media and UEFI HTTP boot enabled
- **Built-in inspection configured** (agent interface)
- HTTP server configured for ISO serving

### Validation
- Ironic API returns correct configuration
- Enabled interfaces match requirements (redfish-virtual-media, redfish-https)
- Agent inspect interface enabled
- PXE/TFTP components not present
- Conductor can communicate with API
- Inspection can be triggered via `baremetal node inspect`

---

## Phase 8: Main Playbook Integration

### Objective
Integrate all roles into cohesive deployment playbooks.

### Tasks
1. Update `playbooks/deploy.yml`:
   - Order roles correctly (dependencies first)
   - Add handlers for service management
   - Add error handling and rollback options

2. Create `playbooks/upgrade.yml`:
   - Pull new container images
   - Rolling restart of services
   - Configuration updates

3. Create `playbooks/destroy.yml`:
   - Stop all services
   - Remove containers
   - Cleanup data (optional)

4. Add deployment tags:
   - Tag each role for selective deployment
   - Support for partial deployments

5. Create handler roles:
   - Service restart handlers
   - Configuration reload handlers

### Deliverables
- Complete deploy playbook
- Upgrade playbook
- Destroy playbook
- Tagged roles for flexibility

### Validation
- `ansible-playbook deploy.yml` completes successfully
- All services running after deployment
- Upgrade playbook works without data loss

---

## Phase 9: Testing and Validation

### Objective
Add validation tasks and create test scenarios.

### Tasks
1. Create `roles/ironic-validate/`:
   - Check all services are running
   - Verify API connectivity
   - Test authentication
   - Validate database connectivity
   - Check RabbitMQ connectivity

2. Create test playbook:
   - `playbooks/test.yml`
   - Run validation tasks
   - Report status

3. Add post-deployment hooks:
   - Automatic validation after deploy
   - Health check endpoints
   - Service status reporting

### Deliverables
- Validation role
- Test playbook
- Automated health checks

### Validation
- All validation tasks pass
- Test playbook provides clear status
- Services are healthy

---

## Phase 10: Documentation and Examples

### Objective
Create comprehensive documentation and example configurations.

### Tasks
1. Update `README.md`:
   - Complete deployment guide
   - Variable documentation
   - Troubleshooting section

2. Create example configurations:
   - `inventory/single-node.yml`
   - `inventory/multi-conductor.yml`
   - `group_vars/ironic.yml.example`

3. Create guides:
   - Adding new conductor groups
   - Upgrading Ironic
   - Adding nodes to Ironic
   - Enabling iPXE later

4. Create variable documentation:
   - All configurable options
   - Default values
   - Dependencies between variables

### Deliverables
- Complete README
- Example inventories
- Configuration examples
- Variable reference

### Validation
- Documentation is clear and complete
- Examples work as documented

---

## Phase 11: Keystone Integration Preparation

### Objective
Add preparation for future Keystone integration (disabled by default).

### Tasks
1. Add Keystone configuration options:
   - Variables for Keystone endpoints
   - Variables for Keystone credentials
   - Feature flag to enable/disable

2. Update ironic.conf template:
   - Support for both http_basic and keystone
   - Conditional Keystone configuration

3. Create migration guide:
   - How to migrate from http_basic to Keystone
   - What changes are needed

### Deliverables
- Keystone configuration support (disabled)
- Migration documentation
- Easy path to Keystone later

### Validation
- Default deployment still uses http_basic
- Keystone configuration is available but not active

---

## Implementation Notes

### Variable Naming Convention
- Use `ironic_` prefix for all Ironic-specific variables
- Use `ironic_<component>_` for component-specific variables
- Boolean variables use `_enabled` suffix

### Container Image Management
- All images pulled from quay.io/metal3-io by default
- Variables to override image locations for air-gapped environments
- Version variables for each component

### Boot Interface Configuration
- **Primary**: redfish-virtual-media (works with BIOS and UEFI)
- **Secondary**: redfish-https (UEFI-only HTTP boot)
- **No PXE/DHCP/TFTP** components deployed
- HTTP server (`ironic-http`) serves IPA images and generated boot ISOs

### Inspection Configuration
- **Built-in inspection** via `agent` inspect interface (no separate ironic-inspector service)
- Supported since Ironic 2023.2 (Bobcat)
- Works with virtual media boot via managed inspection mode
- Configure `[inspector]` section in ironic.conf for kernel parameters and collectors
- Inspection callback handled by ironic-conductor itself

### Security Considerations
- Basic auth passwords in encrypted variables
- Option for TLS/HTTPS (future enhancement)
- Network segmentation support (L3 boot supported with virtual media)

### Error Handling
- Each role should be idempotent
- Failed deployments should be rollable
- Clear error messages for common issues

---

## Phase Dependencies

```
Phase 1 (Skeleton)
    ↓
Phase 2 (Dependencies: MariaDB, RabbitMQ)
    ↓
Phase 3 (IPA Downloader) ───┐
    ↓                      ↓
Phase 4 (Ironic API)   Phase 7 (Config)
    ↓                      ↑
Phase 5 (HTTP)           ↑
    ↓                      ↑
Phase 6 (Conductor) ──────┘
    ↓
Phase 8 (Integration)
    ↓
Phase 9 (Validation)
    ↓
Phase 10 (Documentation)
    ↓
Phase 11 (Keystone Prep)
```

---

## Success Criteria

After all phases complete:
1. Full Ironic deployment with single `ansible-playbook deploy.yml` command
2. Multiple conductor instances manageable via systemd templates
3. Basic authentication working
4. **Redfish virtual media (redfish-virtual-media) and UEFI HTTP boot (redfish-https) interfaces enabled**
5. **No PXE/DHCP/TFTP components** (simplified deployment)
6. **Built-in inspection working** (agent interface, no separate service)
7. IPA images downloaded and served via HTTP
8. All services running as systemd-managed Docker containers
9. Clean upgrade path available
10. Documentation complete and accurate
