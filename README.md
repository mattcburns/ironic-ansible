# Standalone OpenStack Ironic Deployment via Ansible

A complete Ansible-based deployment solution for running OpenStack Ironic in standalone mode using Docker containers managed by systemd. This deployment uses **virtual media booting** and **Redfish-based inspection** - eliminating the need for PXE, DHCP, or a separate inspector service.

## 🚀 Features

- ✅ **Docker-based deployment**: All Ironic components run in isolated containers
- ✅ **Systemd management**: Services persist across reboots with automatic restart
- ✅ **No PXE/DHCP required**: Uses Redfish virtual media and HTTP boot
- ✅ **Built-in inspection**: No separate ironic-inspector service needed
- ✅ **HTTP Basic Auth**: Simple authentication with htpasswd
- ✅ **Containerized CLI helper**: Run `openstack baremetal` via `ironic-cli` without host package installs
- ✅ **Generated `clouds.yaml` profile**: Ansible writes `/etc/openstack/clouds.yaml` for `--os-cloud` auth
- ✅ **Generated `QUICKSTART.md` cheat sheet**: Ansible writes command snippets and resolved URLs/paths to `/etc/ironic/QUICKSTART.md`
- ✅ **Ubuntu LTS image mirror**: Downloads and serves a Ubuntu LTS cloud image for provisioning (default pinned to 24.04)
- ✅ **Flatcar ramdisk artifact mirror (optional)**: Downloads and serves Flatcar live-boot kernel/initramfs artifacts for ramdisk deployments
- ✅ **Scalable conductors**: Systemd unit templates for dynamic conductor scaling
- ✅ **Production-ready**: MariaDB and RabbitMQ for persistence and messaging

## ⚠️ Compatibility Policy

This project currently prioritizes deployment simplicity over backward compatibility.
Defaults and variable shapes may change between iterations, so review `group_vars/all.yml`
and docs before applying updates to existing environments.

## 📋 Prerequisites

- **Operating System**: Linux host with systemd (tested on Ubuntu 22.04+)
- **Docker**: Docker Engine 24.0+ installed and running
- **Ansible**: Ansible 2.14+ installed on the control node
- **Ansible collections**: Install from `requirements.yml`
- **htpasswd utility**: Required for HTTP Basic Auth file generation (e.g. `apache2-utils`)
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
| **Ironic CLI Helper** | Wrapper script that runs CLI tools in a container | N/A |
| **IPA Downloader** | Fetches Ironic Python Agent images | N/A |
| **OS Image Downloader** | Fetches and serves Ubuntu direct-deploy images and optional Flatcar ramdisk live-boot artifacts | N/A |

## 📁 Repository Layout (Current)

The repository is organized around reusable Ansible roles and consolidated playbooks:

```text
.
├── group_vars/all.yml
├── scripts/generate-passwords.sh
├── requirements.yml
├── playbooks/
│   ├── deploy.yml
│   ├── validate.yml
│   ├── upgrade.yml
│   ├── destroy.yml
│   └── rollback.yml
└── roles/
    ├── common
    ├── mariadb
    ├── rabbitmq
    ├── ipa_downloader
    ├── ironic_common
    ├── ironic_http
    ├── ironic_api
    ├── ironic_cli
    └── ironic_conductor
```

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd ironic-ansible
```

### 2. Install Ansible Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 3. Configure Variables

Generate deployment passwords before first deploy:

```bash
./scripts/generate-passwords.sh
```

This updates the required password values in `group_vars/all.yml` and writes a
backup to `group_vars/all.yml.bak`. Then edit `group_vars/all.yml` for any
additional customization:

```yaml
# Passwords are generated by scripts/generate-passwords.sh
# Optional: set a custom length before running, for example:
# PASSWORD_LENGTH=48 ./scripts/generate-passwords.sh

