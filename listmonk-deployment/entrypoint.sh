#!/bin/sh
set -e

echo "🚀 Starting Listmonk setup..."

# Generate config.toml from environment variables
cat > /listmonk/config.toml <<EOF
[app]
address = "0.0.0.0:9000"
admin_username = "${LISTMONK_ADMIN_USERNAME:-admin}"
admin_password = "${LISTMONK_ADMIN_PASSWORD:-listmonk}"

[db]
host = "${DB_HOST:-localhost}"
port = ${DB_PORT:-5432}
user = "${DB_USER:-listmonk}"
password = "${DB_PASSWORD}"
database = "${DB_NAME:-postgres}"
ssl_mode = "${DB_SSL_MODE:-require}"
max_open = 25
max_idle = 10
max_lifetime = "300s"
params = "${DB_PARAMS:-search_path=${DB_SCHEMA:-listmonk}}"

[privacy]
individual_tracking = true
allow_blocklist = true
allow_export = true
allow_wipe = false
exportable = ["profile", "subscriptions", "campaign_views", "link_clicks"]

[media]
provider = "filesystem"
upload_path = "/listmonk/uploads"
upload_uri = "/uploads"

[security]
enable_captcha = false
EOF

echo "✅ Config file generated"
echo "📊 Database: ${DB_HOST}:${DB_PORT:-5432}/${DB_NAME:-postgres}"

# Create schema if it doesn't exist
echo "🔧 Creating schema if needed..."
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" \
  -p "${DB_PORT:-5432}" \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  -c "CREATE SCHEMA IF NOT EXISTS ${DB_SCHEMA:-listmonk};" \
  2>&1 | grep -v "already exists" || true

echo "✅ Schema ready"

# Run installation
echo "🔧 Running Listmonk installation..."
./listmonk --install --yes --config /listmonk/config.toml

# Start Listmonk
echo "🎉 Starting Listmonk..."
exec ./listmonk --config /listmonk/config.toml
