# macOS lab VM (Lima)

Darwin is operator-only. Ironic, sushy-tools, and the fake BMC guests run
**inside** a Linux VM. Ansible on the Mac talks to that VM over SSH.

## What you need

| Item | Why |
|---|---|
| macOS 15 or newer | Nested virtualization for Linux guests |
| Apple Silicon M3 or later (M5 Pro included), **or** Intel Mac | Nested KVM inside the Lima VM |
| Lima 1.0+ (`brew install lima`) | Creates the Linux VM with `vmType: vz` |
| Ansible 2.14+ on the Mac (`brew install ansible`) | Runs `lab_up` from the Mac |
| 16 GiB free RAM for the VM, ~100 GiB disk | Two nested guests plus Ironic containers |

M1/M2: Lima will start, but nested KVM is not available. `lab_up` will fail the `/dev/kvm` check. Use a Linux box or an M3+ Mac.

Do **not** start an x86_64 Lima VM on Apple Silicon (`arch: x86_64`). That uses QEMU emulation, nested virt is off, and the lab will not get KVM.

## Start the VM

From the repo root:

```bash
brew install lima ansible
limactl start --name=ironic-lab lima/lab.yaml
```

First boot downloads Ubuntu 24.04 (arm64 on Apple Silicon, amd64 on Intel)
and takes several minutes. Confirm nested virt inside the guest:

```bash
limactl shell ironic-lab -- test -e /dev/kvm && echo KVM_OK
limactl shell ironic-lab -- uname -m
```

`uname -m` should be `aarch64` on M5 Pro and `x86_64` on Intel. SSH config lands at
`~/.lima/ironic-lab/ssh.config` (host alias `lima-ironic-lab`).

## Point inventory at Lima

`inventory.lab-remote.yml` is already set for this instance name. If you used a
different `--name`, edit `ansible_host` / the `-F` path to match:

```yaml
ansible_host: lima-ironic-lab
ansible_ssh_common_args: '-F {{ lookup("env", "HOME") }}/.lima/ironic-lab/ssh.config'
```

Check SSH before the playbook:

```bash
ssh -F ~/.lima/ironic-lab/ssh.config lima-ironic-lab 'uname -a && sudo -n true'
```

Lima's default user has passwordless sudo, so `--ask-become-pass` is usually unnecessary.

## Bring the lab up (from the Mac)

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.lab-remote.yml playbooks/lab_up.yml
ansible-playbook -i inventory.lab-remote.yml playbooks/lab_smoke.yml
```

`lab_up` does **not** create or destroy the Lima VM. It installs libvirt/sushy
inside it, deploys Ironic, and enrolls `lab-node-1` / `lab-node-2`.

`lima/lab.yaml` forwards guest 6385 and 8001 to the Mac:

| From the Mac | URL |
|---|---|
| Ironic API | `http://127.0.0.1:6385` (`admin` / `labpass`) |
| Redfish | `http://127.0.0.1:8001/redfish/v1` (`admin` / `password`) |

Inside the VM, guests still use `http://192.168.125.1:6180` for Ironic HTTP.

## Tear down

Cleans Ironic/sushy/nodes **inside** Lima and leaves the VM running:

```bash
ansible-playbook -i inventory.lab-remote.yml playbooks/lab_down.yml
```

Stop or delete the VM itself:

```bash
limactl stop ironic-lab
limactl delete ironic-lab
```

## Architecture notes (Apple Silicon)

L2 `lab-node-*` domains follow the Lima VM architecture (aarch64 on M5 Pro)
so they can use nested KVM. That is enough for Redfish, enroll, and
`lab_smoke.yml`.

IPA and ESP both come from `mattcburns/ironic-iso` `v0.0.30`, which ships
`amd64` and `arm64` assets. Apple Silicon Lima VMs pull the `arm64` kernel,
initramfs, and ESP. Flatcar stays disabled in `group_vars/lab.yml`.
Ubuntu cloud-image arch follows the lab VM (`arm64` on Apple Silicon) for later
direct-deploy experiments.

Ironic and sushy container images may be amd64-only. On aarch64 the playbook
installs `qemu-user-static` so Docker can run them under emulation (slower
than native).

## Troubleshooting

| Symptom | What to check |
|---|---|
| `nested virtualization is not supported` | macOS 15+, M3 or later, `vmType: vz` (recreate the instance; vmType cannot change in place) |
| `/dev/kvm is missing` | Nested virt did not attach. Recreate with `lima/lab.yaml`. M1/M2 cannot nest. |
| SSH: `could not resolve lima-ironic-lab` | Use `-F ~/.lima/ironic-lab/ssh.config` (inventory already does) |
| Port 6385 already allocated | Another Ironic or Lima instance; change `hostPort` in `lima/lab.yaml` and recreate |
| `vmx\|svm` preflight fail | That check is x86-only; current preflight skips it on aarch64 |
| IPA downloader 404 | Confirm `ironic_iso_release_tag` is `v0.0.30+` and `ironic_iso_arch` is `amd64` or `arm64` |
