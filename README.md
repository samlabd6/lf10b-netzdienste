# lf10b-netzdienste

Praxisprojekt LF10b (Serverdienste bereitstellen, Backup, Monitoring, Wiederanlauf), 30.09. bis 02.10.2026, Samuel Ararsa.

Ein DHCP-Dienst auf Basis von **ISC Kea** läuft in einem eigenen Labornetz auf **Proxmox VE**. Die Server werden aus einem cloud-init-Template erzeugt und vollständig mit **Ansible** konfiguriert. Gesichert wird zweistufig mit **vzdump** (VM-Images, lokal) und **Restic** (inkrementell, verschlüsselt, offsite in **Backblaze B2**). Überwacht wird mit **Prometheus** und **CheckMK**; Alarme gehen an **Discord**.

## Architektur

```
 Heimnetz 192.168.88.0/24 (Router mit eigenem DHCP)
        │
   vmbr0: 192.168.88.110   Proxmox-Host "Spencer" (Hypervisor, NAT, Ansible, vzdump)
        │  Routing + NAT (MASQUERADE)
   vmbr1: 10.10.10.1/24    Labornetz, ohne physischen Port
        │
   ├── net01    10.10.10.10   Kea DHCPv4, kea-exporter, Restic
   ├── mon01    10.10.10.20   Prometheus, CheckMK (Docker Compose), Restic
   └── client01 10.10.10.50   Testclient (DHCP-Reservierung)
                     │
              Backblaze B2 (Bucket lf10b-backup, S3-API)  ◄── Restic stündlich
```

| System | VM-ID | IP | Aufgabe |
|---|---|---|---|
| Proxmox-Host | | 192.168.88.110 / 10.10.10.1 | Virtualisierung, NAT-Gateway, Ansible-Controller, vzdump |
| Template | 9000 | | Debian 13 genericcloud mit cloud-init (User `samuel`, SSH-Key) |
| net01 | 110 | 10.10.10.10 (statisch) | Kea DHCPv4 |
| mon01 | 120 | 10.10.10.20 (statisch) | Monitoring |
| client01 | 130 | 10.10.10.50 (Reservierung per MAC `BC:24:11:00:00:50`) | Testclient |

**DHCP:** Subnetz `10.10.10.0/24`, Pool `10.10.10.100 - 10.10.10.199`, Lease-Zeit 8 h (T1 4 h, T2 7 h), Router `10.10.10.1`.

## Verzeichnisstruktur

```
lf10b-netzdienste/
├── README.md
├── docs/
│   ├── projektplan.md
│   ├── dokumentation.md          Projektdokumentation (Umsetzung, Tests, Probleme)
│   ├── wiederanlaufplan.md       Wiederanlaufplan mit Befehlen
│   ├── reflexion.md              Reflexion des Projektergebnisses
│   └── praesentation.md          Ablauf und Demo-Drehbuch
├── scripts/
│   ├── create-template.sh        Debian-13-Template 9000 anlegen
│   └── create-vm.sh              VM aus dem Template klonen (IP oder DHCP)
├── checkmk/
│   ├── docker-compose.yml        CheckMK-Server (Passwort steht nur im Vault)
│   └── local-checks/             eigene CheckMK-Checks je Host
└── ansible/
    ├── ansible.cfg
    ├── inventory.ini
    ├── site.yml                  kompletter Aufbau aller Server
    ├── update.yml                Vollupdate aller Server nacheinander
    ├── group_vars/all/main.yml   Netz, DHCP, B2-Endpunkt
    ├── group_vars/all/vault.yml  Geheimnisse (verschlüsselt)
    └── roles/
        ├── common/               Basispakete, Zeitzone, Guest-Agent, node_exporter
        ├── kea/                  Kea DHCPv4 aus Template, Validierung vor Aktivierung
        ├── exporters/            kea-exporter für Prometheus
        ├── monitoring/           Prometheus, Alarmregeln, Discord-Benachrichtigung
        └── restic/               Backup nach B2, stündlicher Timer, Status-Datei
```

## Schnellstart (Neuaufbau)

Voraussetzungen: Proxmox mit `vmbr1` und NAT, `git` und `ansible` auf dem Host, SSH-Key `/root/.ssh/id_ed25519`, Vault-Passwort in `/root/.vault-pass`.

