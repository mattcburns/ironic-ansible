# Project Structure

```
ironic-ansible/
├── README.md                          # Main project documentation
├── QUICKSTART.md                      # Quick start guide
├── inventory.example                  # Example Ansible inventory
├── ansible.cfg                        # Ansible configuration
├── requirements.yml                   # Ansible Galaxy dependencies
│
├── group_vars/
│   └── all.yml                        # Global variables for all hosts
│
├── roles/
│   ├── common/                        # Prerequisites setup
│   │   └── tasks/main.yml             # Installs htpasswd, creates user/dirs/network
│   │
│   ├── mariadb/
│   │   └── templates/
│   │       ├── mariadb.service.j2     # Systemd unit (ironic-mariadb.service)
│   │       └── mariadb.env.j2         # Credentials env file (mode 0600)
│   │
│   ├── rabbitmq/
│   │   └── templates/
│   │       ├── rabbitmq.service.j2    # Systemd unit (ironic-rabbitmq.service)
│   │       └── rabbitmq.env.j2        # Credentials env file (mode 0600)
│   │
│   ├── ipa_downloader/
│   │   ├── files/
│   │   │   └── ipa-downloader.sh      # IPA image download script
│   │   └── templates/
│   │       └── ipa-downloader.service.j2  # Oneshot systemd unit
│   │
│   ├── ironic_common/
│   │   └── templates/
│   │       └── ironic.conf.j2         # Shared Ironic configuration
│   │
│   ├── ironic_api/
│   │   └── templates/
│   │       └── ironic-api.service.j2  # Systemd unit for Ironic API
│   │
│   ├── ironic_http/
│   │   └── templates/
│   │       └── ironic-http.service.j2 # Systemd unit for HTTP server
│   │
│   └── ironic_conductor/
│       └── templates/
│           ├── ironic-conductor@.service.j2  # Systemd unit template
│           └── conductor-override.conf.j2    # Per-instance config override
│
└── playbooks/
    ├── deploy.yml                     # Full deployment (roles + validate)
    ├── validate.yml                   # Health checks for all services
    ├── upgrade.yml                    # Rolling upgrade to new version
    ├── destroy.yml                    # Service/data teardown
    └── rollback.yml                   # Full host rollback
```

## Roles

#### common
Prerequisites and host setup:
- Installs `apache2-utils`/`httpd-tools` for htpasswd
- Creates service user/group
- Creates data directories with proper ownership
- Creates Docker bridge network
- Generates htpasswd file for HTTP Basic Auth

#### mariadb
Deploys MariaDB database container:
- Credentials stored in `/etc/ironic/mariadb.env` (mode 0600)
- Persistent storage via volume mount
- Bound to 127.0.0.1 by default (containers use Docker network)
- Systemd service: `ironic-mariadb`

#### rabbitmq
Deploys RabbitMQ message queue container:
- Credentials stored in `/etc/ironic/rabbitmq.env` (mode 0600)
- Management UI enabled
- Bound to 127.0.0.1 by default
- Systemd service: `ironic-rabbitmq`

#### ipa_downloader
Downloads Ironic Python Agent images:
- Fetches kernel and ramdisk from upstream
- Stores in shared HTTP directory
- Retry logic and file verification
- Oneshot systemd unit with `RemainAfterExit=yes`

#### ironic_common
Shared Ironic configuration and schema:
- Generates `ironic.conf` from template
- Runs `ironic-dbsync upgrade` to initialize/migrate the database

#### ironic_api
Deploys Ironic API service:
- Mounts ironic.conf and htpasswd
- Exposes API on configurable bind address and port

#### ironic_http
Deploys HTTP server for IPA images and boot ISOs:
- Serves files from `/var/lib/ironic/http-images`
- Starts after ipa-downloader to ensure images are available
- No authentication (must be reachable from BMC network)

#### ironic_conductor
Deploys scalable conductor instances:
- Systemd template unit (`ironic-conductor@.service`)
- Per-instance config override sets host, workers, and conductor group
- Each instance gets a stable hostname (`--hostname ironic-conductor-<group>`)

## Playbooks

- **`deploy.yml`** — Full deployment: runs all roles in order, then validates
- **`validate.yml`** — Checks systemd services, ports, and API health
- **`upgrade.yml`** — Stops Ironic services, re-deploys config/images, restarts
- **`destroy.yml`** — Stops all services, removes containers/units/data/user
- **`rollback.yml`** — Runs `destroy.yml` and removes deployment images/prerequisite package

## Deployment Flow

```
deploy.yml
  ├── common role (prerequisites)
  │   ├── Install htpasswd package
  │   ├── Create service user/group
  │   ├── Create directories
  │   ├── Create Docker network
  │   └── Generate htpasswd file
  │
  ├── mariadb role
  │   ├── mariadb.env.j2 → /etc/ironic/mariadb.env
  │   └── mariadb.service.j2 → ironic-mariadb.service
  │
  ├── rabbitmq role
  │   ├── rabbitmq.env.j2 → /etc/ironic/rabbitmq.env
  │   └── rabbitmq.service.j2 → ironic-rabbitmq.service
  │
  ├── ipa_downloader role
  │   ├── ipa-downloader.sh
  │   └── ipa-downloader.service.j2
  │
  ├── ironic_common role
  │   ├── ironic.conf.j2 → /etc/ironic/ironic.conf
  │   └── ironic-dbsync upgrade
  │
  ├── ironic_http role
  │   └── ironic-http.service.j2
  │
  ├── ironic_api role
  │   └── ironic-api.service.j2
  │
  ├── ironic_conductor role
  │   ├── conductor-override.conf.j2 → /etc/ironic/conductor-<group>.conf
  │   └── ironic-conductor@.service.j2
  │
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
ansible-playbook playbooks/deploy.yml -i inventory
```

3. Verify:
```bash
systemctl status ironic-conductor@group3
```

Each conductor group gets its own `conductor_group` assignment in Ironic, so
nodes can be targeted to specific conductors via the `conductor_group` property.

## Customization Points

### Change Image Versions
Edit `group_vars/all.yml`:
```yaml
ironic_image_tag: "v34.0.0"  # Pin for production
mariadb_image: "mariadb:11.4"
rabbitmq_image: "rabbitmq:3.13-management"
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
