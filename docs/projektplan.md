# Projektplan LF10b: Hochverfügbare Netzdienste mit Kea DHCP, BIND 9 und NTP

| | |
|---|---|
| **Autor** | Samuel Ararsa |
| **Lernfeld** | LF10b, Serverdienste bereitstellen und Administrationsaufgaben automatisieren |
| **Umfang** | 3 × 6 UE (Mi 30.09. bis Fr 02.10.2026) |
| **Vorstellung Plan** | Di 29.09.2026 |
| **Präsentation** | Mo 05.10.2026 |
| **Status** | Entwurf v0.1 |

---

## 1. Projektbeschreibung

Im Projekt baue ich eine kleine, vollständig automatisierte Netzdienst-Infrastruktur für ein fiktives Firmennetz auf. Kern ist ein DHCP-Server auf Basis von ISC Kea, der den Nachfolger des seit Ende 2022 nicht mehr gepflegten ISC DHCP darstellt. Ergänzt wird er durch einen DNS-Server (BIND 9) für die interne Zone `lab.intern` sowie einen Zeitserver (chrony), da DHCP, DNS und NTP in der Praxis eng zusammengehören. Die Dienste laufen als virtuelle Maschinen auf einem Proxmox-VE-Host in einem vom Schulnetz getrennten Labornetz, damit kein fremder DHCP-Server im Schulnetz auftaucht. Die gesamte Konfiguration wird mit Ansible aus einem Git-Repository ausgerollt, sodass das System jederzeit reproduzierbar neu aufgebaut werden kann. Für die Datensicherung setze ich eine Kombination aus VM-Image-Backups (Proxmox vzdump) und verschlüsselten, deduplizierten Datei-Backups mit Restic ein. Ein Monitoring-Stack aus Prometheus, Grafana und Alertmanager überwacht Hosts, Dienste, DHCP-Pool-Auslastung und das Alter der letzten Sicherung. Abschließend teste ich den Wiederanlauf praktisch, messe die tatsächliche Wiederherstellungszeit und vergleiche sie mit dem geplanten RTO.

## 2. Ziele (persönliche Motivation)

1. Kea DHCP produktionsnah betreiben (Subnetze, Pools, Reservierungen, Optionen) und das Wissen auf meine betriebliche Kea-Migration übertragen.
2. DNS-Grundlagen praktisch vertiefen: autoritative Zone, Reverse-Zone, Forwarding.
3. Infrastructure as Code mit Ansible lernen: Rollen, Templates, Variablen, Idempotenz.
4. Eine Backup-Strategie nach der 3-2-1-Regel planen, umsetzen und vor allem den Restore testen.
5. RTO und RPO nicht nur definieren, sondern messen.
6. Einen Monitoring-Stack mit Prometheus und Grafana aufbauen und sinnvolle Alarme definieren.
7. Einen Wiederanlaufplan nach BSI-Standard 200-4 schreiben, mit dem eine andere Fachkraft das System wiederherstellen kann.
8. Git sauber für Konfiguration und Dokumentation nutzen (Commits, README, Struktur).
9. Linux-Serveradministration auf Debian festigen (systemd, Netzwerk, Logging), passend zu meinem Ziel Linux- und AWS-Solutions-Architect.
10. Vorbereitung auf die AP2: Themen Verfügbarkeit, Datensicherung, Monitoring und Nutzwertanalyse praktisch anwenden.

## 3. Dienste im Projekt

| Dienst | Zweck | Priorität |
|---|---|---|
| DHCPv4 (Kea) | Adressvergabe im Labornetz, Reservierungen, Optionen (Router, DNS, NTP, Domain) | Muss |
| DNS (BIND 9) | Autoritativ für `lab.intern` und Reverse-Zone, Forwarder für externe Namen | Muss |
| NTP (chrony) | Zeitserver für das Labornetz, per DHCP-Option 42 verteilt | Muss |
| Backup (vzdump + Restic) | VM-Images und Nutzdaten (Leases, Zonen, Konfiguration) sichern | Muss |
| Monitoring (Prometheus, Grafana, Alertmanager) | Metriken, Dashboards, Alarme | Muss |
| Automatisierung (Ansible, cloud-init) | Reproduzierbarer Aufbau aller VMs | Muss |
| Dynamisches DNS (Kea DHCP-DDNS) | Automatische DNS-Einträge für DHCP-Clients | Kann |
| DHCP-Hochverfügbarkeit (Kea HA Hook, zweiter Knoten) | Ausfallsicherheit des DHCP-Dienstes | Kann |

