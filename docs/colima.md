# Local Docker with Colima

## Why Colima

Harbor runs every trial in Docker containers through `docker compose` and `buildx`, so a local run needs a Docker Engine. On macOS this repo uses [Colima](https://github.com/abiosoft/colima):

- It is free and open source (MIT), and has no Docker Desktop licence or GUI.
- It runs the Docker Engine in a small Linux VM (Lima on Apple's Virtualization framework, `vmType: vz`) with `virtiofs` mounts, which is fast on Apple silicon.
- It is driven entirely from the CLI, so CPU, memory and disk can be sized for many concurrent trials and scripted the same way on every laptop.
- The `docker` CLI, compose and buildx work as they do on a Linux host, so the same Harbor commands run locally and on EC2.

Settings used here: 10 CPUs, 24 GiB memory, 100 GiB disk, `vz`, `virtiofs`, `aarch64`.

```bash
colima start --cpu 10 --memory 24 --disk 100 --vm-type vz --mount-type virtiofs --arch aarch64 --runtime docker
docker info --format '{{.ServerVersion}} {{.NCPU}} cpus'
```

## Incident: VM disk I/O errors (2026-10-22)

### Symptoms

- Every Harbor trial failed during `docker compose build` with
  `failed to solve: write /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db: input/output error`.
- `docker system df` failed with `blob sha256:... input/output error`.
- `colima ssh -- df -h /` failed with `/bin/bash: Input/output error`.
- The Lima host-agent log (`~/.colima/_lima/colima/ha.stderr.log`) repeated
  `fork/exec /usr/sbin/iptables: input/output error` every 3 seconds, starting at 2026-10-21 20:17:33. This was also the last time the VM disk file (`~/.colima/_lima/colima/diffdisk`) was modified.

### Cause

The macOS data volume was 97% full (15 GiB free). The VM disk is a sparse 100 GiB file that had grown to about 40 GiB. Writes from the VM started failing at the time shown above, and the VM's root filesystem was left unreadable. The low free space on the host is the most likely trigger: the timing matches, but there was no log line that proved it.

### Fix

1. `colima stop` (clean, 8 s), then `colima start`. **This did not help.** The VM booted, but SSH inside the guest never came up, and `colima start` gave up after 10 minutes (`did not receive an event with the "running" status`).
2. Deleted and recreated the VM with the same settings. **This removes every image, container and volume in the VM.**
   ```bash
   cp ~/.colima/default/colima.yaml /tmp/colima-default-backup.yaml
   colima stop --force
   colima delete --force
   colima start --cpu 10 --memory 24 --disk 100 --vm-type vz --mount-type virtiofs --arch aarch64 --runtime docker
   docker run --rm ubuntu:24.04 echo ok
   ```
   The new VM started in 22 s. Deleting the old disk freed about 40 GiB on the Mac (97% → 85% used).

### Prevention

- Keep at least 30 GiB free on the Mac: `df -h /System/Volumes/Data`.
- Check VM usage with `docker system df`. Harbor builds one image per task (`hb__*`), and agent installs add more data per trial. Remove the images your own runs created when you are done with them.
- Space freed inside the VM goes back to macOS only after a trim:
  ```bash
  colima ssh -- sudo fstrim -v /
  ```
- If `colima ssh` itself returns `Input/output error`, the VM disk is gone. Save what you need from mounted host paths, then recreate the VM as shown above.
