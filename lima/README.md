# Lima path (macOS later)

The lab treats **one Linux machine** as the host: Docker, libvirt, sushy-tools, and Ironic all run there. On Fedora that host is this laptop. On macOS it should be a Lima VM, not Darwin.

Darwin is operator-only. Nested KVM on macOS is not a goal.

## Intended flow (not the default inventory yet)

1. Install Lima on the Mac.
2. `limactl start lima/lab.yaml`
3. Point `inventory.lab.yml` at the Lima instance over SSH (replace `ansible_connection: local`).
4. From the Mac:  
   `ansible-playbook -i inventory.lab.yml playbooks/lab_up.yml --ask-become-pass`

The Lima template enables nested virtualization and mounts your home directory. Apple Silicon will run an aarch64 Linux VM; the current node XML and IPA artifacts are x86_64. That mismatch is a later problem — do not block the Fedora lab on it.

## What this repo will not do

- Run libvirt on Darwin
- Treat Docker Desktop as a substitute for the lab host
