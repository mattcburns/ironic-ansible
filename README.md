# Standalone OpenStack Ironic Deployment via Ansible

A complete Ansible-based deployment solution for running OpenStack Ironic in standalone mode using Docker containers managed by systemd. This deployment uses **virtual media booting** and **built-in agent inspection** - eliminating the need for PXE, DHCP, or a separate inspector service.

## 🚀 Features

- ✅ **Docker-based deployment**: All Ironic components run in isolated containers
- ✅ **Systemd management**: Services persist across reboots with automatic restart
- ✅ **No PXE/DHCP required**: Uses Redfish virtual media and HTTP boot
- ✅ **Built-in inspection**: No separate ironic-inspector service needed
- ✅ **HTTP Basic Auth**: Simple authentication with htpasswd
- ✅ **Scalable conductors**: Systemd unit templates for dynamic conductor scaling
- ✅ **Production-ready**: MariaDB and RabbitMQ for persistence and messaging

## 📋 Prerequisites

- **Operating System**: Ubuntu 22.04 LTS or later (tested on 24.04)
- **Docker**: Docker Engine 24.0+ installed and running
- **Ansible**: Ansible 2.14+ installed on the control node
- **Root/Sudo access**: Required for systemd service management
- **Network access**: Outbound internet access to pull Docker images

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Host System                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Docker Network (bridge)                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │  │
│  │  │   MariaDB    │  │   RabbitMQ   │  │   HTTP     │ │  │
│  │  │  (Container) │  │  (Container) │  │   Server   │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └────┬───────┘ │  │
│  │         │                 │               │          │  │
│  │  ┌──────▼───────┐  ┌──────▼───────┐  ┌────▼───────┐ │  │
│  │  │ Ironic API   │  │ Ironic       │  │ Ironic     │ │  │
│  │  │ (Container)  │◄─┤ Conductor    │  │ Conductor  │ │  │
│  │  └──────────────┘  │ (Container)  │  │ (Container)│ │  │
│  │                    └──────────────┘  └────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                              │                             │
│                    ┌─────────▼─────────┐                  │
│                    │  Bare Metal Nodes │                  │
│                    │  (via Redfish)    │                  │
│                    └───────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Description | Port |
|-----------|-------------|------|
| **MariaDB** | Persistent database for Ironic state | 3306 |
| **RabbitMQ** | Message queue for inter-service communication | 5672 (AMQP), 15672 (Management) |
| **Ironic API** | REST API for managing bare metal nodes | 6385 |
| **Ironic HTTP** | Serves IPA images and boot ISOs | 6180 |
| **Ironic Conductor** | Executes deployment tasks (scalable) | N/A |
| **IPA Downloader** | Fetches Ironic Python Agent images | N/A |

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd ironic-ansible
```

### 2. Configure Variables

Edit `group_vars/all.yml` to customize your deployment:

```yaml
# Change passwords for production!
mariadb_password: "your_secure_password"
rabbitmq_password: "your_rabbitmq_password"
ironic_admin_password: "your_admin_password"

# Optional: Change image versions
ironic_image_tag: "2024.2"  # or "latest"
```

### 3. Set Up Inventory

Copy the example inventory:

```bash
cp inventory.example inventory
```

Edit `inventory` to match your environment. For local deployment, the default is:

```ini
[ironic]
localhost ansible_connection=local
```

### 4. Deploy Ironic

```bash
# Run the deployment playbook
ansible-playbook playbooks/deploy.yml -i inventory
```

### 5. Verify Deployment

```bash
# Check service status
systemctl status ironic-api
systemctl status ironic-http
systemctl status ironic-conductor@group1
systemctl status ironic-conductor@group2

# Test Ironic API
curl -u admin:<ironic_admin_password> http://localhost:6385/v1/nodes
```

## 📖 Usage

### List Bare Metal Nodes

```bash
curl -u admin:<password> http://<hostname>:6385/v1/nodes
```

### Create a Node (via API)

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "name": "node-01",
    "driver": "redfish",
    "driver_info": {
      "redfish_address": "https://<bmc-ip>",
      "redfish_username": "<bmc-user>",
      "redfish_password": "<bmc-password>"
    },
    "boot_interface": "redfish-virtual-media",
    "deploy_interface": "no-op",
    "network_interface": "noop",
    "inspect_interface": "agent"
  }' \
  -u admin:<password> \
  http://<hostname>:6385/v1/nodes
```

### Run Inspection

```bash
# Start inspection with agent interface
openstack baremetal node inspect node-01
```