# Optional: Override image versions
ironic_image_repo: "ghcr.io/mattcburns"
ironic_image_name: "ironic-standalone"
ironic_image_tag: "master"  # default branch tag; pin to a vX.Y.Z release tag when available
```

### 4. Set Up Inventory

Copy the example inventory:

```bash
cp inventory.example inventory
```

Edit `inventory` to match your environment. For local deployment, the default is:

```ini
[ironic]
localhost ansible_connection=local
```

### 5. Deploy Ironic

```bash
# Run the deployment playbook
ansible-playbook playbooks/deploy.yml -i inventory
```

### 6. Verify Deployment

```bash
# Check service status
systemctl status ironic-mariadb
systemctl status ironic-rabbitmq
systemctl status ironic-api
systemctl status ironic-http
systemctl status ironic-conductor@1

# Test Ironic API
curl -u admin:<ironic_admin_password> http://localhost:6385/v1/nodes

# Optional: run validation checks directly
ansible-playbook playbooks/validate.yml -i inventory

# Use the containerized CLI helper
ironic-cli node list

# If openstackclient is installed on the host, use the generated cloud profile
openstack --os-cloud ironic baremetal node list

# Review generated quickstart commands and resolved paths/URLs
cat /etc/ironic/QUICKSTART.md
```

## 📖 Usage

### List Bare Metal Nodes

```bash
curl -u admin:<password> http://<hostname>:6385/v1/nodes
```

### Run Bare Metal Commands via Containerized CLI

```bash
# Defaults to: openstack baremetal <args>
ironic-cli node list

# Run explicit OpenStack CLI command
ironic-cli openstack baremetal node show <node-id>

# Open an interactive shell in the CLI container
ironic-cli shell
```

`ironic-cli` bind-mounts your current working directory into the container at
the same path and uses it as the container working directory, so local files
such as `network-data.json` can be passed directly to baremetal commands that
accept file path arguments.

### Use Native OpenStack CLI with Generated Cloud Profile

```bash
# Uses /etc/openstack/clouds.yaml generated by the deploy playbook
openstack --os-cloud ironic baremetal node list
```

### Enrolling and Provisioning a Node

1. Enroll the node by creating it in the API: `ironic-cli node create --driver redfish --driver-info redfish_address=<redfish https endpoint> --driver-info redfish_username=<bmc user> --driver-info redfish_password=<bmc password> --driver-info redfish_verify_ca=False`
1. Make the node manageable: `ironic-cli node manage <node id>`
1. Apply the network data for cleaning (you can find a template in `server_templates/`): `ironic-cli node set --network-data network_data.json <node id>`
1. Make the node available for provisioning and trigger a cleaning: `ironic-cli node provide <node id>`
1. Configure the OS image to provision for direct deploy (Ubuntu example): `ironic-cli node set <node id> --instance-info image_type=whole-disk --instance-info image_disk_format=qcow2 --instance-info image_source=http://<ironic-host>:6180/ubuntu/noble-server-cloudimg-amd64.img --instance-info image_os_hash_algo=sha256 --instance-info image_os_hash_value=$(curl -fsSL http://<ironic-host>:6180/ubuntu/noble-server-cloudimg-amd64.img.sha256)`
1. Provision the node: `ironic-cli node deploy <node id> --configdrive <some cloudinit json, optional>`

### Flatcar Ramdisk Deployment with Ignition
Use this when you want a ramdisk-based workflow and need to pass Ignition URL kernel arguments on deploy.
1. Ensure `ramdisk` deploy interface is enabled in `group_vars/all.yml` (`ironic_enabled_deploy_interfaces: "direct,ramdisk"` already includes it by default).
1. Quick demo path: use the sample Ignition in this repo, `server_templates/flatcar-demo.ign`, via raw URL: `https://raw.githubusercontent.com/mattcburns/ironic-ansible/master/server_templates/flatcar-demo.ign` (replace `master` if testing from a different branch/tag).
1. Local mirror path: deploy seeds a default sample Ignition at `flatcar_ignition_local_path` and serves it at `flatcar_ignition_http_url` (default `http://<ironic-host>:6180/flatcar/config.ign`). Replace the local file contents if you want custom Ignition behavior while keeping the same URL.
1. Set ramdisk deploy mode and Flatcar boot artifacts for the demo:
   - `ironic-cli node set <node id> --deploy-interface ramdisk`
   - `ironic-cli node set <node id> --instance-info kernel=http://<ironic-host>:6180/flatcar/flatcar_production_image.vmlinuz --instance-info ramdisk=http://<ironic-host>:6180/flatcar/flatcar_production_image.bin.bz2 --instance-info ramdisk_kernel_arguments="flatcar.first_boot=1 ignition.config.url=https://raw.githubusercontent.com/mattcburns/ironic-ansible/master/server_templates/flatcar-demo.ign"`