## 4. Architektur

### 4.1 Übersicht

```
                    Schulnetz / Internet
                            │
                   ┌────────┴─────────┐
                   │  Proxmox VE Host │  vmbr0: Uplink (Schulnetz)
                   │  (NAT/Gateway)   │  vmbr1: Labornetz 10.10.10.0/24
                   └────────┬─────────┘  (isoliert, NAT nach außen)
                            │ vmbr1
       ┌────────────────────┼─────────────────────┐
       │                    │                     │
┌──────┴───────┐    ┌───────┴───────┐     ┌───────┴──────┐
│ net01        │    │ mon01         │     │ client01     │
│ 10.10.10.10  │    │ 10.10.10.20   │     │ DHCP-Client  │
│ Kea DHCPv4   │    │ Prometheus    │     │ (Testsystem) │
│ BIND 9       │    │ Grafana       │     └──────────────┘
│ chrony       │    │ Alertmanager  │
│ node_exporter│    │ Blackbox Exp. │
│ kea-exporter │    │ (Docker       │
│ bind_exporter│    │  Compose)     │
│ Restic       │    │ Restic        │
└──────────────┘    └───────────────┘

Backup-Ziele:  (1) vzdump -> separater Datenträger am Host (USB-SSD/NAS)
               (2) Restic -> Offsite-Repository (S3-Bucket oder SFTP)
               (3) Git-Repository (Konfiguration, Playbooks, Doku) -> GitHub/GitLab
```

### 4.2 IP-Plan Labornetz `10.10.10.0/24`

| Adresse | System | Bemerkung |
|---|---|---|
| 10.10.10.1 | Proxmox-Host (vmbr1) | Gateway mit NAT (Masquerading) |
| 10.10.10.10 | net01 | Kea, BIND 9, chrony |
| 10.10.10.20 | mon01 | Monitoring |
| 10.10.10.50 | client01 (Reservierung) | Test einer Host-Reservierung |
| 10.10.10.100 bis .199 | DHCP-Pool | Lease-Zeit 8 h |

### 4.3 Plattform, Hardware, Betriebssysteme, Virtualisierung

- **Plattform:** Proxmox VE (aktuelle Version) als Typ-1-Hypervisor auf einem Schul-PC oder eigenem Rechner. Fallback, falls keine Bare-Metal-Installation möglich ist: Proxmox verschachtelt (nested) in VirtualBox/VMware Workstation oder KVM/libvirt auf meinem Linux-Laptop.
- **Hardware (Mindestanforderung):** 4 CPU-Kerne mit VT-x/AMD-V, 16 GB RAM, 120 GB SSD, zusätzlicher Datenträger (USB-SSD) als Backup-Ziel.
- **Gast-Betriebssystem:** Debian 13 "trixie" (Cloud-Image mit cloud-init als VM-Template).
- **Virtualisierung:** KVM-VMs für die Dienste. Der Monitoring-Stack läuft innerhalb von mon01 als Docker-Compose-Projekt (Containerisierung). Kea und BIND laufen bewusst nativ als systemd-Dienste, da DHCP Layer-2-Broadcasts benötigt und in Containern nur mit Host-Networking sauber funktioniert.

| VM | vCPU | RAM | Disk |
|---|---|---|---|
| net01 | 1 | 1 GB | 10 GB |
| mon01 | 2 | 4 GB | 25 GB |
| client01 | 1 | 1 GB | 8 GB |

## 5. Softwareauswahl mit Vergleich

Bewertung als Nutzwertanalyse: Punkte 1 (schlecht) bis 5 (sehr gut), Gewichtung in Prozent, Ergebnis = gewichtete Summe.

### 5.1 Plattform

| Kriterium | Gewicht | Proxmox VE | VMware ESXi | Hyper-V | Docker auf Bare Metal | AWS EC2 |
|---|---|---|---|---|---|---|
| Kosten/Lizenz | 15 % | 5 | 2 | 3 | 5 | 3 |
| Automatisierbarkeit (API, cloud-init, Ansible/Terraform) | 20 % | 4 | 4 | 3 | 5 | 5 |
| Integrierte Backup-Funktion | 20 % | 5 | 3 | 3 | 3 | 4 |
| Eignung für L2-Dienste (DHCP) und Netztrennung | 20 % | 5 | 5 | 4 | 2 | 1 |
| Vorkenntnisse/Lernkurve | 10 % | 4 | 3 | 3 | 4 | 3 |
| Ressourcenbedarf | 5 % | 4 | 3 | 3 | 5 | 5 |
| Praxisrelevanz | 10 % | 4 | 4 | 4 | 4 | 5 |
| **Ergebnis** | 100 % | **4,55** | 3,55 | 3,30 | 3,80 | 3,50 |

