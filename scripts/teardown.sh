#!/bin/bash
# ============================================================
# Homelab — Teardown Script
# Stops and removes all stack containers.
# Data volumes are preserved unless you pass --volumes.
#
# Usage:
#   ./scripts/teardown.sh              — stop containers only
#   ./scripts/teardown.sh --volumes    — stop and remove volumes
#   ./scripts/teardown.sh --stack NN   — stop a single stack
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

REMOVE_VOLUMES=false
ONLY_STACK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volumes)    REMOVE_VOLUMES=true; shift ;;
    --stack)      ONLY_STACK="${2:-}"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--volumes] [--stack NN]"
      echo ""
      echo "  --volumes    Also remove Docker volumes (destructive — data will be lost)"
      echo "  --stack NN   Stop only the specified stack"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

DOWN_ARGS="down"
$REMOVE_VOLUMES && DOWN_ARGS="down -v" && warn "Volumes will be removed — all data in those stacks will be lost."

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
  [[ -n "$ONLY_STACK" && "$stack" != "$ONLY_STACK" ]] && continue
  dir="/opt/$stack"
  [ -f "$dir/docker-compose.yml" ] || continue
  info "Stopping $stack..."
  docker compose -f "$dir/docker-compose.yml" $DOWN_ARGS
done

info "Done."
$REMOVE_VOLUMES || echo "  Tip: data volumes are preserved. Use --volumes to also remove them."
