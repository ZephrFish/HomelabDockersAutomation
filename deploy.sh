#!/bin/bash
# ============================================================
# Homelab — Full Stack Deployment Script
# Run on a fresh Proxmox/Debian host as root.
# Edit .env before running.
#
# Usage:
#   ./deploy.sh              — deploy all stacks
#   ./deploy.sh --stack NN   — deploy a single stack (e.g. --stack 05)
#   ./deploy.sh --help
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

# ── Argument parsing ─────────────────────────────────────────
ONLY_STACK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      ONLY_STACK="${2:-}"
      [[ -z "$ONLY_STACK" ]] && { echo "Error: --stack requires a stack number (e.g. --stack 05)"; exit 1; }
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--stack NN]"
      echo ""
      echo "  --stack NN   Deploy only the specified stack"
      echo ""
      echo "Stacks:"
      echo "  01  Monitoring    07  Git & CI"
      echo "  02  Apps          08  Storage"
      echo "  03  Auth          09  Knowledge"
      echo "  04  Security      10  Media"
      echo "  05  Tools         11  Misc"
      echo "  06  Dev Tools     12  Honeypot"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Run $0 --help for usage."
      exit 1
      ;;
  esac
done

# Colour helpers
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; }
section() { echo -e "\n${GREEN}══════════════════════════════════════${NC}"; echo -e "${GREEN} $*${NC}"; echo -e "${GREEN}══════════════════════════════════════${NC}"; }

# ── .env validation ──────────────────────────────────────────
validate_env() {
  section "Validating .env"
  local failed=false

  # Check HOST_IP is set and not a placeholder
  if [[ -z "${HOST_IP:-}" || "$HOST_IP" == "10.10.x.x" ]]; then
    error "HOST_IP is not set in .env"
    failed=true
  fi

  # Check for known placeholder strings that must be replaced
  local -A checks=(
    [AUTHENTIK_SECRET_KEY]="ChangeMeToA50CharRandomString"
    [VAULTWARDEN_ADMIN_TOKEN]="ChangeMe"
    [N8N_ENCRYPTION_KEY]="ChangeMeToA32CharRandomString"
    [BOOKSTACK_APP_KEY]="ChangeMe__see_README"
    [SEMAPHORE_ACCESS_KEY_ENCRYPTION]="ChangeMeToA32CharString"
    [WG_PASSWORD_HASH]="ChangeMe__see_README"
    [NETBOX_SECRET_KEY]="ChangeMeToA50PlusCharRandomString"
    [NETBOX_SUPERUSER_API_TOKEN]="ChangeMeToA40HexCharString"
    [PAPERLESS_SECRET_KEY]="ChangeMeToA50CharRandomStringForPaperless"
    [HUGINN_SECRET_TOKEN]="ChangeMeToA50CharRandomStringForHuginn"
    [CROWDSEC_ENROLLMENT_KEY]="your_enrollment_key_here"
  )

  for var in "${!checks[@]}"; do
    placeholder="${checks[$var]}"
    value="${!var:-}"
    if [[ -z "$value" || "$value" == *"$placeholder"* ]]; then
      warn "$var is not set — update .env before deploying"
      failed=true
    fi
  done

  if [[ "$failed" == "true" ]]; then
    error ".env contains unset or placeholder values. Run: bash scripts/gen-secrets.sh"
    exit 1
  fi

  info ".env looks good."
}

validate_env

# ── Prerequisites ────────────────────────────────────────────
section "Checking prerequisites"
command -v docker  >/dev/null || { error "Docker not found. Install Docker first: https://docs.docker.com/engine/install/"; exit 1; }
command -v sysctl  >/dev/null && sysctl -w net.ipv4.ip_forward=1 >/dev/null

info "Creating /opt stack directories..."
for d in monitoring apps authentik crowdsec wazuh tools devtools forgejo jenkins minio \
         bookstack netbox defectdojo jellyfin paperless cyberchef searxng privatebin \
         huginn restic shepherd opencanary opencanary-ui; do
  mkdir -p /opt/$d