1. Optional: host your own Ignition config at any URL and set `ignition.config.url` to that location.
1. Deploy the node: `ironic-cli node deploy <node id>`

Note: ramdisk deploy boots the supplied kernel/initramfs workload from memory and does not perform a persistent whole-disk image write.
The demo Ignition writes `/etc/flatcar-demo.txt` so you can quickly verify that Ignition applied.
The sample also configures a demo login for validation: username `demo`, password `demo-password` (intentionally insecure; demo use only).
Flatcar release artifact names can vary by channel/release; if needed, override `flatcar_ramdisk_kernel_source_url` and `flatcar_ramdisk_initramfs_source_url` in `group_vars/all.yml` to match your target release.


## 🔧 Configuration

All configuration is centralized in `group_vars/all.yml`. Key sections:

### Container Images

```yaml
ironic_image_repo: "ghcr.io/mattcburns"
ironic_image_name: "ironic-standalone"
ironic_image_tag: "master"
mariadb_image: "mariadb:11.4"
rabbitmq_image: "rabbitmq:3.13-management"
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

### Containerized Ironic CLI Helper

```yaml
ironic_cli_enabled: true
ironic_cli_wrapper_path: "/usr/local/bin/ironic-cli"
ironic_cli_image: "ghcr.io/mattcburns/ironic-cli:latest"
ironic_cli_network_name: "host"
ironic_cli_endpoint: "http://127.0.0.1:{{ ironic_api_port }}"
ironic_cli_auth_type: "http_basic"  # or "v3password" / "none"
```

### OpenStack clouds.yaml Profile

```yaml
ironic_clouds_yaml_enabled: true
ironic_clouds_yaml_path: "/etc/openstack/clouds.yaml"
ironic_cloud_name: "ironic"
ironic_cloud_interface: "public"
ironic_cloud_region_name: "RegionOne"
```

### Generated QUICKSTART Cheat Sheet

```yaml
ironic_quickstart_enabled: true
ironic_quickstart_path: "{{ ironic_etc_dir }}/QUICKSTART.md"
```

### Boot Interfaces

```yaml
ironic_enabled_boot_interfaces: "redfish-virtual-media,redfish-https"
ironic_default_boot_interface: "redfish-virtual-media"
ironic_enabled_deploy_interfaces: "direct,ramdisk"
ironic_default_deploy_interface: "direct"
ironic_esp_image_release_tag: "v0.0.27"
ironic_esp_image_filename: "esp.img"
ironic_esp_image_url: "https://github.com/mattcburns/ironic-iso/releases/download/{{ ironic_esp_image_release_tag }}/{{ ironic_esp_image_filename }}"
ironic_grub_config_path: "EFI/centos/grub.cfg"
ironic_bootloader: "file:///shared/html/{{ ironic_esp_image_filename }}"
ironic_bootloader_by_arch: ""
ironic_file_url_allowed_paths: ""
ironic_ipa_kernel_append_params: "nofb vga=normal"
ironic_ipa_ssh_public_key: ""  # optional: inject one debug SSH key into IPA
ironic_enabled_network_interfaces: "noop"
ironic_default_network_interface: "noop"
ironic_enabled_inspect_interfaces: "redfish,no-inspect"
ironic_default_inspect_interface: "redfish"
```
The defaults above are aligned for `ghcr.io/mattcburns/ironic-standalone`.
ESP image artifacts are downloaded from the tagged release in
`mattcburns/ironic-iso` and exposed to the conductor via
`file:///shared/html/{{ ironic_esp_image_filename }}`. This keeps deploy and
clean flows on Ironic's runtime ISO-building path without requiring `deploy_iso`.
If you replace the ESP source, update both `ironic_esp_image_url` and
`ironic_grub_config_path` to match the GRUB binary embedded in that image.
Set `ironic_ipa_ssh_public_key` to a public key when you need shell access to
the IPA live ramdisk during clean/deploy/inspect debugging. This maps to
Ironic kernel append parameters (`sshkey="..."`) and supports one key.

