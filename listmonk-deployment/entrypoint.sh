#!/bin/sh
set -e

echo "🚀 Starting Listmonk setup..."

# Generate config.toml from environment variables
cat > /listmonk/config.toml <<EOF
[app]
address = "0.0.0.0:9000"
root_url = "${LISTMONK_ROOT_URL:-http://localhost:9000}"

# NOTE: admin_username and admin_password removed - v4.0+ stores credentials in database
# Admin user is created during migration or updated below

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
params = "options='-c search_path=${DB_SCHEMA:-listmonk},extensions,public'"

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

# AMAZON SES SMTP CONFIGURATION (HARDCODED - DO NOT MODIFY)
# Successfully tested: December 1, 2025
# Test email sent to: hartzlerandrew@gmail.com
[smtp]
  [[smtp.0]]
    enabled = true
    host = "email-smtp.us-east-2.amazonaws.com"
    port = 2587
    auth_protocol = "login"
    username = "AKIA3XRYIEHT3PLRTQWY"
    password = "BFOsxwg+srSHJYx4zbPX24dc4HEB28CHlhRCmxlrATac"
    hello_hostname = ""
    tls_enabled = true
    tls_skip_verify = false
    max_conns = 10
    max_msg_retries = 2
    idle_timeout = "15s"
    wait_timeout = "5s"
    email_headers = []
EOF

echo "✅ Config file generated"
echo "📊 Database: ${DB_HOST}:${DB_PORT:-5432}/${DB_NAME:-postgres}"
echo "🔒 Schema: ${DB_SCHEMA:-listmonk} (tables isolated in listmonk schema)"
echo "🔍 Search path: ${DB_SCHEMA:-listmonk}, extensions, public"
echo "🔧 Search path order: listmonk (tables) → extensions (Supabase extensions) → public (fallback)"
echo ""
echo "Generated config.toml [db] section:"
grep -A 10 "^\[db\]" /listmonk/config.toml

# Create schema and set up proper permissions
echo "🔧 Setting up schema '${DB_SCHEMA:-listmonk}'..."
PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-EOSQL
  -- Create schema if it doesn't exist
  CREATE SCHEMA IF NOT EXISTS ${DB_SCHEMA:-listmonk};

  -- Set search_path before creating extension so it goes into listmonk schema
  SET search_path TO ${DB_SCHEMA:-listmonk};

  -- Enable pgcrypto extension (required for gen_salt() function used in v4.0.0 migration)
  -- Create without SCHEMA clause to use current search_path
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  -- Grant all permissions on schema
  GRANT ALL ON SCHEMA ${DB_SCHEMA:-listmonk} TO ${DB_USER};
  GRANT ALL ON SCHEMA ${DB_SCHEMA:-listmonk} TO postgres;

  -- Set default privileges for future tables
  ALTER DEFAULT PRIVILEGES IN SCHEMA ${DB_SCHEMA:-listmonk} GRANT ALL ON TABLES TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA ${DB_SCHEMA:-listmonk} GRANT ALL ON SEQUENCES TO ${DB_USER};

  -- Set search_path at BOTH database and role level to ensure Listmonk can see tables AND extensions
  -- Order: listmonk (first, for tables), extensions (for Supabase extensions like pgcrypto), public (fallback)
  ALTER DATABASE ${DB_NAME} SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;
  ALTER ROLE ${DB_USER} IN DATABASE ${DB_NAME} SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;
EOSQL

if [ $? -eq 0 ]; then
  echo "✅ Schema and permissions configured successfully"
else
  echo "⚠️  Schema setup failed, continuing anyway..."
fi

# Check if tables already exist
echo "🔍 Checking if Listmonk tables exist..."
TABLE_COUNT=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_SCHEMA:-listmonk}' AND table_name = 'subscribers';")

