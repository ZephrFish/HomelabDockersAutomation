# Homelab Docker Automation

12 modular Docker stacks for a self-hosted homelab. Tested on Proxmox 8 / Debian 12.

## Quick Start

```bash
cp .env.example .env
nano .env                    # fill in HOST_IP, passwords, and generated secrets
bash scripts/gen-secrets.sh  # print fresh secrets to paste into .env

sudo ./deploy.sh             # deploy all stacks
sudo ./deploy.sh --stack 05  # deploy a single stack

bash scripts/status.sh       # docker compose ps for every stack
bash scripts/teardown.sh     # stop all stacks (preserves volumes)
bash scripts/teardown.sh --volumes  # stop and delete all data
```

`.env` is gitignored — never commit it.

## Stacks

| # | Name | Services | Ports |
|---|------|----------|-------|
| 01 | Monitoring | Portainer, Prometheus, Loki, Promtail, Grafana | 9000, 9090, 3100, 3000 |
| 02 | Apps | Homepage, Nginx Proxy Manager, Uptime Kuma | 3001, 81, 3002 |
| 03 | Auth | Authentik | 9110 |
| 04 | Security | CrowdSec, Wazuh | 8090, 5601 |
| 05 | Tools | ntfy, Registry, SonarQube, Scrutiny, n8n, Vaultwarden | 8085, 5001, 9095, 8082, 5678, 8083 |
| 06 | Dev Tools | Dozzle, code-server, pgAdmin, Semaphore, OWASP ZAP, WireGuard | 9999, 8484, 5050, 3333, 8091, 51821 |
| 07 | Git & CI | Forgejo, Jenkins | 3030, 8088 |
| 08 | Storage | MinIO | 9002 |
| 09 | Knowledge | BookStack, Netbox, DefectDojo | 6875, 8093, 8092 |
| 10 | Media | Jellyfin, Paperless-ngx | 8096, 8104 |
| 11 | Misc | CyberChef, SearXNG, PrivateBin, Huginn, Restic, Shepherd | 8000, 8888, 8889 |
| 12 | Honeypot | OpenCanary, Alerter, Postfix, Web UI | 8501 + honeypot ports |

## Secrets

`scripts/gen-secrets.sh` generates most secrets automatically. Two require manual steps:

**BookStack APP_KEY**
```bash
docker run --rm --entrypoint /bin/bash lscr.io/linuxserver/bookstack:latest appkey
```

**WireGuard password hash**
```bash
echo -n "yourpassword" | docker run --rm -i ghcr.io/wg-easy/wg-easy wgpw
# Double all $ signs before pasting into .env: $$2b$$12$$...
```

## First-run steps

| Service | Step |
|---------|------|
| Authentik | Complete setup at `/if/flow/initial-setup/`, then create OAuth apps for Grafana and Portainer |
| Jenkins | `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` |
| CrowdSec | `docker exec crowdsec cscli console enroll <key>` |
| Forgejo | Set host URL to `http://<HOST_IP>:3030` in the setup wizard |
| Wazuh / SonarQube / BookStack | Change default password on first login |
| Jellyfin | Complete media library wizard |

## Notes

**Wazuh** requires `vm.max_map_count=262144`. The deploy script sets this for the session; to persist:
```bash
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

**Grafana / OpenCanary dashboard** — the dashboard JSON has a hardcoded Loki datasource UID (`P8E80F9AEF21F6940`). After deployment, get the actual UID from Grafana → Connections → Data Sources → Loki, then replace all occurrences in `stacks/01-monitoring/config/grafana/provisioning/dashboards/opencanary.json` and restart Grafana.

**OpenCanary UI** — the `opencanary-ui:local` image is built locally from `stacks/12-honeypot/ui/` and is not published. The deploy script builds it automatically.

**Port 51820** — if already in use (e.g. by Ludus), change `WG_PORT` in the devtools compose.

**AppArmor** — containers needing elevated permissions already have `security_opt: [apparmor:unconfined]` set.