done

# ── Helper: deploy a stack ───────────────────────────────────
# Passes the repo .env so Docker Compose resolves ${VAR} references in compose files.
deploy() {
  local name="$1"; local dir="$2"
  info "Deploying $name..."
  docker compose --env-file "$SCRIPT_DIR/.env" -f "$dir/docker-compose.yml" up -d --remove-orphans
}

# ── Helper: check whether a stack number should run ─────────
should_run() { [[ -z "$ONLY_STACK" || "$ONLY_STACK" == "$1" ]]; }

# ============================================================
# STACK 1 — Monitoring (Portainer, Prometheus, Loki, Promtail, Grafana)
# ============================================================
if should_run "01"; then
  section "Stack 1 — Monitoring"

  cp -r stacks/01-monitoring/config/prometheus  /opt/monitoring/
  cp -r stacks/01-monitoring/config/loki        /opt/monitoring/
  cp -r stacks/01-monitoring/config/promtail    /opt/monitoring/
  mkdir -p /opt/monitoring/grafana/provisioning
  cp -r stacks/01-monitoring/config/grafana/provisioning /opt/monitoring/grafana/

  # Substitute host IP in promtail config (plain YAML, not a compose file)
  sed -i "s/10\.10\.76\.127/$HOST_IP/g" /opt/monitoring/promtail/promtail.yml

  cp stacks/01-monitoring/docker-compose.yml /opt/monitoring/docker-compose.yml

  deploy "Monitoring" /opt/monitoring
  info "Grafana:    http://$HOST_IP:3000  (admin / $GRAFANA_ADMIN_PASSWORD)"
  info "Prometheus: http://$HOST_IP:9090"
  info "Portainer:  http://$HOST_IP:9000"
fi

# ============================================================
# STACK 2 — Apps (Homepage, Nginx Proxy Manager, Uptime Kuma)
# ============================================================
if should_run "02"; then
  section "Stack 2 — Apps"
  cp stacks/02-apps/docker-compose.yml /opt/apps/docker-compose.yml
  deploy "Apps" /opt/apps
  info "Homepage:          http://$HOST_IP:3080"
  info "Nginx Proxy Mgr:  http://$HOST_IP:81"
  info "Uptime Kuma:      http://$HOST_IP:3001"
fi

# ============================================================
# STACK 3 — Auth (Authentik)
# ============================================================
if should_run "03"; then
  section "Stack 3 — Authentik (SSO)"
  cp stacks/03-auth/docker-compose.yml /opt/authentik/docker-compose.yml
  deploy "Authentik" /opt/authentik
  info "Authentik:  http://$HOST_IP:9110"
  warn "MANUAL: Complete Authentik setup wizard at http://$HOST_IP:9110/if/flow/initial-setup/"
fi

# ============================================================
# STACK 4 — Security (CrowdSec, Wazuh)
# ============================================================
if should_run "04"; then
  section "Stack 4 — Security"

  cp stacks/04-security/crowdsec/docker-compose.yml /opt/crowdsec/docker-compose.yml
  deploy "CrowdSec" /opt/crowdsec
  warn "MANUAL: Enrol CrowdSec at app.crowdsec.net, then run:"
  warn "  docker exec crowdsec cscli console enroll \$CROWDSEC_ENROLLMENT_KEY"

  info "Deploying Wazuh (this takes several minutes)..."
  cp stacks/04-security/wazuh/docker-compose.yml /opt/wazuh/docker-compose.yml
  sysctl -w vm.max_map_count=262144
  deploy "Wazuh" /opt/wazuh
  info "Wazuh:  https://$HOST_IP:5601  (admin / SecretPassword)"
  warn "MANUAL: Wazuh generates self-signed certs. First login may require accepting the cert."
fi