**Entscheidung: Proxmox VE.** Kostenfrei nutzbar, eingebautes Backup (vzdump), cloud-init-Templates und eine REST-API für spätere Automatisierung. ESXi hat seit der Broadcom-Übernahme eine unsichere Lizenzlage und benötigt für Backups Zusatzsoftware. AWS scheidet für DHCP aus, weil eine VPC keine Broadcasts weiterleitet und den DHCP-Dienst selbst bereitstellt.

### 5.2 DHCP-Server

| Kriterium | Kea | ISC DHCP (dhcpd) | dnsmasq | Windows Server DHCP |
|---|---|---|---|---|
| Wartungsstatus | aktiv entwickelt | End of Life seit 2022 | aktiv | aktiv |
| Konfiguration | JSON, zur Laufzeit per API änderbar | Textdatei, Neustart nötig | Textdatei | GUI/PowerShell |
| Lease-Backend | Memfile (CSV), MySQL, PostgreSQL | Datei | Datei | Jet-Datenbank |
| Hochverfügbarkeit | HA-Hook (Hot-Standby, Load-Balancing) | Failover-Protokoll | nein | Failover |
| Monitoring | Statistiken per API, Prometheus-Exporter | begrenzt | begrenzt | Windows-Tools |
| Kosten | Open Source | Open Source | Open Source | Windows-Lizenz |

**Entscheidung: Kea.** Zukunftssicher, API-fähig, gut überwachbar und direkt relevant für meine betriebliche Migration.

### 5.3 DNS-Server

| Kriterium | BIND 9 | Unbound | PowerDNS | dnsmasq |
|---|---|---|---|---|
| Autoritativ | ja | nur rudimentär (local-data) | ja (Authoritative Server) | einfach |
| Rekursiv/Forwarding | ja | ja (Spezialität) | separater Recursor | ja |
| DDNS mit Kea | ja (RFC 2136, TSIG) | nein | ja | nein |
| Verbreitung/Doku | sehr hoch, Referenzimplementierung | hoch | hoch | hoch (klein) |
| Monitoring | Statistik-Channel, bind_exporter | unbound_exporter | eingebaute Metriken | begrenzt |

**Entscheidung: BIND 9.** Ein Dienst für autoritative Zonen und Forwarding, unterstützt DDNS mit Kea für die Kann-Erweiterung.

### 5.4 Backup

| Kriterium | Gewicht | Restic | BorgBackup | Duplicity | Proxmox Backup Server | vzdump (integriert) | rsync |
|---|---|---|---|---|---|---|---|
| Verschlüsselung | 15 % | 5 | 5 | 4 | 5 | 2 | 1 |
| Deduplizierung/Speicherbedarf | 15 % | 5 | 5 | 2 | 5 | 1 | 1 |
| Offsite-Ziele (S3, SFTP) | 20 % | 5 | 3 | 5 | 4 | 2 | 3 |
| Wiederherstellung (Tempo, Einfachheit) | 20 % | 4 | 4 | 2 | 5 | 5 | 3 |
| Automatisierbarkeit/Monitoring-Integration | 15 % | 5 | 4 | 3 | 4 | 4 | 3 |
| Einrichtungsaufwand | 15 % | 4 | 4 | 3 | 3 | 5 | 5 |
| **Ergebnis** | 100 % | **4,65** | 4,10 | 3,20 | 4,35 | 3,20 | 2,70 |

**Entscheidung: Restic für Datei-Backups, ergänzt durch vzdump für VM-Images.**

- Restic sichert verschlüsselt und dedupliziert die Nutzdaten (Kea-Leases, BIND-Zonen und Journale, `/etc`, Grafana-Datenbank) in ein Offsite-Repository. Es ist ein einzelnes Binary, spricht S3 und SFTP nativ und lässt sich gut per systemd-Timer und Prometheus-Metrik überwachen.
- vzdump ist in Proxmox bereits enthalten und ermöglicht den schnellsten Restore einer kompletten VM.
- Der Proxmox Backup Server wäre im Produktivbetrieb erste Wahl, erfordert aber ein zusätzliches System. Für ein Einzelprojekt in 18 UE ist er als Ausbaustufe vorgemerkt.