### Provisioning Image Mirror (Ubuntu LTS)

```yaml
ubuntu_lts_image_enabled: true
ubuntu_lts_image_url: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-{{ ubuntu_lts_image_arch }}.img"  # default pin: Ubuntu 24.04 LTS
ubuntu_lts_meta_release_url: "https://changelogs.ubuntu.com/meta-release-lts"
ubuntu_lts_image_arch: "amd64"
ubuntu_lts_image_disk_format: "qcow2"  # set to "raw" only if ubuntu_lts_image_url points to a raw artifact
ubuntu_lts_image_directory: "{{ ironic_http_images_dir }}/ubuntu"
ubuntu_lts_image_filename: "{{ ubuntu_lts_image_url | regex_replace('^.*/', '') | regex_replace('\\?.*$', '') }}"  # derived from upstream URL basename
ubuntu_lts_image_http_url: "http://{{ ironic_api_host }}:{{ ironic_http_port }}/ubuntu/{{ ubuntu_lts_image_filename }}"
ubuntu_lts_image_checksum_http_url: "{{ ubuntu_lts_image_http_url }}.sha256"
```

When `ubuntu_lts_image_enabled` is true, deploy downloads a cloud image into
`{{ ubuntu_lts_image_directory }}` and writes a SHA256 checksum file alongside
it. The mirrored filename is derived from the upstream image URL basename
(`ubuntu_lts_image_url`), so codename-based names always match the downloaded
artifact. Set `ubuntu_lts_image_url` to an empty string if you want to
auto-resolve the latest LTS dynamically from `ubuntu_lts_meta_release_url`.
Use `ubuntu_lts_image_disk_format=qcow2` for the default Ubuntu cloud image,
or set it to `raw` when mirroring a raw artifact URL.
The deploy summary prints both HTTP URLs so you can use them directly with
`--instance-info image_source`, `image_disk_format`, and SHA256
`image_os_hash_*` fields.

### Provisioning Image Mirror (Flatcar)

```yaml
flatcar_image_enabled: true
flatcar_image_directory: "{{ ironic_http_images_dir }}/flatcar"
flatcar_ignition_filename: "config.ign"
flatcar_ignition_local_path: "{{ flatcar_image_directory }}/{{ flatcar_ignition_filename }}"
flatcar_ignition_http_url: "http://{{ ironic_api_host }}:{{ ironic_http_port }}/flatcar/{{ flatcar_ignition_filename }}"
flatcar_ramdisk_kernel_source_url: "https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_image.vmlinuz"
flatcar_ramdisk_initramfs_source_url: "https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_image.bin.bz2"
flatcar_ramdisk_kernel_filename: "{{ (flatcar_ramdisk_kernel_source_url.split('?') | first) | basename }}"
flatcar_ramdisk_initramfs_filename: "{{ (flatcar_ramdisk_initramfs_source_url.split('?') | first) | basename }}"
flatcar_ramdisk_kernel_http_url: "http://{{ ironic_api_host }}:{{ ironic_http_port }}/flatcar/{{ flatcar_ramdisk_kernel_filename }}"
flatcar_ramdisk_initramfs_http_url: "http://{{ ironic_api_host }}:{{ ironic_http_port }}/flatcar/{{ flatcar_ramdisk_initramfs_filename }}"
flatcar_ramdisk_kernel_url: "{{ flatcar_ramdisk_kernel_http_url }}"
flatcar_ramdisk_initramfs_url: "{{ flatcar_ramdisk_initramfs_http_url }}"
flatcar_ramdisk_kernel_params: "flatcar.first_boot=1 ignition.config.url={{ flatcar_ignition_http_url }}"
```
Set `flatcar_image_enabled=true` to mirror Flatcar ramdisk live-boot artifacts via the OS image downloader.
Ramdisk deploy artifacts are mirrored from `flatcar_ramdisk_*_source_url` and exposed via
`flatcar_ramdisk_kernel_http_url` / `flatcar_ramdisk_initramfs_http_url`, so deployment
commands can use local HTTP URLs instead of upstream release URLs.
Deploy also seeds `flatcar_ignition_local_path` from `server_templates/flatcar-demo.ign` when
that file does not already exist, so `flatcar_ignition_http_url` is immediately usable for
the QUICKSTART ramdisk workflow.
For ramdisk-based workflows, `flatcar_ramdisk_*` and `flatcar_ignition_*` provide
defaults for kernel/initramfs boot and Ignition URL injection.

