#!/bin/bash
# ============================================================
# Homelab — Secret Generator
# Generates all required secrets and prints them ready to
# paste into your .env file.
#
# Requires: python3, docker
# ============================================================
set -euo pipefail

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }
command -v docker  >/dev/null || { echo "docker is required (for BookStack APP_KEY)"; exit 1; }

echo "# ── Generated secrets — paste into .env ────────────────────"
echo ""

echo "# Authentik SECRET_KEY (50 chars)"
echo "AUTHENTIK_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")"
echo ""

echo "# Netbox SECRET_KEY (60+ chars)"
echo "NETBOX_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(60))")"
echo ""

echo "# n8n ENCRYPTION_KEY (32 hex chars)"
echo "N8N_ENCRYPTION_KEY=$(python3 -c "import secrets; print(secrets.token_hex(16))")"
echo ""

echo "# Semaphore ACCESS_KEY_ENCRYPTION (32 hex chars)"
echo "SEMAPHORE_ACCESS_KEY_ENCRYPTION=$(python3 -c "import secrets; print(secrets.token_hex(16))")"
echo ""

echo "# Vaultwarden ADMIN_TOKEN"
echo "VAULTWARDEN_ADMIN_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")"
echo ""

echo "# Paperless SECRET_KEY (50+ chars)"
echo "PAPERLESS_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")"
echo ""

echo "# Huginn SECRET_TOKEN (50+ chars)"
echo "HUGINN_SECRET_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")"
echo ""

echo "# Netbox SECRET_KEY (60+ chars)"
echo "NETBOX_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(60))")"
echo ""

echo "# DefectDojo SECRET_KEY"
echo "DEFECTDOJO_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(40))")"
echo ""

echo "# DefectDojo CREDENTIAL_KEY (exactly 16 chars)"
echo "DEFECTDOJO_CREDENTIAL_KEY=$(python3 -c "import secrets; print(secrets.token_hex(8))")"
echo ""

echo "# BookStack APP_KEY (pulling image — this may take a moment)"
BOOKSTACK_KEY=$(docker run --rm --entrypoint /bin/bash \
  lscr.io/linuxserver/bookstack:latest appkey 2>/dev/null | tr -d '\r\n')
echo "BOOKSTACK_APP_KEY=$BOOKSTACK_KEY"
echo ""

echo "# ── WireGuard password hash ────────────────────────────────"
echo "# Run the following manually and paste the result into .env as WG_PASSWORD_HASH."
echo "# Double up all \$ signs before pasting (e.g. \$\$2b\$\$12\$\$...)."
echo "#"
echo "#   echo -n 'yourpassword' | docker run --rm -i ghcr.io/wg-easy/wg-easy wgpw"
echo ""
