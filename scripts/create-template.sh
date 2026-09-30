#!/bin/bash
set -euo pipefail                      # stop on errors, on unset variables and on failed pipe parts
cd /root                               # download location for the image

# downloads the official Debian 13 cloud image (qcow2 disk with cloud-init preinstalled)
wget -N https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2

# creates an empty VM 9000: 1 GB RAM, 1 core, NIC on the lab bridge vmbr1, VirtIO SCSI controller, Linux guest
qm create 9000 --name debian13-tpl --memory 1024 --cores 1 \
  --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci --ostype l26

# imports the downloaded image as the VM's first SCSI disk on storage local-lvm
qm set 9000 --scsi0 local-lvm:0,import-from=/root/debian-13-genericcloud-amd64.qcow2

qm set 9000 --ide2 local-lvm:cloudinit          # adds the cloud-init drive (passes user, SSH key, IP to the VM)
qm set 9000 --boot order=scsi0                  # boots from the imported disk
qm set 9000 --serial0 socket --vga serial0      # serial console, required by the Debian cloud image
qm set 9000 --agent enabled=1                   # enables the QEMU guest agent channel (IP display, clean shutdown)
qm set 9000 --ciuser samuel --sshkeys /root/.ssh/id_ed25519.pub   # cloud-init creates user "samuel" with the Ansible key
qm template 9000                                # converts the VM into a read-only template for cloning