### Deploy a Custom ISO

```bash
# 1. Upload your deployment ISO
cp your-iso.iso /var/lib/ironic/http-images/

# 2. Inject ISO via Redfish virtual media
openstack baremetal node set node-01 \
  --properties deploy_isolabel="your-iso.iso"

# 3. Use Redfish API or IPMI to mount the ISO
# and boot from virtual media
```

## 🔧 Configuration

All configuration is centralized in `group_vars/all.yml`. Key sections:

### Container Images

```yaml
ironic_image_repo: "metal3-io"
ironic_image_tag: "2024.2"  # Pin specific version
```

### Database (MariaDB)

```yaml
mariadb_database: "ironic"
mariadb_user: "ironic"
mariadb_password: "secure_password"  # CHANGE IN PRODUCTION
```

### Message Queue (RabbitMQ)

```yaml
rabbitmq_user: "ironic"
rabbitmq_password: "secure_password"  # CHANGE IN PRODUCTION
```

### Ironic API

```yaml
ironic_api_port: 6385
ironic_api_bind_addr: "0.0.0.0"  # or "127.0.0.1" for local only
```

### Boot Interfaces

```yaml
ironic_boot_interface: "redfish-virtual-media,redfish-https"
ironic_deploy_interface: "no-op"
ironic_network_interface: "noop"
ironic_inspect_interface: "agent"
```

## 🔐 Security Considerations

### Default Credentials

**⚠️ IMPORTANT**: Change all default passwords in `group_vars/all.yml` before production deployment:

- `mariadb_password`
- `mariadb_root_password`
- `rabbitmq_password`
- `ironic_admin_password`

### Firewall Rules

If deploying externally, consider:

```bash
# Allow Ironic API
ufw allow 6385/tcp

# Allow HTTP server (for IPA images)
ufw allow 6180/tcp

# Optional: Allow RabbitMQ management
ufw allow 15672/tcp
```

### SSL/TLS

For production deployments, enable SSL/TLS:

```yaml
ironic_enable_ssl: true
ironic_ssl_cert_path: "/etc/ironic/certs/ironic.crt"
ironic_ssl_key_path: "/etc/ironic/certs/ironic.key"
```

## 🐳 Docker Network

The deployment creates a dedicated Docker bridge network named `ironic-network`. All containers communicate over this isolated network.

## 📊 Monitoring

### View Logs

```bash
# Ironic API logs
journalctl -u ironic-api -f

# Conductor logs
journalctl -u ironic-conductor@group1 -f

# Check container logs
docker logs ironic-api
docker logs ironic-conductor-group1
```

### RabbitMQ Management UI

Access at: `http://localhost:15672`

Default credentials: `guest` / `guest` (or configured `rabbitmq_user` / `rabbitmq_password`)

## 🔧 Troubleshooting

### Service Not Starting

```bash
# Check systemd status
systemctl status ironic-api
journalctl -u ironic-api

# Check Docker container
docker ps -a | grep ironic
docker logs ironic-api
```

### Database Connection Issues

```bash
# Check MariaDB container
docker logs ironic-mariadb

# Verify database is running
docker exec ironic-mariadb mysqladmin -u ironic -p status
```

### RabbitMQ Connection Issues

```bash
# Check RabbitMQ container
docker logs ironic-rabbitmq

# Access management UI
curl -u ironic:<rabbitmq_password> http://localhost:15672/api/queues
```

## 🔄 Upgrades

### Update to New Version

```bash
# 1. Update image tag in group_vars/all.yml
# ironic_image_tag: "2024.3"

# 2. Run upgrade playbook
ansible-playbook playbooks/upgrade.yml -i inventory
```

### Full Re-deployment

```bash
# 1. Stop and clean up
ansible-playbook playbooks/destroy.yml -i inventory

# 2. Update configuration as needed

# 3. Re-deploy
ansible-playbook playbooks/deploy.yml -i inventory
```

## 🧹 Cleanup

Remove all components:

```bash
ansible-playbook playbooks/destroy.yml -i inventory
```

This will:
- Stop all services
- Remove all containers
- Delete data directories
- Clean up systemd units

## 📚 References

- [OpenStack Ironic Documentation](https://docs.openstack.org/ironic/latest/)
- [Metal3 Docker Images](https://hub.docker.com/orgs/metal3-io)
- [Ironic Standalone Deployment](https://docs.openstack.org/ironic/latest/install/standalone.html)
- [Redfish Virtual Media](https://www.dmtf.org/standards/redsif)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
