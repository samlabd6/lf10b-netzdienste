#!/bin/bash
# Usage: create-vm.sh <name> <vmid> <ip|dhcp> [mac] [disk] [mem] [cores] [nameserver]
set -euo pipefail                          # stop on the first error
NAME=$1; VMID=$2; IP=$3                    # required parameters: VM name, VM ID, IP or "dhcp"
MAC=${4:-}; DISK=${5:-10G}; MEM=${6:-1024}; CORES=${7:-1}   # optional parameters with defaults
NS=${8:-1.1.1.1}                           # DNS server for static VMs; use the school/home DNS if external DNS is blocked

qm clone 9000 "$VMID" --name "$NAME" --full               # full independent copy of the template
qm set "$VMID" --memory "$MEM" --cores "$CORES"           # sets RAM (MB) and CPU cores
if [ -n "$MAC" ]; then                                    # only if a MAC address was given
  qm set "$VMID" --net0 "virtio=$MAC,bridge=vmbr1"        # fixed MAC, needed for the DHCP reservation
fi
if [ "$IP" = "dhcp" ]; then
  qm set "$VMID" --ipconfig0 ip=dhcp                      # cloud-init configures the NIC for DHCP
else
  qm set "$VMID" --ipconfig0 "ip=$IP/24,gw=10.10.10.1" \
                 --nameserver "$NS" --searchdomain lab.intern   # static IP, gateway, DNS server and search domain
fi
qm resize "$VMID" scsi0 "$DISK"                           # grows the disk to the requested size
qm set "$VMID" --onboot 1                                 # starts the VM automatically when the host boots
qm start "$VMID"                                          # starts the VM