**Backup-Strategie (3-2-1 und Generationenprinzip):**

| Kopie | Medium | Ort | Inhalt | Intervall | Aufbewahrung |
|---|---|---|---|---|---|
| Original | VM-Disk | Proxmox-Host | laufendes System | | |
| Kopie 1 | USB-SSD/NAS (vzdump) | lokal, getrennter Datenträger | komplette VMs | täglich | 7 täglich, 4 wöchentlich |
| Kopie 2 | Objektspeicher/SFTP (Restic) | offsite | Nutzdaten und Konfiguration | stündlich (Leases), täglich (Rest) | 24 stündlich, 7 täglich, 4 wöchentlich, 6 monatlich |
| Konfiguration | Git (GitHub/GitLab) | offsite | Playbooks, Templates, Doku | bei jeder Änderung | vollständige Historie |

Geheimnisse (Restic-Passwort, TSIG-Schlüssel, Grafana-Admin) liegen nicht im Klartext im Repository, sondern werden mit Ansible Vault verschlüsselt.

### 5.5 Monitoring

| Kriterium | Gewicht | Prometheus + Grafana | Zabbix | CheckMK Raw | Icinga 2 | Uptime Kuma |
|---|---|---|---|---|---|---|
| Integration Kea/BIND (Exporter, Plugins) | 25 % | 5 | 3 | 3 | 3 | 1 |
| Alerting | 15 % | 4 | 5 | 4 | 4 | 3 |
| Visualisierung/Trends | 15 % | 5 | 4 | 3 | 2 | 2 |
| Einrichtungsaufwand | 15 % | 3 | 3 | 4 | 3 | 5 |
| Konfiguration als Code | 20 % | 5 | 3 | 3 | 4 | 2 |
| Ressourcenbedarf | 10 % | 4 | 3 | 3 | 4 | 5 |
| **Ergebnis** | 100 % | **4,45** | 3,45 | 3,30 | 3,30 | 2,65 |

**Entscheidung: Prometheus, Grafana und Alertmanager** (per Docker Compose auf mon01). Es gibt fertige Exporter für Kea, BIND und Linux-Hosts, die komplette Konfiguration inklusive Dashboards lässt sich als Dateien in Git versionieren und mit Ansible ausrollen.

### 5.6 Automatisierung

| Kriterium | Ansible | Shell-Skripte | Terraform | Puppet/Salt |
|---|---|---|---|---|
| Agentenlos | ja (SSH) | ja | ja (API) | nein (Agent/Master) |
| Idempotenz | ja | nur mit Aufwand | ja (Zustand) | ja |
| Einsatzgebiet | Konfiguration von Systemen | Einzelaufgaben | Bereitstellung von Infrastruktur (VMs) | Konfiguration großer Umgebungen |
| Lernkurve | mittel | gering | mittel | hoch |

**Entscheidung: Ansible für die Konfiguration, cloud-init für die Erstkonfiguration der VMs.** Terraform (Provider für Proxmox) zum automatischen Anlegen der VMs ist als Ausbaustufe vorgesehen.

## 6. Recovery Time Objective (RTO) und Recovery Point Objective (RPO)

Vorüberlegung: Bei einer Lease-Zeit von 8 h versuchen Clients nach 4 h (T1) ihre Lease zu verlängern. Bestehende Clients bemerken einen DHCP-Ausfall von unter 4 h daher kaum, neue Clients erhalten aber sofort keine Adresse. DNS fällt dagegen sofort spürbar aus.

| Szenario | Wiederherstellungsweg | Ziel-RTO | Ziel-RPO |
|---|---|---|---|
| Dienst hängt / Fehlkonfiguration | Rollback per Git und Ansible | 15 min | 0 (Konfiguration in Git) |
| VM net01 defekt | Restore aus vzdump | 20 min | 24 h (VM-Stand), Leases 1 h per Restic |
| VM net01 verloren, kein vzdump verfügbar | Neuaufbau aus Template + Ansible + Restic-Restore | **60 min** | 1 h (Leases) |
| Proxmox-Host komplett ausgefallen | Neuinstallation Proxmox, dann Neuaufbau aller VMs | 4 h | 1 h (Leases), 24 h (Metriken) |

**Projektziel:** Der Neuaufbau von net01 ohne VM-Image (nur Git + Restic) gelingt in höchstens 60 Minuten. Die tatsächlichen Zeiten werden am Fr 02.10. gemessen und in den Wiederanlaufplan übernommen.