### Conductor Scaling (Simple Default)

```yaml
ironic_conductor_replicas: 1

# Default green-thread pool size applied to every conductor instance.
ironic_conductor_default_workers: 128

# Enable automated cleaning when nodes move to available state.
ironic_automated_clean: true
```

Increase `ironic_conductor_replicas` to scale conductor instances in the default mode.
Instances are named `ironic-conductor@1`, `ironic-conductor@2`, and so on.

### Advanced: Conductor Groups (Optional)

```yaml
ironic_conductor_groups:
  - name: "group1"                # uses ironic_conductor_default_workers
  - name: "group2"
    workers: 256                   # per-group override
```

Set `ironic_conductor_groups` only when you need targeted scheduling via
`conductor_group`. In grouped mode, each group inherits
`ironic_conductor_default_workers` unless an explicit `workers` value is set.
The pool size must exceed the minimum Ironic calculates from the number of
enabled hardware types and interfaces; 128 provides comfortable headroom for
the default driver set.

## 🔐 Security Considerations

### Default Credentials

**⚠️ IMPORTANT**: Change all default passwords in `group_vars/all.yml` before production deployment:

- `mariadb_password`
- `mariadb_root_password`
- `rabbitmq_password`
- `ironic_admin_password`

### Credential Storage

MariaDB and RabbitMQ credentials are stored in env files under `/etc/ironic/` with
mode `0600` (root-only). They are **not** embedded in the systemd unit files.

### Firewall Rules

MariaDB (3306) and RabbitMQ (5672/15672) bind to `127.0.0.1` by default and are
not exposed to the network. Only the Ironic API and HTTP server need external access:

```bash
# Allow Ironic API
ufw allow 6385/tcp

# Allow HTTP server (for IPA images / virtual media boot ISOs)
ufw allow 6180/tcp
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
journalctl -u ironic-conductor@1 -f

# Check container logs
docker logs ironic-api
docker logs ironic-conductor-1
```

### RabbitMQ Management UI
The management UI is exposed on `127.0.0.1:15672` on the target host.

For a remote deployment, create a local SSH tunnel:

```bash
ssh -L 15672:127.0.0.1:15672 <ssh-user>@<ironic-host>
```

Then access:

- `http://localhost:15672`
- `http://localhost:15672/#/queues` (direct queues view)

Use the configured `rabbitmq_user` / `rabbitmq_password` credentials.

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
# ironic_image_tag: "v36.0.0"

# 2. Run upgrade playbook
ansible-playbook playbooks/upgrade.yml -i inventory
```

### Full Re-deployment

```bash
# 1. Stop and clean up
ansible-playbook playbooks/rollback.yml -i inventory

# 2. Update configuration as needed

# 3. Re-deploy
ansible-playbook playbooks/deploy.yml -i inventory
```

## 🧹 Cleanup

Remove deployed services and data:

```bash
ansible-playbook playbooks/destroy.yml -i inventory
```

This will:
- Stop all services
- Remove all containers
- Delete data directories
- Clean up systemd units

For a full host rollback (including deployment images and the htpasswd prerequisite package), run:

```bash
ansible-playbook playbooks/rollback.yml -i inventory
```

## 📚 References

- [OpenStack Ironic Documentation](https://docs.openstack.org/ironic/latest/)
- [Ironic Standalone Container Repository](https://github.com/mattcburns/ironic-standalone)
- [Ironic ISO / ESP Artifact Repository](https://github.com/mattcburns/ironic-iso)
- [Ironic Standalone Deployment](https://docs.openstack.org/ironic/latest/install/standalone.html)
- [Redfish Virtual Media](https://www.dmtf.org/standards/redfish)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