# ============================================================
# STACK 5 — Tools (ntfy, Registry, SonarQube, Scrutiny, n8n, Vaultwarden)
# ============================================================
if should_run "05"; then
  section "Stack 5 — Tools"
  cp stacks/05-tools/docker-compose.yml /opt/tools/docker-compose.yml
  deploy "Tools" /opt/tools
  info "ntfy:         http://$HOST_IP:8085"
  info "Registry UI:  http://$HOST_IP:5001"
  info "SonarQube:    http://$HOST_IP:9095  (admin / admin — change on first login)"
  info "Scrutiny:     http://$HOST_IP:8082"
  info "n8n:          http://$HOST_IP:5678"
  info "Vaultwarden:  http://$HOST_IP:8083"
fi

# ============================================================
# STACK 6 — Dev Tools (Dozzle, code-server, pgAdmin, Semaphore, ZAP, WireGuard)
# ============================================================
if should_run "06"; then
  section "Stack 6 — Dev Tools"
  cp stacks/06-devtools/docker-compose.yml /opt/devtools/docker-compose.yml
  deploy "DevTools" /opt/devtools
  info "Dozzle:      http://$HOST_IP:9999"
  info "code-server: http://$HOST_IP:8484  (password: $ADMIN_PASSWORD)"
  info "pgAdmin:     http://$HOST_IP:5050  ($PGADMIN_EMAIL / $PGADMIN_PASSWORD)"
  info "Semaphore:   http://$HOST_IP:3333  (admin / $ADMIN_PASSWORD)"
  info "OWASP ZAP:   http://$HOST_IP:8091"
  info "WireGuard:   http://$HOST_IP:51821"
fi

# ============================================================
# STACK 7 — Git & CI (Forgejo, Jenkins)
# ============================================================
if should_run "07"; then
  section "Stack 7 — Git & CI"

  cp stacks/07-git-ci/forgejo/docker-compose.yml /opt/forgejo/docker-compose.yml
  deploy "Forgejo" /opt/forgejo
  info "Forgejo:  http://$HOST_IP:3030"

  cp stacks/07-git-ci/jenkins/docker-compose.yml /opt/jenkins/docker-compose.yml
  deploy "Jenkins" /opt/jenkins
  info "Jenkins:  http://$HOST_IP:8088"
  warn "MANUAL: Jenkins initial password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
fi

# ============================================================
# STACK 8 — Storage (MinIO)
# ============================================================
if should_run "08"; then
  section "Stack 8 — Storage"
  cp stacks/08-storage/minio/docker-compose.yml /opt/minio/docker-compose.yml
  deploy "MinIO" /opt/minio
  info "MinIO Console: http://$HOST_IP:9002  ($MINIO_ROOT_USER / $MINIO_ROOT_PASSWORD)"
fi

# ============================================================
# STACK 9 — Knowledge & Tracking (BookStack, Netbox, DefectDojo)
# ============================================================
if should_run "09"; then
  section "Stack 9 — Knowledge & Tracking"

  cp stacks/09-knowledge/bookstack/docker-compose.yml /opt/bookstack/docker-compose.yml
  deploy "BookStack" /opt/bookstack
  info "BookStack:  http://$HOST_IP:6875  (admin@admin.com / password — change immediately)"

  cp stacks/09-knowledge/netbox/docker-compose.yml /opt/netbox/docker-compose.yml
  deploy "Netbox" /opt/netbox
  info "Netbox:  http://$HOST_IP:8093  (admin / $ADMIN_PASSWORD)"

  cp stacks/09-knowledge/defectdojo/docker-compose.yml /opt/defectdojo/docker-compose.yml
  deploy "DefectDojo" /opt/defectdojo
  info "DefectDojo:  http://$HOST_IP:8092  (admin / $ADMIN_PASSWORD)"
  warn "DefectDojo takes 3-5 minutes to initialise on first boot."
fi