```bash
git clone git@github.com:<user>/lf10b-netzdienste.git /root/lf10b-netzdienste   # Repository holen
cd /root/lf10b-netzdienste
./scripts/create-template.sh                                          # Template 9000 (einmalig)
./scripts/create-vm.sh net01 110 10.10.10.10 "" 10G 1024 1            # DHCP-Server
./scripts/create-vm.sh mon01 120 10.10.10.20 "" 25G 4096 2            # Monitoring-Server
cd ansible
ansible-playbook site.yml --check --diff                              # Änderungen prüfen
ansible-playbook site.yml                                             # alles ausrollen
../scripts/create-vm.sh client01 130 dhcp BC:24:11:00:00:50 8G 1024 1   # Testclient, bekommt 10.10.10.50
```

## Betrieb

| Aufgabe | Befehl |
|---|---|
| Konfiguration ausrollen | `ansible-playbook site.yml` |
| Änderung vorher prüfen | `ansible-playbook site.yml --check --diff` |
| Änderung zurücknehmen | `git revert <commit>` und `ansible-playbook site.yml` |
| Vollupdate aller Server | `ansible-playbook update.yml` (zusätzlich wöchentlich per Cron) |
| Backup sofort ausführen | `ssh samuel@10.10.10.10 sudo systemctl start restic-backup.service` |
| Snapshots in B2 anzeigen | `ssh samuel@10.10.10.10 sudo restic-cloud snapshots` |
| VM-Images anzeigen | `ls -lh /var/lib/vz/dump/` |
| CheckMK öffnen | `ssh -L 8080:10.10.10.20:8080 root@192.168.88.110`, dann `http://localhost:8080/cmk/` |
| Prometheus öffnen | `ssh -L 9090:10.10.10.20:9090 root@192.168.88.110`, dann `http://localhost:9090` |

## Backup

| Ebene | Werkzeug | Was | Wann | Aufbewahrung | Ort |
|---|---|---|---|---|---|
| A | vzdump (Snapshot, zstd) | komplette VMs 110 und 120 | täglich 02:00 | letzte 3 | Proxmox, Storage `local` |
| B | Restic (S3-API) | net01: `/etc/kea`, `/var/lib/kea`; mon01: `/etc/prometheus`, `/opt/checkmk`, `/opt/checkmk-backup` | stündlich | 24 stündlich, 7 täglich, 4 wöchentlich | Backblaze B2 `lf10b-backup` |
| | `omd backup` | CheckMK-Konfiguration | täglich 01:30 | 1 (wird von Restic versioniert) | mon01, danach B2 |

Die Konfiguration selbst liegt in Git (RPO 0). Wiederherstellung: siehe [docs/wiederanlaufplan.md](docs/wiederanlaufplan.md).

## Monitoring

| Was | Prometheus | CheckMK |
|---|---|---|
| CPU, RAM, Plattenplatz, Netzwerk | node_exporter | Agent (automatisch erkannt) |
| DHCP-Pool-Auslastung | kea-exporter | Local Check `kea_pool` |
| Kea-Dienst | Target `kea` | Local Check `kea_service` |
| Restic-Backup | `restic_backup_success`, Alter | Local Check `restic_status` |
| vzdump-Backup | `vzdump_last_success_timestamp_seconds` | Local Check `vzdump_status` |
| Benachrichtigung | `prometheus-notify` (Timer) an Discord | Slack-Plugin an Discord-Webhook (`/slack`) |

## Geheimnisse

Alle Passwörter und Schlüssel liegen ausschließlich in `ansible/group_vars/all/vault.yml` (Ansible Vault). Das Vault-Passwort liegt in `/root/.vault-pass` auf dem Proxmox-Host **und** außerhalb der Infrastruktur im Passwortmanager. Ohne Vault-Passwort und Restic-Passwort ist das Offsite-Backup nicht wiederherstellbar.

## Dokumentation

- [Projektplan](docs/projektplan.md)
- [Projektdokumentation](docs/dokumentation.md)
- [Wiederanlaufplan](docs/wiederanlaufplan.md)
- [Reflexion](docs/reflexion.md)
- [Präsentation](docs/praesentation.md)
