#!/bin/bash
# ============================================================
# Homelab — Stack Status
# Shows running container state for every deployed stack.
# ============================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

STACKS=(
  monitoring apps authentik
  crowdsec wazuh
  tools devtools
  forgejo jenkins
  minio
  bookstack netbox defectdojo
  jellyfin paperless
  cyberchef searxng privatebin huginn restic shepherd
  opencanary
)

for stack in "${STACKS[@]}"; do
  dir="/opt/$stack"
  [ -f "$dir/docker-compose.yml" ] || continue
  echo -e "\n${CYAN}── $stack ──${NC}"
  docker compose -f "$dir/docker-compose.yml" ps 2>/dev/null || echo -e "${YELLOW}  (not running)${NC}"
done
