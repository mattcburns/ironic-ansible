# Quick Start Guide

## 🎯 Get Up and Running in 5 Minutes

### Prerequisites Check

```bash
# 1. Verify Docker is installed
docker --version

# 2. Verify Docker is running
docker ps

# 3. Verify Ansible is installed
ansible --version

# 4. Verify you have sudo access
sudo -l
```

### Step 1: Configure Variables

Open `group_vars/all.yml` and change the default passwords:

```bash
nano group_vars/all.yml
```

Change these lines:
```yaml
mariadb_password: "YOUR_MARIADB_PASSWORD"
mariadb_root_password: "YOUR_ROOT_PASSWORD"
rabbitmq_password: "YOUR_RABBITMQ_PASSWORD"
ironic_admin_password: "YOUR_IRONIC_ADMIN_PASSWORD"
```

### Step 2: Create Inventory

```bash
# Copy the example inventory
cp inventory.example inventory

# For local deployment, use the default (already configured):
# [ironic]
# localhost ansible_connection=local
```

### Step 3: Deploy Ironic

```bash
# Run the deployment (takes 5-10 minutes for first run)
ansible-playbook playbooks/deploy.yml -i inventory
```

### Step 4: Verify Installation

```bash
# Check all services are running
systemctl status ironic-api
systemctl status ironic-http
systemctl status ironic-conductor@group1
systemctl status ironic-conductor@group2

# Check Docker containers
docker ps | grep ironic

# Test Ironic API endpoint
curl -u admin:YOUR_IRONIC_ADMIN_PASSWORD http://localhost:6385/v1/nodes
```

Expected output: `[]` (empty list of nodes)

### Step 5: Add Your First Node

```bash
# Create a bare metal node
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "node-01",
    "driver": "redfish",
    "driver_info": {
      "redfish_address": "https://<BMC_IP>",
      "redfish_username": "<BMC_USER>",
      "redfish_password": "<BMC_PASS>"
    },
    "boot_interface": "redfish-virtual-media",
    "deploy_interface": "ramdisk",
    "network_interface": "noop",
    "inspect_interface": "agent"
  }' \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes
```

### Step 6: Run Inspection

```bash
# Start inspection with agent interface
curl -X PATCH \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "inspect_interface": "agent"
    }
  }' \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes/node-01

# Trigger inspection
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"state": "active", "inspect": true}' \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes/node-01/manage

# Check inspection progress
curl -X GET \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes/node-01

# View inspection results
curl -X GET \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes/node-01
```

### Step 7: Deploy Operating System

```bash
# 1. Prepare your deployment ISO
# (Example: Fedora CoreOS, Ubuntu, etc.)

# 2. Upload ISO to HTTP server
sudo cp your-iso.iso /var/lib/ironic/http-images/

# 3. Set the deploy ISO label
curl -X PATCH \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "deploy_isolabel": "your-iso.iso"
    }
  }' \
  -u admin:YOUR_IRONIC_ADMIN_PASSWORD \
  http://localhost:6385/v1/nodes/node-01

# 4. Inject ISO via Redfish virtual media
# Use Redfish API or IPMI to mount the ISO

# 5. Reboot the node
# The node will boot from the ISO and install the OS
```

## 🔧 Common Issues

### Docker not running
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Port already in use
Edit `group_vars/all.yml` and change the port:
```yaml
ironic_api_port: 8080
ironic_http_port: 8081
```

### Permission denied on htpasswd
```bash
sudo apt-get install apache2-utils  # For htpasswd command
```

### Services not starting
```bash
# Check logs
journalctl -u ironic-api -f
journalctl -u ironic-http -f

# Check Docker logs
docker logs ironic-api
docker logs ironic-mariadb
```

## 🎓 Next Steps

1. **Configure Firewall**: Open ports for external access
2. **Enable SSL/TLS**: For production deployments
3. **Scale Conductors**: Add more conductor instances
4. **Integrate Keystone**: For enterprise authentication
5. **Set up Monitoring**: Prometheus, Grafana

## 📚 Additional Resources

- [README.md](README.md) - Full documentation
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Project organization
- [INITIAL_PHASED_PLAN.md](INITIAL_PHASED_PLAN.md) - Implementation plan
- [OpenStack Ironic Docs](https://docs.openstack.org/ironic/latest/)

## 🆘 Need Help?

```bash
# View deployment logs
journalctl -u ironic-api -n 50
journalctl -u ironic-conductor@group1 -n 50

# Check container health
docker ps -a

# Validate configuration
ansible-playbook playbooks/validate.yml -i inventory -v
```