if [ "$TABLE_COUNT" -gt 0 ]; then
  echo "✅ Listmonk tables already exist, checking if upgrade needed..."

  # Check current migration version
  echo "🔍 Checking current migration version..."
  CURRENT_VERSION=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT value FROM ${DB_SCHEMA:-listmonk}.settings WHERE key = 'migrations';" 2>/dev/null | tr -d ' \n')
  echo "   Current version: ${CURRENT_VERSION}"

  # If migration version exists but is not v5.1.0, run upgrade
  if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != '["v5.1.0"]' ]; then
    echo "🔄 Database needs upgrade. Running migrations from ${CURRENT_VERSION} to v5.1.0..."
    ./listmonk --upgrade --config /listmonk/config.toml --yes

    if [ $? -eq 0 ]; then
      echo "✅ Database upgraded successfully to v5.1.0"
    else
      echo "❌ Database upgrade failed"
      exit 1
    fi
  else
    echo "✅ Database is already at v5.1.0 or needs initialization"

    # Only set migration version if it doesn't exist
    if [ -z "$CURRENT_VERSION" ]; then
      echo "📝 Marking database as installed..."
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
        SET search_path TO ${DB_SCHEMA:-listmonk};
        INSERT INTO settings (key, value)
        VALUES('migrations', '["v5.1.0"]'::JSONB)
        ON CONFLICT (key) DO UPDATE SET value = '["v5.1.0"]'::JSONB;
EOSQL
      echo "✅ Database marked as installed"
    fi
  fi

  # Verify the migration record
  echo "🔍 Verifying migration record is accessible..."
  MIGRATION_CHECK=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SET search_path TO ${DB_SCHEMA:-listmonk}; SELECT value FROM settings WHERE key = 'migrations';")
  echo "   Migration value found: ${MIGRATION_CHECK}"

  # Update admin password (v4.0+ stores credentials in database, not config)
  echo "🔐 Setting admin user credentials..."
  PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
    SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

    -- Upsert admin user (insert if not exists, update password if exists)
    -- email is required field, using admin@localhost as default
    INSERT INTO users (username, password, name, type, status, email)
    VALUES ('admin', crypt('fucktrump67', gen_salt('bf')), 'Admin', 'user', 'enabled', 'admin@localhost')
    ON CONFLICT (username) DO UPDATE
    SET password = EXCLUDED.password;
