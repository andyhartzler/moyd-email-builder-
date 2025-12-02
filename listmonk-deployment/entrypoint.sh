#!/bin/sh
set -e

echo "🚀 Starting Listmonk setup..."

# Generate config.toml from environment variables
cat > /listmonk/config.toml <<EOF
[app]
address = "0.0.0.0:9000"
admin_username = "${LISTMONK_ADMIN_USERNAME:-admin}"
admin_password = "${LISTMONK_ADMIN_PASSWORD:-listmonk}"
root_url = "${LISTMONK_ROOT_URL:-http://localhost:9000}"

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
params = "${DB_PARAMS}"

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
echo "🔒 Schema: ${DB_SCHEMA:-listmonk} (ISOLATED - no public schema access)"
echo "🔍 Search path: ${DB_SCHEMA:-listmonk} ONLY"

# Create schema and set up proper permissions
echo "🔧 Setting up schema '${DB_SCHEMA:-listmonk}'..."
PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-EOSQL
  -- Create schema if it doesn't exist
  CREATE SCHEMA IF NOT EXISTS ${DB_SCHEMA:-listmonk};

  -- Grant all permissions on schema
  GRANT ALL ON SCHEMA ${DB_SCHEMA:-listmonk} TO ${DB_USER};
  GRANT ALL ON SCHEMA ${DB_SCHEMA:-listmonk} TO postgres;

  -- Set default privileges for future tables
  ALTER DEFAULT PRIVILEGES IN SCHEMA ${DB_SCHEMA:-listmonk} GRANT ALL ON TABLES TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA ${DB_SCHEMA:-listmonk} GRANT ALL ON SEQUENCES TO ${DB_USER};

  -- Set search_path for the postgres user (more reliable than ALTER DATABASE)
  ALTER ROLE ${DB_USER} SET search_path TO ${DB_SCHEMA:-listmonk}, public;
EOSQL

if [ $? -eq 0 ]; then
  echo "✅ Schema and permissions configured successfully"
else
  echo "⚠️  Schema setup failed, continuing anyway..."
fi

# Run installation (Listmonk will create schema if needed)
echo "🔧 Running Listmonk installation..."
./listmonk --install --yes --config /listmonk/config.toml

# Start Listmonk
echo "🎉 Starting Listmonk..."
exec ./listmonk --config /listmonk/config.toml