# ============================================================
# STACK 10 — Media (Jellyfin, Paperless)
# ============================================================
if should_run "10"; then
  section "Stack 10 — Media"

  cp stacks/10-media/jellyfin/docker-compose.yml /opt/jellyfin/docker-compose.yml
  deploy "Jellyfin" /opt/jellyfin
  info "Jellyfin:  http://$HOST_IP:8096"
  warn "MANUAL: Complete Jellyfin first-run wizard."

  cp stacks/10-media/paperless/docker-compose.yml /opt/paperless/docker-compose.yml
  deploy "Paperless" /opt/paperless
  info "Paperless:  http://$HOST_IP:8104  (admin / $ADMIN_PASSWORD)"
fi

# ============================================================
# STACK 11 — Misc (CyberChef, SearXNG, PrivateBin, Huginn, etc.)
# ============================================================
if should_run "11"; then
  section "Stack 11 — Misc Tools"
  for tool in cyberchef searxng privatebin huginn restic shepherd; do
    cp stacks/11-misc/$tool/docker-compose.yml /opt/$tool/docker-compose.yml 2>/dev/null || true
    [ -f /opt/$tool/docker-compose.yml ] && deploy "$tool" /opt/$tool
  done
  info "CyberChef:  http://$HOST_IP:8000"
  info "SearXNG:    http://$HOST_IP:8888"
  info "PrivateBin: http://$HOST_IP:8889"
  info "Huginn:     http://$HOST_IP:8103  (admin / $ADMIN_PASSWORD)"
fi

