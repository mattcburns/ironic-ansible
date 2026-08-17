# User-supplied lab VM (macOS)

Darwin is operator-only. Nested KVM on macOS is not supported.

1. Install Lima.
2. `limactl start lima/lab.yaml` (nested virtualization on, 16 GiB).
3. Set `ansible_host` / `ansible_user` in `inventory.lab-remote.yml` to the Lima instance.
4. From the Mac:

```bash
ansible-playbook -i inventory.lab-remote.yml playbooks/lab_up.yml --ask-become-pass
```

`lab_up` will not create or destroy that VM. `lab_down` cleans Ironic/sushy/nodes inside it and leaves Lima running.

On Linux, prefer `inventory.lab.yml` so Ansible creates the VM on L0 for you.

Apple Silicon runs an aarch64 Linux VM; current L2 node XML and IPA artifacts are x86_64. That mismatch is later work.