## 7. Monitoring-Parameter

| Bereich | Parameter | Quelle | Alarmschwelle (Vorschlag) |
|---|---|---|---|
| Host | CPU-Last (load) | node_exporter | load15 > Anzahl Kerne für 15 min |
| Host | RAM-Nutzung, Swap | node_exporter | RAM > 90 %, Swap > 20 % |
| Host | Freier Plattenplatz | node_exporter | < 15 % frei |
| Host | Uhrzeit-Abweichung | node_exporter (timex) | Offset > 100 ms |
| Proxmox-Host | SMART-Status der Datenträger | smartctl_exporter (Kann) | SMART-Fehler |
| DHCP | Dienst läuft | kea-exporter, systemd | Dienst nicht erreichbar > 1 min |
| DHCP | Pool-Auslastung (assigned/total addresses) | kea-exporter | > 80 % Warnung, > 95 % kritisch |
| DHCP | Abgelehnte Adressen (declined), verworfene Pakete | kea-exporter | Anstieg > 0 |
| DNS | Antwortet für `lab.intern` und extern | blackbox_exporter (DNS-Probe) | Probe schlägt fehl |
| DNS | Antwortzeit | blackbox_exporter | > 200 ms |
| DNS | SERVFAIL-Rate, Anfragen pro Sekunde | bind_exporter | SERVFAIL > 5 % |
| NTP | chrony erreichbar, Stratum | blackbox/chrony-Exporter (Kann) | Stratum > 5 |
| Backup | Alter der letzten erfolgreichen Sicherung | Restic-Metrik per node_exporter textfile collector | älter als 26 h (täglich) bzw. 2 h (Leases) |
| Backup | Größe des Repositorys | Restic-Metrik | Sprung > 50 % |
| Monitoring | Prometheus-Targets erreichbar | Prometheus `up` | `up == 0` > 2 min |

Benachrichtigung: Alertmanager, im Projekt per E-Mail (Test-Postfach) oder Webhook.

## 8. Automatisierungskonzept

1. **VM-Template:** Debian-13-Cloud-Image als Proxmox-Template mit cloud-init (Benutzer, SSH-Key, statische IP).
2. **VM anlegen:** zunächst per `qm clone` (Skript), als Ausbaustufe per Terraform-Provider für Proxmox.
3. **Konfiguration:** Ansible-Playbook `site.yml` mit Rollen:
   - `common` (Pakete, Zeitzone, SSH-Härtung, node_exporter)
   - `kea` (Kea DHCPv4, Konfiguration per Jinja2-Template aus Variablen: Subnetze, Pools, Reservierungen)
   - `bind` (Zonen aus Variablen, Forwarder, Statistik-Channel)
   - `chrony`
   - `restic` (Repository-Init, Backup-Skript, systemd-Timer, Metrik-Export)
   - `monitoring` (Docker Compose mit Prometheus, Grafana, Alertmanager, Blackbox Exporter, provisionierte Dashboards und Alarmregeln)
4. **Secrets:** Ansible Vault.
5. **Restore-Playbook:** `restore.yml` stellt die Nutzdaten aus Restic wieder her, damit der Wiederanlauf mit einem Befehl möglich ist.
6. **Qualität:** `ansible-lint`, `kea-dhcp4 -t` (Konfigurationstest) und `named-checkconf`/`named-checkzone` vor dem Ausrollen.

Geplante Repository-Struktur:

```
lf10b-netzdienste/
├── README.md
├── docs/
│   ├── projektplan.md
│   ├── wiederanlaufplan.md
│   └── messprotokoll.md
├── ansible/
│   ├── inventory.ini
│   ├── group_vars/  (inkl. vault.yml)
│   ├── site.yml
│   ├── restore.yml
│   └── roles/ (common, kea, bind, chrony, restic, monitoring)
└── scripts/
    └── create-vm.sh
```

## 9. Zeitplan

