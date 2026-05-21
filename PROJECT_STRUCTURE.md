# Project Structure

```
ironic-ansible/
├── README.md                          # Main project documentation
├── inventory.example                  # Example Ansible inventory
├── ansible.cfg                        # Ansible configuration
├── INITIAL_PHASED_PLAN.md             # Master implementation plan
│
├── group_vars/
│   └── all.yml                        # Global variables for all hosts
│       - Container images & versions
│       - Database credentials
│       - RabbitMQ configuration
│       - Ironic API settings
│       - Network configuration
│       - Storage paths
│       - Authentication settings
│       - Future Keystone hooks
│
├── roles/
│   ├── mariadb/
│   │   ├── files/                     # Static files (empty)
│   │   └── templates/
│   │       └── mariadb.service.j2     # Systemd unit for MariaDB container
│   │
│   ├── rabbitmq/
│   │   ├── files/                     # Static files (empty)
│   │   └── templates/
│   │       └── rabbitmq.service.j2    # Systemd unit for RabbitMQ container
│   │
│   ├── ipa_downloader/
│   │   ├── files/
│   │   │   └── ipa-downloader.sh      # IPA image download script
│   │   └── templates/
│   │       └── ipa-downloader.service.j2  # Systemd unit for downloader
│   │
│   ├── ironic_api/
│   │   └── templates/
│   │       ├── ironic-api.service.j2  # Systemd unit for Ironic API
│   │       └── ironic.conf.j2         # Ironic configuration file
│   │
│   ├── ironic_http/
│   │   └── templates/
│   │       └── ironic-http.service.j2 # Systemd unit for HTTP server
│   │
│   └── ironic_conductor/
│       └── templates/
│           └── ironic-conductor@.service.j2  # Systemd unit template
│
└── playbooks/
    ├── deploy.yml                     # Main deployment orchestrator
    ├── upgrade.yml                    # Upgrade to new version
    ├── destroy.yml                    # Cleanup and removal
    │
    ├── setup.yml                      # Prerequisites setup
    │   - Creates service user/group
    │   - Creates data directories
    │   - Creates Docker network
    │   - Creates htpasswd file
    │
    ├── ironic-deploy.yml              # Main deployment orchestration
    │
    ├── mariadb-deploy.yml             # Deploy MariaDB service
    ├── rabbitmq-deploy.yml            # Deploy RabbitMQ service
    ├── ipa-deploy.yml                 # Deploy IPA downloader
    ├── ironic-api-deploy.yml          # Deploy Ironic API service
    ├── ironic-http-deploy.yml         # Deploy HTTP server service
    └── ironic-conductor-deploy.yml    # Deploy conductor template
    │
    └── validate.yml                   # Validate deployment health
```

## File Descriptions

### Configuration Files

| File | Purpose |
|------|---------|
| `group_vars/all.yml` | Centralized configuration for all deployment variables |
| `inventory.example` | Template for Ansible inventory (copy to `inventory`) |
| `ansible.cfg` | Ansible runtime configuration |

### Roles

#### mariadb
Deploys MariaDB database container with:
- Persistent storage via volume mount
- Pre-configured database/user creation
- Systemd service management

#### rabbitmq
Deploys RabbitMQ message queue container with:
- Management UI enabled
- Persistent storage via volume mount
- Pre-configured user/vhost creation

#### ipa_downloader
Downloads Ironic Python Agent images:
- Fetches kernel/ramdisk/ISO images
- Stores in shared HTTP directory
- Retry logic and verification

#### ironic_api
Deploys Ironic API service:
- Generates ironic.conf from template
- Creates htpasswd for HTTP Basic Auth
- Mounts configuration and logs

#### ironic_http
Deploys HTTP server for IPA images:
- Serves IPA kernel/ramdisk
- Serves boot ISOs for virtual media
- No authentication (public access)

#### ironic_conductor
Creates scalable conductor template:
- Systemd unit template with instance support
- Generates per-instance configurations
- Supports dynamic scaling

### Playbooks

#### Deploy Playbooks

| Playbook | Purpose |
|----------|---------|
| `deploy.yml` | Master orchestrator for full deployment |
| `setup.yml` | Sets up prerequisites (user, dirs, network) |
| `mariadb-deploy.yml` | Deploys MariaDB service |
| `rabbitmq-deploy.yml` | Deploys RabbitMQ service |
| `ipa-deploy.yml` | Downloads IPA images |
| `ironic-api-deploy.yml` | Deploys Ironic API |
| `ironic-http-deploy.yml` | Deploys HTTP server |
| `ironic-conductor-deploy.yml` | Deploys conductor instances |
| `validate.yml` | Verifies all services are healthy |

#### Maintenance Playbooks

| Playbook | Purpose |
|----------|---------|
| `upgrade.yml` | Updates all services to new version |
| `destroy.yml` | Complete cleanup of deployment |

## Templates Overview

All Jinja2 templates use variables from `group_vars/all.yml`:

### Service Templates (`.service.j2`)
- Define systemd unit for Docker container management
- Include health checks and automatic restart
- Support graceful shutdown
- Run as unprivileged service user

### Configuration Templates (`.conf.j2`)
- Generate Ironic configuration dynamically
- Support conditional sections (Keystone, SSL)
- Include all required interface registrations
- Support conductor group configuration

## Deployment Flow

```
deploy.yml
  ├── setup.yml (prerequisites)
  │   ├── Create service user/group
  │   ├── Create directories
  │   ├── Create Docker network
  │   └── Create htpasswd file
  │
  └── ironic-deploy.yml
      ├── mariadb-deploy.yml
      │   └── mariadb.service.j2
      │
      ├── rabbitmq-deploy.yml
      │   └── rabbitmq.service.j2
      │
      ├── ipa-deploy.yml
      │   ├── ipa-downloader.sh
      │   └── ipa-downloader.service.j2
      │
      ├── ironic-api-deploy.yml
      │   ├── ironic.conf.j2
      │   └── ironic-api.service.j2
      │
      ├── ironic-http-deploy.yml
      │   └── ironic-http.service.j2
      │
      └── ironic-conductor-deploy.yml
          ├── ironic-conductor@.service.j2
          └── ironic.conf.j2 (per instance)

  └── validate.yml (health checks)
```

## Scaling Conductors

To add more conductor instances:

1. Edit `group_vars/all.yml`:
```yaml
ironic_conductor_groups:
  - name: "group1"
    workers: 4
  - name: "group2"
    workers: 4
  - name: "group3"  # Add new group
    workers: 4
```

2. Deploy:
```bash
ansible-playbook playbooks/ironic-conductor-deploy.yml -i inventory
```

3. Verify:
```bash
systemctl status ironic-conductor@group3
```

## Customization Points

### Change Image Versions
Edit `group_vars/all.yml`:
```yaml
ironic_image_tag: "2024.3"
mariadb_image_tag: "11.4"
rabbitmq_image_tag: "3.13-management"
```

### Change Ports
Edit `group_vars/all.yml`:
```yaml
ironic_api_port: 8080
ironic_http_port: 8081
mariadb_port: 3307
```

### Change Storage Locations
Edit `group_vars/all.yml`:
```yaml
ironic_data_root: "/mnt/ironic-data"
mariadb_data_dir: "/mnt/ironic-data/mariadb"
rabbitmq_data_dir: "/mnt/ironic-data/rabbitmq"
```

### Enable SSL/TLS
Edit `group_vars/all.yml`:
```yaml
ironic_enable_ssl: true
ironic_ssl_cert_path: "/etc/ironic/certs/ironic.crt"
ironic_ssl_key_path: "/etc/ironic/certs/ironic.key"
```