# ============================================================
# STACK 12 — OpenCanary Honeypot
# ============================================================
if should_run "12"; then
  section "Stack 12 — OpenCanary Honeypot"

  cp stacks/12-honeypot/opencanary.conf /opt/opencanary/opencanary.conf
  cp stacks/12-honeypot/alerter.sh      /opt/opencanary/alerter.sh
  chmod +x /opt/opencanary/alerter.sh

  # Patch the honeypot node ID in the JSON config
  sed -i "s/ultra-lab-canary/$HOST_HOSTNAME/g" /opt/opencanary/opencanary.conf

  # Patch alerter with current host values (runs inside a container — cannot use .env directly)
  sed -i "s|http://10\.10\.76\.127:8085|$NTFY_URL|g"    /opt/opencanary/alerter.sh
  sed -i "s/canarylocal@zsec\.uk/$CANARY_ALERT_EMAIL/g"  /opt/opencanary/alerter.sh
  sed -i "s/ultra-lab\.chaos\.local/$HOST_HOSTNAME/g"    /opt/opencanary/alerter.sh

  info "Building OpenCanary UI image..."
  cp -r stacks/12-honeypot/ui/* /opt/opencanary-ui/
  cd /opt/opencanary-ui
  docker build -t opencanary-ui:local .
  cd "$SCRIPT_DIR"

  cp stacks/12-honeypot/docker-compose.yml /opt/opencanary/docker-compose.yml
  deploy "OpenCanary" /opt/opencanary

  sleep 3
  docker cp /opt/opencanary/opencanary.conf opencanary:/etc/opencanaryd/opencanary.conf
  docker restart opencanary

  info "OpenCanary UI:  http://$HOST_IP:8501  (admin / admin)"
  info "Honeypot ports: 21 23 1433 2223 3306 3389 5900 8843 8880"
  info "Alerts → ntfy: $NTFY_URL  |  email: $CANARY_ALERT_EMAIL"
fi

# ============================================================
# Promtail — wire OpenCanary log volume into Loki
# ============================================================
if should_run "01" || should_run "12"; then
  section "Wiring OpenCanary logs → Loki"
  if docker volume inspect opencanary_opencanary_logs >/dev/null 2>&1; then
    docker compose --env-file "$SCRIPT_DIR/.env" \
      -f /opt/monitoring/docker-compose.yml up -d --force-recreate promtail
    info "Promtail now shipping OpenCanary logs to Loki."
  else
    warn "OpenCanary log volume not found — deploy stack 12 first, then re-run stack 01."
  fi
fi

# ============================================================
# Done
# ============================================================
if [[ -z "$ONLY_STACK" ]]; then
  section "Deployment Complete"
  echo ""
  echo "  Service         URL                                     Creds"
  echo "  ─────────────── ─────────────────────────────────────── ──────────────────────"
  echo "  Proxmox         https://$HOST_IP:8006                    root / (system)"
  echo "  Portainer       http://$HOST_IP:9000                     (first-run setup)"
  echo "  Homepage        http://$HOST_IP:3080"
  echo "  Grafana         http://$HOST_IP:3000                     admin / $GRAFANA_ADMIN_PASSWORD"
  echo "  Prometheus      http://$HOST_IP:9090"
  echo "  Authentik       http://$HOST_IP:9110                     (setup wizard)"
  echo "  CrowdSec API    http://$HOST_IP:8090"
  echo "  Wazuh           https://$HOST_IP:5601                    admin / SecretPassword"
  echo "  ntfy            http://$HOST_IP:8085"
  echo "  Registry UI     http://$HOST_IP:5001"
  echo "  SonarQube       http://$HOST_IP:9095                     admin / admin"
  echo "  Scrutiny        http://$HOST_IP:8082"
  echo "  n8n             http://$HOST_IP:5678"
  echo "  Vaultwarden     http://$HOST_IP:8083"
  echo "  Dozzle          http://$HOST_IP:9999"
  echo "  code-server     http://$HOST_IP:8484                     password: $ADMIN_PASSWORD"
  echo "  pgAdmin         http://$HOST_IP:5050                     $PGADMIN_EMAIL"
  echo "  Semaphore       http://$HOST_IP:3333                     admin / $ADMIN_PASSWORD"
  echo "  OWASP ZAP       http://$HOST_IP:8091"
  echo "  WireGuard       http://$HOST_IP:51821"
  echo "  Forgejo         http://$HOST_IP:3030                     (setup wizard)"
  echo "  Jenkins         http://$HOST_IP:8088                     (setup wizard)"
  echo "  MinIO           http://$HOST_IP:9002                     $MINIO_ROOT_USER / $MINIO_ROOT_PASSWORD"
  echo "  BookStack       http://$HOST_IP:6875                     admin@admin.com / password"
  echo "  Netbox          http://$HOST_IP:8093                     admin / $ADMIN_PASSWORD"
  echo "  DefectDojo      http://$HOST_IP:8092                     admin / $ADMIN_PASSWORD"
  echo "  Jellyfin        http://$HOST_IP:8096                     (setup wizard)"
  echo "  Paperless       http://$HOST_IP:8104                     admin / $ADMIN_PASSWORD"
  echo "  CyberChef       http://$HOST_IP:8000"
  echo "  SearXNG         http://$HOST_IP:8888"
  echo "  PrivateBin      http://$HOST_IP:8889"
  echo "  Huginn          http://$HOST_IP:8103                     admin / $ADMIN_PASSWORD"
  echo "  OpenCanary UI   http://$HOST_IP:8501                     admin / admin"
  echo ""
  warn "Manual steps required:"
  warn "  1. Authentik — complete setup wizard, create OAuth apps for Grafana/Portainer"
  warn "  2. Jenkins  — retrieve initial admin password from container"
  warn "  3. CrowdSec — enrol with: docker exec crowdsec cscli console enroll <key>"
  warn "  4. Wazuh    — change default password after first login"
  warn "  5. SonarQube — change admin password on first login"
  warn "  6. BookStack — change admin@admin.com password on first login"
  warn "  7. Forgejo  — complete setup wizard (set host to http://$HOST_IP:3030)"
  warn "  8. Jellyfin — complete first-run media library wizard"
  warn "  9. Grafana  — Loki datasource UID is auto-generated; re-check OpenCanary dashboard"
  warn " 10. WireGuard — if port 51820 is taken by another VPN, change WG_PORT in devtools compose"
  echo ""
fi