EOSQL

  if [ $? -eq 0 ]; then
    echo "✅ Admin credentials set (username: admin, password: fucktrump67)"
  else
    echo "⚠️  Failed to set admin credentials, but continuing..."
  fi

  # Inject custom CSS to hide header and branding for embedded Flutter app
  echo "🎨 Injecting custom CSS to hide header and branding..."
  PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
    SET search_path TO ${DB_SCHEMA:-listmonk};

    -- Insert custom CSS to hide header bar, logo, and branding (using to_jsonb for proper formatting)
    INSERT INTO settings (key, value)
    VALUES('appearance.admin.custom_css', to_jsonb('/* MOYD Custom Branding - Missouri Young Democrats */

/* ===== REMOVE ONLY THE TOP NAVBAR (keep modals and dialogs working!) ===== */
/* Target ONLY the fixed-top navbar, not all nav elements */
nav.navbar.is-fixed-top {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
}

/* Adjust body padding since navbar is removed */
body.has-navbar-fixed-top {
  padding-top: 0 !important;
}

/* ===== REMOVE PAGE FOOTER BRANDING (but KEEP modal footers!) ===== */
/* Only hide main page footer, NOT modal footers */
body > footer:not(.modal-card-foot),
.app-footer:not(.modal-card-foot),
.page-footer:not(.modal-card-foot) {
  display: none !important;
}

/* Ensure modal footers with buttons stay visible */
.modal-card-foot,
.modal-footer,
.modal .modal-card-foot {
  display: flex !important;
  visibility: visible !important;
}

/* ===== LOGIN PAGE CUSTOMIZATION ===== */
/* Hide only the login page logo container content */
.login .container .logo {
  min-height: 200px;
}

.login .container .logo img,
.login .container .logo svg {
  display: none !important;
}

/* Add custom MOYD logo to login page */
.login .container .logo::before {
  content: "" !important;
  display: block !important;
  width: 200px !important;
  height: 200px !important;
  margin: 0 auto !important;
  background-image: url("/uploads/MOYD01.png") !important;
  background-size: contain !important;
  background-repeat: no-repeat !important;
  background-position: center !important;
}

/* Hide only login page footer (powered by text) */
.login footer.footer {
  display: none !important;
}

/* ===== CHANGE ALL BLUE TO #273351 ===== */
/* Primary color changes */
.button.is-primary, .button.is-link,
.button.is-info, a.button.is-primary,
.has-background-primary, .tag.is-primary,
.notification.is-primary, .message.is-primary,
.hero.is-primary, .navbar.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

/* Link colors */
a, a:hover, a:active, a:focus,
.has-text-primary, .has-text-link, .has-text-info {
  color: #273351 !important;
}

/* Tab and nav active states */
.tabs a:hover, .tabs li.is-active a,
.menu-list a.is-active, .menu-list a:hover {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

/* Progress bars and loaders */
.progress::-webkit-progress-value,
.progress::-moz-progress-bar {
  background-color: #273351 !important;
}

/* Inputs and selects focus */
.input:focus, .textarea:focus, .select select:focus,
.input:active, .textarea:active, .select select:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

/* Checkboxes and radios */
.checkbox:hover, .radio:hover,
input[type="checkbox"]:checked,
input[type="radio"]:checked {
  border-color: #273351 !important;
  background-color: #273351 !important;
}

/* Pagination */
.pagination-link.is-current,
.pagination-previous:hover, .pagination-next:hover,
.pagination-link:hover {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

/* Tables */
.table tr.is-selected {
  background-color: #273351 !important;
  color: white !important;
}

/* Tags and badges */
.tag.is-info, .tag.is-link, .badge {
  background-color: #273351 !important;
}

/* Switches and toggles */
.switch input[type="checkbox"]:checked + .check {
  background-color: #273351 !important;
}

/* Loading spinners */
.loader, .spinner {
  border-color: #273351 transparent transparent transparent !important;
}

/* Dropdown active items */
.dropdown-item.is-active, .dropdown-item:hover {
  background-color: #273351 !important;
  color: white !important;
}

/* Modal and panel headers */
.modal-card-head, .panel-heading {
  background-color: #273351 !important;
}

/* Sidebar active items */
.menu-list a.router-link-active,
.menu-list a.is-active {
  background-color: #273351 !important;
  color: white !important;
}
'::text))
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

  if [ $? -eq 0 ]; then
    echo "✅ Custom CSS injected successfully"
  else
    echo "⚠️  Failed to inject custom CSS, but continuing..."
  fi
else
  echo "📦 Installing Listmonk schema manually..."
  # Run schema.sql with explicit search_path set to ONLY listmonk (not public!)
  PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
    -- Set search_path to ONLY listmonk schema (exclude public to protect existing tables!)
    SET search_path TO ${DB_SCHEMA:-listmonk};

    -- Run the schema file
    \i /listmonk/schema.sql
EOSQL

  if [ $? -eq 0 ]; then
    echo "✅ Listmonk schema installed successfully"

    # Mark database as installed by adding migration version to settings table
    echo "📝 Marking database as installed..."
    PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
      -- Set search_path for this session
      SET search_path TO ${DB_SCHEMA:-listmonk};

      -- Mark as installed (this is what --install does)
      INSERT INTO settings (key, value)
      VALUES('migrations', '["v5.1.0"]'::JSONB)
      ON CONFLICT (key) DO UPDATE SET value = '["v5.1.0"]'::JSONB;
EOSQL

    if [ $? -eq 0 ]; then
      echo "✅ Database marked as installed"

      # Debug: Verify the migration record can be found
      echo "🔍 Verifying migration record is accessible..."
      MIGRATION_CHECK=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SET search_path TO ${DB_SCHEMA:-listmonk}; SELECT value FROM settings WHERE key = 'migrations';")
      echo "   Migration value found: ${MIGRATION_CHECK}"

      # Update admin password (v4.0+ stores credentials in database, not config)
      echo "🔐 Setting admin user credentials..."
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
        SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

        -- Upsert admin user (insert if not exists, update password if exists)
        -- email is required field, using admin@localhost as default
        INSERT INTO users (username, password, name, type, status, email)
        VALUES ('admin', crypt('fucktrump67', gen_salt('bf')), 'Admin', 'user', 'enabled', 'admin@localhost')
        ON CONFLICT (username) DO UPDATE
        SET password = EXCLUDED.password;
EOSQL

      if [ $? -eq 0 ]; then
        echo "✅ Admin credentials set (username: admin, password: fucktrump67)"
      else
        echo "⚠️  Failed to set admin credentials, but continuing..."
      fi

      # Inject custom CSS to hide header and branding for embedded Flutter app
      echo "🎨 Injecting custom CSS to hide header and branding..."
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL
        SET search_path TO ${DB_SCHEMA:-listmonk};

        -- Insert custom CSS to hide header bar, logo, and branding (using to_jsonb for proper formatting)
        INSERT INTO settings (key, value)
        VALUES('appearance.admin.custom_css', to_jsonb('/* MOYD Custom Branding - Missouri Young Democrats */

/* ===== REMOVE ONLY THE TOP NAVBAR (keep modals and dialogs working!) ===== */
/* Target ONLY the fixed-top navbar, not all nav elements */
nav.navbar.is-fixed-top {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
}

/* Adjust body padding since navbar is removed */
body.has-navbar-fixed-top {
  padding-top: 0 !important;
}

/* ===== REMOVE PAGE FOOTER BRANDING (but KEEP modal footers!) ===== */
/* Only hide main page footer, NOT modal footers */
body > footer:not(.modal-card-foot),
.app-footer:not(.modal-card-foot),
.page-footer:not(.modal-card-foot) {
  display: none !important;
}

/* Ensure modal footers with buttons stay visible */
.modal-card-foot,
.modal-footer,
.modal .modal-card-foot {
  display: flex !important;
  visibility: visible !important;
}

/* ===== LOGIN PAGE CUSTOMIZATION ===== */
/* Hide only the login page logo container content */
.login .container .logo {
  min-height: 200px;
}

.login .container .logo img,
.login .container .logo svg {
  display: none !important;
}

/* Add custom MOYD logo to login page */
.login .container .logo::before {
  content: "" !important;
  display: block !important;
  width: 200px !important;
  height: 200px !important;
  margin: 0 auto !important;
  background-image: url("/uploads/MOYD01.png") !important;
  background-size: contain !important;
  background-repeat: no-repeat !important;
  background-position: center !important;
}

/* Hide only login page footer (powered by text) */
.login footer.footer {
  display: none !important;
}

/* ===== CHANGE ALL BLUE TO #273351 ===== */
/* Primary color changes */
.button.is-primary, .button.is-link,
.button.is-info, a.button.is-primary,
.has-background-primary, .tag.is-primary,
.notification.is-primary, .message.is-primary,
.hero.is-primary, .navbar.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

/* Link colors */
a, a:hover, a:active, a:focus,
.has-text-primary, .has-text-link, .has-text-info {
  color: #273351 !important;
}

/* Tab and nav active states */
.tabs a:hover, .tabs li.is-active a,
.menu-list a.is-active, .menu-list a:hover {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

/* Progress bars and loaders */
.progress::-webkit-progress-value,
.progress::-moz-progress-bar {
  background-color: #273351 !important;
}

/* Inputs and selects focus */
.input:focus, .textarea:focus, .select select:focus,
.input:active, .textarea:active, .select select:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

/* Checkboxes and radios */
.checkbox:hover, .radio:hover,
input[type="checkbox"]:checked,
input[type="radio"]:checked {
  border-color: #273351 !important;
  background-color: #273351 !important;
}

/* Pagination */
.pagination-link.is-current,
.pagination-previous:hover, .pagination-next:hover,
.pagination-link:hover {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

/* Tables */
.table tr.is-selected {
  background-color: #273351 !important;
  color: white !important;
}

/* Tags and badges */
.tag.is-info, .tag.is-link, .badge {
  background-color: #273351 !important;
}

/* Switches and toggles */
.switch input[type="checkbox"]:checked + .check {
  background-color: #273351 !important;
}

/* Loading spinners */
.loader, .spinner {
  border-color: #273351 transparent transparent transparent !important;
}

/* Dropdown active items */
.dropdown-item.is-active, .dropdown-item:hover {
  background-color: #273351 !important;
  color: white !important;
}

/* Modal and panel headers */
.modal-card-head, .panel-heading {
  background-color: #273351 !important;
}

/* Sidebar active items */
.menu-list a.router-link-active,
.menu-list a.is-active {
  background-color: #273351 !important;
  color: white !important;
}
'::text))
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

      if [ $? -eq 0 ]; then
        echo "✅ Custom CSS injected successfully"
      else
        echo "⚠️  Failed to inject custom CSS, but continuing..."
      fi
    else
      echo "⚠️  Failed to mark database as installed, but continuing..."
    fi
  else
    echo "❌ Schema installation failed"
    exit 1
  fi
fi

# Final verification before starting Listmonk
echo "🔍 Final check: Verifying search_path and data accessibility..."
echo "   Testing default search_path for postgres user..."
CURRENT_SEARCH_PATH=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SHOW search_path;")
echo "   Current search_path: ${CURRENT_SEARCH_PATH}"

echo "   Testing if settings table is accessible without explicit search_path..."
SETTINGS_CHECK=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM settings;" 2>&1 || echo "FAILED")
echo "   Settings table accessible: ${SETTINGS_CHECK}"

# Start Listmonk
echo "🎉 Starting Listmonk..."
exec ./listmonk --config /listmonk/config.toml