| Termin | UE | Aufgabe | Ergebnis |
|---|---|---|---|
| bis Di 29.09. | SOL | Projektplan und WAP-Entwurf, Git-Repository anlegen, Hardware klären | Plan vorgestellt |
| **Mi 30.09.** | 1 | Proxmox prüfen/installieren, vmbr1 mit NAT, Debian-Template mit cloud-init | Plattform bereit |
| | 2 | VMs net01, mon01, client01 anlegen, Ansible-Grundgerüst, Rolle `common` | SSH-Zugriff per Ansible |
| | 3 bis 4 | Rolle `kea`: Subnetz, Pool, Optionen, Reservierung, Test mit client01 | client01 erhält Lease |
| | 5 | Rollen `bind` und `chrony`, Forward- und Reverse-Zone | Namensauflösung funktioniert |
| | 6 | Tests, Commit, Doku des Tages | Stand in Git |
| **Do 01.10.** | 1 bis 2 | Rolle `monitoring`: Prometheus, Grafana, Alertmanager, Exporter | Metriken sichtbar |
| | 3 | Dashboards (Host, Kea, BIND), Alarmregeln, Testalarm | Alarm kommt an |
| | 4 | vzdump-Job einrichten, Rolle `restic` mit Timer | erste Backups |
| | 5 | Backup-Metriken ins Monitoring, `restore.yml` schreiben | Backup überwacht |
| | 6 | Puffer, Doku, WAP ergänzen | Stand in Git |
| **Fr 02.10.** | 1 bis 2 | **Restore-Test 1:** net01 löschen, Neuaufbau über Template + Ansible + Restic, Zeit messen | gemessenes RTO |
| | 3 | **Restore-Test 2:** Restore aus vzdump, Zeit messen | Vergleich |
| | 4 | Wiederanlaufplan mit Messwerten finalisieren | WAP v1.0 |
| | 5 | Puffer oder Kann-Ziele (DDNS, Terraform, Kea HA) | optional |
| | 6 | Präsentation vorbereiten, SOL Projektabschluss | Abgabe Git-Link |
| **Mo 05.10.** | | Projektpräsentation | |

**Risiken und Gegenmaßnahmen**

| Risiko | Gegenmaßnahme |
|---|---|
| Keine Bare-Metal-Installation an der Schule möglich | Nested Proxmox oder KVM/libvirt auf eigenem Laptop, vorher testen |
| DHCP-Server stört Schulnetz | Dienste nur auf isoliertem vmbr1, Kea lauscht nur auf dem Lab-Interface |
| Kein Internetzugang für Pakete/Offsite-Backup | Pakete vorab cachen (apt-cacher-ng) oder lokales Restic-Repository auf zweitem Datenträger als Offsite-Ersatz |
| Zeit reicht nicht (Einzelarbeit) | Kann-Ziele strikt nachrangig, Puffer-UE am Do und Fr |

## 10. Aufgabenverteilung

Das Projekt wird in Einzelarbeit durchgeführt. Alle Rollen liegen bei mir:

| Rolle | Aufgaben | Verantwortlich |
|---|---|---|
| Plattform und Automatisierung | Proxmox, Template, Ansible-Grundgerüst | Samuel Ararsa |
| Netzdienste | Kea, BIND 9, chrony | Samuel Ararsa |
| Backup und Wiederanlauf | vzdump, Restic, Restore-Tests, WAP | Samuel Ararsa |
| Monitoring | Prometheus, Grafana, Alertmanager | Samuel Ararsa |
| Dokumentation und Präsentation | Git-Repository, Doku, Folien | Samuel Ararsa |

## 11. Anleitungen und Dokumentation

- LF10b-Unterlagen: https://johannesloetzsch.github.io/LF10b/ (Datensicherung, Monitoring, Automatisierung, Ansible, DHCP, DNS, NTP)
- Kea Administrator Reference Manual: https://kea.readthedocs.io/
- BIND 9 Administrator Reference Manual: https://bind9.readthedocs.io/
- chrony Dokumentation: https://chrony-project.org/documentation.html
- Proxmox VE Administration Guide (vzdump, cloud-init, Netzwerk): https://pve.proxmox.com/pve-docs/
- Restic Dokumentation: https://restic.readthedocs.io/
- Prometheus Dokumentation: https://prometheus.io/docs/
- Grafana Dokumentation (Provisioning): https://grafana.com/docs/grafana/latest/
- Kea Prometheus Exporter: https://github.com/mweinelt/kea-exporter
- BIND Exporter: https://github.com/prometheus-community/bind_exporter
- Blackbox Exporter: https://github.com/prometheus/blackbox_exporter
- Ansible Dokumentation: https://docs.ansible.com/
- BSI-Standard 200-4, Vorlage Wiederanlaufplan: https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/Grundschutz/Hilfsmittel/Standard200_4_BCM/Standard_200-4_Vorlage_Wiederanlaufplan.html
