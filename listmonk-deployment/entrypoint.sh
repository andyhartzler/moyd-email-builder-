#!/bin/sh
set -e

echo "🚀 Starting Listmonk setup..."

# Generate config.toml from environment variables
# NOTE: Listmonk runs on port 9001 internally; nginx proxies from port 9000
cat > /listmonk/config.toml <<EOF
[app]
address = "0.0.0.0:9001"
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
max_open = ${DB_MAX_OPEN:-5}
max_idle = ${DB_MAX_IDLE:-2}
max_lifetime = "${DB_MAX_LIFETIME:-60s}"
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

# CORS configuration - Allow CRM domain (moyd.app) for auto-authentication
# This allows the Flutter CRM to make API requests to Listmonk
cors_allowed_origins = ["https://moyd.app", "https://www.moyd.app", "https://*.moyd.app", "http://localhost:*"]
cors_allowed_headers = ["Content-Type", "Authorization", "Cookie", "X-Requested-With"]
cors_allowed_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_credentials = true

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

echo "✅ Config file generated with connection pool settings"
echo "📊 Database: ${DB_HOST}:${DB_PORT:-5432}/${DB_NAME:-postgres}"
echo "🔒 Schema: ${DB_SCHEMA:-listmonk} (tables isolated in listmonk schema)"
echo "🔍 Search path: ${DB_SCHEMA:-listmonk}, extensions, public"
echo "🔧 Search path order: listmonk (tables) → extensions (Supabase extensions) → public (fallback)"
echo "🔄 Connection pool: max_open=${DB_MAX_OPEN:-5}, max_idle=${DB_MAX_IDLE:-2}, max_lifetime=${DB_MAX_LIFETIME:-60s}"
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
    -- user_role_id = 1 is the "Super Admin" role created by v4.0.0 migration
    INSERT INTO users (username, password, name, type, status, email, user_role_id)
    VALUES ('admin', crypt('fucktrump67', gen_salt('bf')), 'Admin', 'user', 'enabled', 'admin@localhost', 1)
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

/* ===== FIX DARK TEXT ON TEMPLATE PAGE ===== */
/* Make template header text more visible */
.template-header h1,
.template-header .tag,
.template-header small,
.content h1, .content h2, .content h3,
.title, .subtitle {
  color: #2c3e50 !important;
}

/* Lighter text for IDs and metadata */
.template-header .tag.is-light,
small, .help-text {
  color: #666 !important;
}

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

/* ===== CHANGE ALL BLUE TO #273351 ===== */
/* Primary color changes */
.button.is-primary, .button.is-link,
.button.is-info, a.button.is-primary,
.has-background-primary, .tag.is-primary,
.notification.is-primary, .message.is-primary,
.hero.is-primary, .navbar.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
}

/* Link colors */
a, a:hover, a:active, a:focus,
.has-text-primary, .has-text-link, .has-text-info {
  color: #273351 !important;
}

/* Tab and nav active states */
.tabs a:hover, .tabs li.is-active a {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

/* Menu list items with navy background - WHITE TEXT for visibility */
.menu-list a.is-active,
.menu-list a:hover,
.menu-list a.router-link-active {
  background-color: #273351 !important;
  color: white !important;
  border-bottom-color: #273351 !important;
}

/* ===== CUSTOM BUTTONS SPACE ===== */
/* Create space above the menu for custom buttons */
.menu {
  margin-top: 70px !important;
}

/* Hide CSS pseudo-element buttons (JavaScript will create real clickable buttons) */
.menu::before,
.menu::after {
  display: none !important;
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
  color: white !important;
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

/* ===== MOBILE RESPONSIVE STYLES ===== */

/* Tablet and smaller (max-width: 768px) */
@media screen and (max-width: 768px) {
  /* Reduce menu margin on mobile */
  .menu {
    margin-top: 60px !important;
    padding: 0 10px !important;
  }

  /* Make buttons and inputs touch-friendly (min 44px height) */
  .button, button,
  .input, .textarea, .select select {
    min-height: 44px !important;
    font-size: 16px !important; /* Prevents iOS zoom on focus */
  }

  /* Responsive sidebar */
  .sidebar, .menu-list {
    width: 100% !important;
  }

  .menu-list a {
    padding: 12px 16px !important;
    min-height: 44px !important;
    display: flex !important;
    align-items: center !important;
  }

  /* Responsive tables - allow horizontal scroll */
  .table-container, .b-table {
    overflow-x: auto !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .table {
    min-width: 600px !important;
  }

  /* Stack form elements */
  .field.is-horizontal .field-body {
    flex-direction: column !important;
  }

  .field.is-horizontal .field-label {
    margin-bottom: 8px !important;
  }

  /* Modal improvements */
  .modal-card {
    width: calc(100% - 32px) !important;
    max-width: 100% !important;
    margin: 16px !important;
    max-height: calc(100vh - 32px) !important;
  }

  .modal-card-body {
    padding: 16px !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .modal-card-head, .modal-card-foot {
    padding: 12px 16px !important;
  }

  /* Responsive spacing */
  .section {
    padding: 1.5rem 1rem !important;
  }

  .container {
    padding-left: 12px !important;
    padding-right: 12px !important;
  }

  /* Cards and boxes */
  .box, .card {
    padding: 16px !important;
    margin: 12px 0 !important;
  }

  /* Responsive columns - stack on mobile */
  .columns.is-mobile-stacked {
    flex-direction: column !important;
  }

  .columns.is-mobile-stacked .column {
    width: 100% !important;
    flex: none !important;
  }

  /* Hide less important columns on mobile */
  .is-hidden-mobile {
    display: none !important;
  }

  /* Tags and badges - smaller on mobile */
  .tag {
    font-size: 0.7rem !important;
    padding: 4px 8px !important;
  }

  /* Pagination touch-friendly */
  .pagination-link, .pagination-previous, .pagination-next {
    min-width: 44px !important;
    min-height: 44px !important;
    padding: 8px !important;
  }

  /* Dropdown touch-friendly */
  .dropdown-item {
    padding: 12px 16px !important;
    min-height: 44px !important;
  }

  /* Tabs - scrollable on mobile */
  .tabs {
    overflow-x: auto !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .tabs ul {
    flex-wrap: nowrap !important;
  }

  .tabs li {
    flex-shrink: 0 !important;
  }
}

/* Small phones (max-width: 480px) */
@media screen and (max-width: 480px) {
  /* Even smaller menu margin */
  .menu {
    margin-top: 55px !important;
  }

  /* Larger touch targets */
  .button, button,
  .input, .textarea, .select select {
    min-height: 48px !important;
  }

  .menu-list a {
    padding: 14px 12px !important;
    min-height: 48px !important;
  }

  /* Smaller fonts for very small screens */
  .title.is-4, .title.is-5 {
    font-size: 1.1rem !important;
  }

  .subtitle {
    font-size: 0.9rem !important;
  }

  /* Full-width buttons on small screens */
  .buttons .button {
    width: 100% !important;
    margin-bottom: 8px !important;
  }

  .buttons {
    flex-direction: column !important;
  }

  /* Modal - almost full screen */
  .modal-card {
    width: calc(100% - 20px) !important;
    margin: 10px !important;
    max-height: calc(100vh - 20px) !important;
  }

  /* Smaller section padding */
  .section {
    padding: 1rem 0.75rem !important;
  }

  /* Cards even smaller padding */
  .box, .card {
    padding: 12px !important;
  }

  /* Pagination - compact */
  .pagination-link, .pagination-previous, .pagination-next {
    font-size: 0.85rem !important;
  }
}

/* Touch device specific styles */
@media (hover: none) and (pointer: coarse) {
  /* Increase tap targets for touch devices */
  .button, button, a.button {
    min-height: 44px !important;
  }

  /* Remove hover effects that cause issues on touch */
  .button:hover, button:hover {
    transform: none !important;
  }

  /* Better touch scrolling */
  .table-container, .modal-card-body, .menu {
    -webkit-overflow-scrolling: touch !important;
  }

  /* Prevent text selection on interactive elements */
  .button, button, .menu-list a, .dropdown-item, .pagination-link {
    -webkit-user-select: none !important;
    user-select: none !important;
  }
}

/* Landscape mobile orientation */
@media screen and (max-height: 500px) and (orientation: landscape) {
  .menu {
    margin-top: 50px !important;
  }

  .modal-card {
    max-height: 90vh !important;
  }

  .modal-card-body {
    max-height: 50vh !important;
    overflow-y: auto !important;
  }
}

/* Safe area support for notched devices (iPhone X+) */
@supports (padding: env(safe-area-inset-bottom)) {
  .modal-card-foot {
    padding-bottom: calc(12px + env(safe-area-inset-bottom)) !important;
  }

  .menu {
    padding-bottom: env(safe-area-inset-bottom) !important;
  }
}
'::text))
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

  if [ $? -eq 0 ]; then
    echo "✅ Custom CSS injected successfully"

    # Also inject custom JavaScript for buttons (INLINE CODE)
    # NOTE: Using appearance.admin.custom_js (NOT custom_head!)
    # The custom_js field expects JavaScript code, not HTML
    echo "💻 Injecting custom JavaScript for buttons..."
    PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL2'
      SET search_path TO listmonk, extensions, public;

      DELETE FROM settings WHERE key = 'appearance.admin.custom_js';
      DELETE FROM settings WHERE key = 'appearance.admin.custom_head';

      INSERT INTO settings (key, value)
      VALUES('appearance.admin.custom_js', to_jsonb('(function() {
  "use strict";

  function isMobile() {
    return window.innerWidth <= 768 || ("ontouchstart" in window) || (navigator.maxTouchPoints > 0);
  }

  function getButtonSize() {
    if (window.innerWidth <= 480) return 48;
    if (window.innerWidth <= 768) return 44;
    return 40;
  }

  function init() {
    var menu = document.querySelector(".menu");
    if (!menu) { setTimeout(init, 500); return; }

    var existing = document.getElementById("moyd-custom-buttons");
    if (existing) existing.remove();

    var buttonSize = getButtonSize();
    var mobile = isMobile();

    var buttonsContainer = document.createElement("div");
    buttonsContainer.id = "moyd-custom-buttons";
    buttonsContainer.style.cssText = "position: fixed; top: " + (mobile ? "10px" : "15px") + "; left: " + (mobile ? "10px" : "15px") + "; z-index: 1000; display: flex; gap: " + (mobile ? "8px" : "10px") + ";";

    var refreshBtn = document.createElement("button");
    refreshBtn.innerHTML = "🔄";
    refreshBtn.title = "Refresh Page";
    refreshBtn.setAttribute("aria-label", "Refresh Page");
    refreshBtn.style.cssText = "width: " + buttonSize + "px; height: " + buttonSize + "px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: " + (mobile ? "18px" : "20px") + "; cursor: pointer; transition: all 0.3s ease; -webkit-tap-highlight-color: transparent; touch-action: manipulation;";

    function refreshBtnActive() { refreshBtn.style.transform = "rotate(180deg)"; refreshBtn.style.backgroundColor = "#1a2438"; }
    function refreshBtnInactive() { refreshBtn.style.transform = "rotate(0deg)"; refreshBtn.style.backgroundColor = "#273351"; }
    refreshBtn.addEventListener("mouseenter", refreshBtnActive);
    refreshBtn.addEventListener("mouseleave", refreshBtnInactive);
    refreshBtn.addEventListener("touchstart", refreshBtnActive, { passive: true });
    refreshBtn.addEventListener("touchend", refreshBtnInactive, { passive: true });
    refreshBtn.addEventListener("click", function(e) { e.preventDefault(); location.reload(); });

    var reportBtn = document.createElement("button");
    reportBtn.innerHTML = "?";
    reportBtn.title = "Report a Problem";
    reportBtn.setAttribute("aria-label", "Report a Problem");
    reportBtn.style.cssText = "width: " + buttonSize + "px; height: " + buttonSize + "px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: " + (mobile ? "22px" : "24px") + "; font-weight: bold; cursor: pointer; transition: background-color 0.3s ease; -webkit-tap-highlight-color: transparent; touch-action: manipulation;";

    function reportBtnActive() { reportBtn.style.backgroundColor = "#1a2438"; }
    function reportBtnInactive() { reportBtn.style.backgroundColor = "#273351"; }
    reportBtn.addEventListener("mouseenter", reportBtnActive);
    reportBtn.addEventListener("mouseleave", reportBtnInactive);
    reportBtn.addEventListener("touchstart", reportBtnActive, { passive: true });
    reportBtn.addEventListener("touchend", reportBtnInactive, { passive: true });
    reportBtn.addEventListener("click", function(e) { e.preventDefault(); showReportModal(); });

    buttonsContainer.appendChild(refreshBtn);
    buttonsContainer.appendChild(reportBtn);
    document.body.appendChild(buttonsContainer);
    menu.style.marginTop = mobile ? "15px" : "20px";
    console.log("[MOYD] Admin buttons loaded (mobile-optimized)");
  }

  function showReportModal() {
    var existing = document.getElementById("moyd-report-modal");
    if (existing) existing.remove();

    var mobile = isMobile();
    var smallPhone = window.innerWidth <= 480;

    var modal = document.createElement("div");
    modal.id = "moyd-report-modal";
    modal.style.cssText = "position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 10000; padding: " + (mobile ? "16px" : "20px") + "; box-sizing: border-box;";

    var modalContent = document.createElement("div");
    modalContent.style.cssText = "background: white; padding: " + (smallPhone ? "20px" : mobile ? "25px" : "30px") + "; border-radius: 12px; width: 100%; max-width: " + (mobile ? "100%" : "500px") + "; max-height: 90vh; overflow-y: auto; box-shadow: 0 4px 20px rgba(0,0,0,0.3); -webkit-overflow-scrolling: touch;";

    var contactBtnStyle = "flex: " + (smallPhone ? "1 1 100%" : "1") + "; display: flex; flex-direction: column; align-items: center; padding: " + (mobile ? "16px 12px" : "20px") + "; background: #273351; color: white; text-decoration: none; border-radius: 8px; min-height: 44px; -webkit-tap-highlight-color: transparent;";

    modalContent.innerHTML = "<h2 style=\\\"margin: 0 0 10px 0; color: #273351; font-size: " + (smallPhone ? "20px" : "24px") + ";\\\">Report a Problem</h2><p style=\\\"margin: 0 0 " + (mobile ? "20px" : "25px") + " 0; color: #666; font-size: " + (smallPhone ? "13px" : "14px") + ";\\\">Having an issue? Contact Andrew directly via text message or email.</p><div style=\\\"display: flex; flex-wrap: wrap; gap: " + (mobile ? "12px" : "15px") + "; margin-bottom: " + (mobile ? "16px" : "20px") + ";\\\"><a href=\\\"sms:+18168983612\\\" id=\\\"moyd-sms-btn\\\" style=\\\"" + contactBtnStyle + "\\\"><span style=\\\"font-size: " + (smallPhone ? "28px" : "32px") + "; margin-bottom: " + (mobile ? "8px" : "10px") + ";\\\">💬</span><span style=\\\"font-size: " + (smallPhone ? "14px" : "16px") + "; font-weight: bold;\\\">Send Text</span><span style=\\\"font-size: " + (smallPhone ? "11px" : "12px") + "; margin-top: 5px; opacity: 0.9;\\\">816-898-3612</span></a><a href=\\\"mailto:andrew@moyoungdemocrats.org?subject=MOYD%20App%20Issue\\\" id=\\\"moyd-email-btn\\\" style=\\\"" + contactBtnStyle + "\\\"><span style=\\\"font-size: " + (smallPhone ? "28px" : "32px") + "; margin-bottom: " + (mobile ? "8px" : "10px") + ";\\\">✉️</span><span style=\\\"font-size: " + (smallPhone ? "14px" : "16px") + "; font-weight: bold;\\\">Send Email</span><span style=\\\"font-size: " + (smallPhone ? "11px" : "12px") + "; margin-top: 5px; opacity: 0.9;\\\">andrew@moyoungdemocrats.org</span></a></div><button id=\\\"moyd-close-modal-btn\\\" style=\\\"width: 100%; padding: " + (mobile ? "14px" : "12px") + "; background: #e0e0e0; border: none; border-radius: 8px; color: #333; font-size: " + (smallPhone ? "15px" : "14px") + "; cursor: pointer; min-height: 44px; -webkit-tap-highlight-color: transparent;\\\">Close</button>";

    modal.appendChild(modalContent);
    document.body.appendChild(modal);

    var closeBtn = document.getElementById("moyd-close-modal-btn");
    closeBtn.addEventListener("click", function(e) { e.preventDefault(); modal.remove(); document.body.style.overflow = ""; });

    modal.addEventListener("click", function(e) { if (e.target === modal) { modal.remove(); document.body.style.overflow = ""; } });
    document.body.style.overflow = "hidden";
    closeBtn.focus();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  var resizeTimeout;
  window.addEventListener("resize", function() { clearTimeout(resizeTimeout); resizeTimeout = setTimeout(init, 250); });
  window.addEventListener("orientationchange", function() { setTimeout(init, 100); });
})();'::text));
EOSQL2

    if [ $? -eq 0 ]; then
      echo "✅ Custom JavaScript injection configured (inline code)"

      # Also inject public CSS for login page
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL3
        SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

        -- Add custom CSS for public pages (login, subscription forms, etc.) (FORCE UPDATE)
        DELETE FROM settings WHERE key = 'appearance.public.custom_css';
        INSERT INTO settings (key, value)
        VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Login Page Customization - Missouri Young Democrats */

/* ===== LOGIN PAGE LOGO ===== */
/* Center the login container */
.login .container {
  max-width: 500px;
  margin: 0 auto;
  padding: 40px 20px;
}

/* Login logo container */
.login .container .logo {
  min-height: 220px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  margin-bottom: 30px !important;
}

/* Hide default listmonk logo */
.login .container .logo img,
.login .container .logo svg {
  display: none !important;
}

/* Add custom MOYD logo - centered properly */
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

/* ===== LOGIN PAGE COLORS - MOYD NAVY BLUE ===== */
/* Login button - MOYD navy blue with white text */
.login .button.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
  font-weight: 600;
}

.login .button.is-primary:hover {
  background-color: #1a2438 !important;
  border-color: #1a2438 !important;
}

/* Input focus states - MOYD navy blue */
.login .input:focus,
.login .input:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

/* Links - MOYD navy blue */
.login a {
  color: #273351 !important;
}

.login a:hover {
  color: #1a2438 !important;
}

/* ===== HIDE "POWERED BY LISTMONK" FOOTER ===== */
.login footer.footer,
.login .footer,
footer.footer {
  display: none !important;
  visibility: hidden !important;
}

/* ===== LOGIN PAGE LAYOUT ===== */
/* Center login form */
.login .box {
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  border-radius: 8px;
}

/* Login page title */
.login .title {
  color: #273351 !important;
  text-align: center;
  margin-bottom: 25px;
}

/* ===== MOBILE RESPONSIVE LOGIN ===== */

/* Tablet and smaller */
@media screen and (max-width: 768px) {
  .login .container {
    padding: 20px 16px !important;
    max-width: 100% !important;
  }

  .login .container .logo {
    min-height: 150px !important;
    margin-bottom: 20px !important;
  }

  .login .container .logo::before {
    width: 140px !important;
    height: 140px !important;
  }

  .login .box {
    padding: 20px !important;
  }

  .login .input {
    min-height: 44px !important;
    font-size: 16px !important;
  }

  .login .button {
    min-height: 44px !important;
    font-size: 16px !important;
  }

  .login .title {
    font-size: 1.5rem !important;
    margin-bottom: 20px !important;
  }
}

/* Small phones */
@media screen and (max-width: 480px) {
  .login .container {
    padding: 16px 12px !important;
  }

  .login .container .logo {
    min-height: 120px !important;
    margin-bottom: 16px !important;
  }

  .login .container .logo::before {
    width: 100px !important;
    height: 100px !important;
  }

  .login .box {
    padding: 16px !important;
  }

  .login .input {
    min-height: 48px !important;
  }

  .login .button {
    min-height: 48px !important;
  }

  .login .title {
    font-size: 1.25rem !important;
  }

  .login .field:not(:last-child) {
    margin-bottom: 12px !important;
  }
}

/* Touch device specific */
@media (hover: none) and (pointer: coarse) {
  .login .input, .login .button {
    min-height: 44px !important;
  }
}
'::text));
EOSQL3

      if [ $? -eq 0 ]; then
        echo "✅ Public CSS (login page) injected successfully"
      else
        echo "⚠️  Failed to inject public CSS, but continuing..."
      fi

      # ========================================
      # INJECT LOGIN FORM ENHANCEMENT JAVASCRIPT
      # For CRM auto-authentication support
      # ========================================
      echo "📝 Injecting login form enhancement JavaScript..."
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_LOGIN_JS'
        SET search_path TO listmonk, extensions, public;

        -- Delete existing public JS to avoid duplicates
        DELETE FROM settings WHERE key = 'appearance.public.custom_js';

        -- Insert login form enhancement for CRM auto-authentication
        -- This adds predictable IDs and attributes to form elements
        -- so the Flutter CRM can reliably auto-fill the login form
        INSERT INTO settings (key, value)
        VALUES('appearance.public.custom_js', to_jsonb('(function() {
  "use strict";

  // Only run on admin pages (login page)
  if (!window.location.pathname.includes("/admin")) return;

  function enhanceForm() {
    // Find all input elements
    var inputs = document.querySelectorAll("input");

    inputs.forEach(function(input) {
      var type = input.type.toLowerCase();

      // Enhance username/email field
      if (type === "text" || type === "email") {
        input.setAttribute("name", "username");
        input.setAttribute("id", "moyd-username");
        input.setAttribute("data-testid", "username-input");
        input.setAttribute("autocomplete", "username");
      }

      // Enhance password field
      if (type === "password") {
        input.setAttribute("name", "password");
        input.setAttribute("id", "moyd-password");
        input.setAttribute("data-testid", "password-input");
        input.setAttribute("autocomplete", "current-password");
      }
    });

    // Enhance submit button
    var button = document.querySelector("button[type=\"submit\"], form button");
    if (button) {
      button.setAttribute("id", "moyd-submit");
      button.setAttribute("data-testid", "submit-button");
    }

    // Enhance form element
    var form = document.querySelector("form");
    if (form) {
      form.setAttribute("id", "moyd-login-form");
      form.setAttribute("data-testid", "login-form");
    }

    console.log("[MOYD] Login form attributes added for CRM auto-auth");
  }

  // Run immediately
  enhanceForm();

  // Also run after delays to catch dynamically loaded content
  setTimeout(enhanceForm, 100);
  setTimeout(enhanceForm, 500);
  setTimeout(enhanceForm, 1000);
  setTimeout(enhanceForm, 2000);

  // Observe for dynamic changes (Vue.js/React may re-render)
  if (typeof MutationObserver !== "undefined") {
    var observer = new MutationObserver(function(mutations) {
      enhanceForm();
    });

    if (document.body) {
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    }

    // Stop observing after 10 seconds to prevent performance issues
    setTimeout(function() {
      observer.disconnect();
    }, 10000);
  }
})();'::text));
EOSQL_LOGIN_JS

      if [ $? -eq 0 ]; then
        echo "✅ Login form enhancement JavaScript injected successfully"
      else
        echo "⚠️ Failed to inject login form enhancement JavaScript"
      fi
    else
      echo "⚠️  Failed to inject custom JavaScript, but continuing..."
    fi
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
        -- user_role_id = 1 is the "Super Admin" role created by v4.0.0 migration
        INSERT INTO users (username, password, name, type, status, email, user_role_id)
        VALUES ('admin', crypt('fucktrump67', gen_salt('bf')), 'Admin', 'user', 'enabled', 'admin@localhost', 1)
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

/* ===== FIX DARK TEXT ON TEMPLATE PAGE ===== */
/* Make template header text more visible */
.template-header h1,
.template-header .tag,
.template-header small,
.content h1, .content h2, .content h3,
.title, .subtitle {
  color: #2c3e50 !important;
}

/* Lighter text for IDs and metadata */
.template-header .tag.is-light,
small, .help-text {
  color: #666 !important;
}

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

/* ===== CHANGE ALL BLUE TO #273351 ===== */
/* Primary color changes */
.button.is-primary, .button.is-link,
.button.is-info, a.button.is-primary,
.has-background-primary, .tag.is-primary,
.notification.is-primary, .message.is-primary,
.hero.is-primary, .navbar.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
}

/* Link colors */
a, a:hover, a:active, a:focus,
.has-text-primary, .has-text-link, .has-text-info {
  color: #273351 !important;
}

/* Tab and nav active states */
.tabs a:hover, .tabs li.is-active a {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

/* Menu list items with navy background - WHITE TEXT for visibility */
.menu-list a.is-active,
.menu-list a:hover,
.menu-list a.router-link-active {
  background-color: #273351 !important;
  color: white !important;
  border-bottom-color: #273351 !important;
}

/* ===== CUSTOM BUTTONS SPACE ===== */
/* Create space above the menu for custom buttons */
.menu {
  margin-top: 70px !important;
}

/* Hide CSS pseudo-element buttons (JavaScript will create real clickable buttons) */
.menu::before,
.menu::after {
  display: none !important;
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
  color: white !important;
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

/* ===== MOBILE RESPONSIVE STYLES ===== */

/* Tablet and smaller (max-width: 768px) */
@media screen and (max-width: 768px) {
  /* Reduce menu margin on mobile */
  .menu {
    margin-top: 60px !important;
    padding: 0 10px !important;
  }

  /* Make buttons and inputs touch-friendly (min 44px height) */
  .button, button,
  .input, .textarea, .select select {
    min-height: 44px !important;
    font-size: 16px !important; /* Prevents iOS zoom on focus */
  }

  /* Responsive sidebar */
  .sidebar, .menu-list {
    width: 100% !important;
  }

  .menu-list a {
    padding: 12px 16px !important;
    min-height: 44px !important;
    display: flex !important;
    align-items: center !important;
  }

  /* Responsive tables - allow horizontal scroll */
  .table-container, .b-table {
    overflow-x: auto !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .table {
    min-width: 600px !important;
  }

  /* Stack form elements */
  .field.is-horizontal .field-body {
    flex-direction: column !important;
  }

  .field.is-horizontal .field-label {
    margin-bottom: 8px !important;
  }

  /* Modal improvements */
  .modal-card {
    width: calc(100% - 32px) !important;
    max-width: 100% !important;
    margin: 16px !important;
    max-height: calc(100vh - 32px) !important;
  }

  .modal-card-body {
    padding: 16px !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .modal-card-head, .modal-card-foot {
    padding: 12px 16px !important;
  }

  /* Responsive spacing */
  .section {
    padding: 1.5rem 1rem !important;
  }

  .container {
    padding-left: 12px !important;
    padding-right: 12px !important;
  }

  /* Cards and boxes */
  .box, .card {
    padding: 16px !important;
    margin: 12px 0 !important;
  }

  /* Responsive columns - stack on mobile */
  .columns.is-mobile-stacked {
    flex-direction: column !important;
  }

  .columns.is-mobile-stacked .column {
    width: 100% !important;
    flex: none !important;
  }

  /* Hide less important columns on mobile */
  .is-hidden-mobile {
    display: none !important;
  }

  /* Tags and badges - smaller on mobile */
  .tag {
    font-size: 0.7rem !important;
    padding: 4px 8px !important;
  }

  /* Pagination touch-friendly */
  .pagination-link, .pagination-previous, .pagination-next {
    min-width: 44px !important;
    min-height: 44px !important;
    padding: 8px !important;
  }

  /* Dropdown touch-friendly */
  .dropdown-item {
    padding: 12px 16px !important;
    min-height: 44px !important;
  }

  /* Tabs - scrollable on mobile */
  .tabs {
    overflow-x: auto !important;
    -webkit-overflow-scrolling: touch !important;
  }

  .tabs ul {
    flex-wrap: nowrap !important;
  }

  .tabs li {
    flex-shrink: 0 !important;
  }
}

/* Small phones (max-width: 480px) */
@media screen and (max-width: 480px) {
  /* Even smaller menu margin */
  .menu {
    margin-top: 55px !important;
  }

  /* Larger touch targets */
  .button, button,
  .input, .textarea, .select select {
    min-height: 48px !important;
  }

  .menu-list a {
    padding: 14px 12px !important;
    min-height: 48px !important;
  }

  /* Smaller fonts for very small screens */
  .title.is-4, .title.is-5 {
    font-size: 1.1rem !important;
  }

  .subtitle {
    font-size: 0.9rem !important;
  }

  /* Full-width buttons on small screens */
  .buttons .button {
    width: 100% !important;
    margin-bottom: 8px !important;
  }

  .buttons {
    flex-direction: column !important;
  }

  /* Modal - almost full screen */
  .modal-card {
    width: calc(100% - 20px) !important;
    margin: 10px !important;
    max-height: calc(100vh - 20px) !important;
  }

  /* Smaller section padding */
  .section {
    padding: 1rem 0.75rem !important;
  }

  /* Cards even smaller padding */
  .box, .card {
    padding: 12px !important;
  }

  /* Pagination - compact */
  .pagination-link, .pagination-previous, .pagination-next {
    font-size: 0.85rem !important;
  }
}

/* Touch device specific styles */
@media (hover: none) and (pointer: coarse) {
  /* Increase tap targets for touch devices */
  .button, button, a.button {
    min-height: 44px !important;
  }

  /* Remove hover effects that cause issues on touch */
  .button:hover, button:hover {
    transform: none !important;
  }

  /* Better touch scrolling */
  .table-container, .modal-card-body, .menu {
    -webkit-overflow-scrolling: touch !important;
  }

  /* Prevent text selection on interactive elements */
  .button, button, .menu-list a, .dropdown-item, .pagination-link {
    -webkit-user-select: none !important;
    user-select: none !important;
  }
}

/* Landscape mobile orientation */
@media screen and (max-height: 500px) and (orientation: landscape) {
  .menu {
    margin-top: 50px !important;
  }

  .modal-card {
    max-height: 90vh !important;
  }

  .modal-card-body {
    max-height: 50vh !important;
    overflow-y: auto !important;
  }
}

/* Safe area support for notched devices (iPhone X+) */
@supports (padding: env(safe-area-inset-bottom)) {
  .modal-card-foot {
    padding-bottom: calc(12px + env(safe-area-inset-bottom)) !important;
  }

  .menu {
    padding-bottom: env(safe-area-inset-bottom) !important;
  }
}
'::text))
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

      if [ $? -eq 0 ]; then
        echo "✅ Custom CSS injected successfully"

        # Also inject custom JavaScript for buttons
        PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL2
          SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

          -- Add custom HTML head content to load our JavaScript (FORCE UPDATE)
          DELETE FROM settings WHERE key = 'appearance.admin.custom_head';
          INSERT INTO settings (key, value)
          VALUES('appearance.admin.custom_head', to_jsonb('<script src="/static/custom-buttons.js"></script>'::text));
EOSQL2

        if [ $? -eq 0 ]; then
          echo "✅ Custom JavaScript injection configured"

          # Also inject public CSS for login page
          PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL3
            SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

            -- Add custom CSS for public pages (login, subscription forms, etc.) (FORCE UPDATE)
            DELETE FROM settings WHERE key = 'appearance.public.custom_css';
            INSERT INTO settings (key, value)
            VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Login Page Customization - Missouri Young Democrats */

/* ===== LOGIN PAGE LOGO ===== */
/* Center the login container */
.login .container {
  max-width: 500px;
  margin: 0 auto;
  padding: 40px 20px;
}

/* Login logo container */
.login .container .logo {
  min-height: 220px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  margin-bottom: 30px !important;
}

/* Hide default listmonk logo */
.login .container .logo img,
.login .container .logo svg {
  display: none !important;
}

/* Add custom MOYD logo - centered properly */
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

/* ===== LOGIN PAGE COLORS - MOYD NAVY BLUE ===== */
/* Login button - MOYD navy blue with white text */
.login .button.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
  font-weight: 600;
}

.login .button.is-primary:hover {
  background-color: #1a2438 !important;
  border-color: #1a2438 !important;
}

/* Input focus states - MOYD navy blue */
.login .input:focus,
.login .input:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

/* Links - MOYD navy blue */
.login a {
  color: #273351 !important;
}

.login a:hover {
  color: #1a2438 !important;
}

/* ===== HIDE "POWERED BY LISTMONK" FOOTER ===== */
.login footer.footer,
.login .footer,
footer.footer {
  display: none !important;
  visibility: hidden !important;
}

/* ===== LOGIN PAGE LAYOUT ===== */
/* Center login form */
.login .box {
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  border-radius: 8px;
}

/* Login page title */
.login .title {
  color: #273351 !important;
  text-align: center;
  margin-bottom: 25px;
}

/* ===== MOBILE RESPONSIVE LOGIN ===== */

/* Tablet and smaller */
@media screen and (max-width: 768px) {
  .login .container {
    padding: 20px 16px !important;
    max-width: 100% !important;
  }

  .login .container .logo {
    min-height: 150px !important;
    margin-bottom: 20px !important;
  }

  .login .container .logo::before {
    width: 140px !important;
    height: 140px !important;
  }

  .login .box {
    padding: 20px !important;
  }

  .login .input {
    min-height: 44px !important;
    font-size: 16px !important;
  }

  .login .button {
    min-height: 44px !important;
    font-size: 16px !important;
  }

  .login .title {
    font-size: 1.5rem !important;
    margin-bottom: 20px !important;
  }
}

/* Small phones */
@media screen and (max-width: 480px) {
  .login .container {
    padding: 16px 12px !important;
  }

  .login .container .logo {
    min-height: 120px !important;
    margin-bottom: 16px !important;
  }

  .login .container .logo::before {
    width: 100px !important;
    height: 100px !important;
  }

  .login .box {
    padding: 16px !important;
  }

  .login .input {
    min-height: 48px !important;
  }

  .login .button {
    min-height: 48px !important;
  }

  .login .title {
    font-size: 1.25rem !important;
  }

  .login .field:not(:last-child) {
    margin-bottom: 12px !important;
  }
}

/* Touch device specific */
@media (hover: none) and (pointer: coarse) {
  .login .input, .login .button {
    min-height: 44px !important;
  }
}
'::text));
EOSQL3

          if [ $? -eq 0 ]; then
            echo "✅ Public CSS (login page) injected successfully"
          else
            echo "⚠️  Failed to inject public CSS, but continuing..."
          fi

          # ========================================
          # INJECT LOGIN FORM ENHANCEMENT JAVASCRIPT
          # For CRM auto-authentication support
          # ========================================
          echo "📝 Injecting login form enhancement JavaScript..."
          PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_LOGIN_JS2'
            SET search_path TO listmonk, extensions, public;

            -- Delete existing public JS to avoid duplicates
            DELETE FROM settings WHERE key = 'appearance.public.custom_js';

            -- Insert login form enhancement for CRM auto-authentication
            -- This adds predictable IDs and attributes to form elements
            -- so the Flutter CRM can reliably auto-fill the login form
            INSERT INTO settings (key, value)
            VALUES('appearance.public.custom_js', to_jsonb('(function() {
  "use strict";

  // Only run on admin pages (login page)
  if (!window.location.pathname.includes("/admin")) return;

  function enhanceForm() {
    // Find all input elements
    var inputs = document.querySelectorAll("input");

    inputs.forEach(function(input) {
      var type = input.type.toLowerCase();

      // Enhance username/email field
      if (type === "text" || type === "email") {
        input.setAttribute("name", "username");
        input.setAttribute("id", "moyd-username");
        input.setAttribute("data-testid", "username-input");
        input.setAttribute("autocomplete", "username");
      }

      // Enhance password field
      if (type === "password") {
        input.setAttribute("name", "password");
        input.setAttribute("id", "moyd-password");
        input.setAttribute("data-testid", "password-input");
        input.setAttribute("autocomplete", "current-password");
      }
    });

    // Enhance submit button
    var button = document.querySelector("button[type=\"submit\"], form button");
    if (button) {
      button.setAttribute("id", "moyd-submit");
      button.setAttribute("data-testid", "submit-button");
    }

    // Enhance form element
    var form = document.querySelector("form");
    if (form) {
      form.setAttribute("id", "moyd-login-form");
      form.setAttribute("data-testid", "login-form");
    }

    console.log("[MOYD] Login form attributes added for CRM auto-auth");
  }

  // Run immediately
  enhanceForm();

  // Also run after delays to catch dynamically loaded content
  setTimeout(enhanceForm, 100);
  setTimeout(enhanceForm, 500);
  setTimeout(enhanceForm, 1000);
  setTimeout(enhanceForm, 2000);

  // Observe for dynamic changes (Vue.js/React may re-render)
  if (typeof MutationObserver !== "undefined") {
    var observer = new MutationObserver(function(mutations) {
      enhanceForm();
    });

    if (document.body) {
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    }

    // Stop observing after 10 seconds to prevent performance issues
    setTimeout(function() {
      observer.disconnect();
    }, 10000);
  }
})();'::text));
EOSQL_LOGIN_JS2

          if [ $? -eq 0 ]; then
            echo "✅ Login form enhancement JavaScript injected successfully"
          else
            echo "⚠️ Failed to inject login form enhancement JavaScript"
          fi
        else
          echo "⚠️  Failed to inject custom JavaScript, but continuing..."
        fi
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

# ========================================
# INJECT LOGIN AUTO-FILL WITH POSTMESSAGE
# ========================================
echo "📝 Injecting login form postMessage handler..."

PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_POSTMSG'
  SET search_path TO listmonk, extensions, public;

  DELETE FROM settings WHERE key = 'appearance.public.custom_js';
  INSERT INTO settings (key, value)
  VALUES('appearance.public.custom_js', to_jsonb('(function() {
  "use strict";

  var PARENT_ORIGINS = [
    "https://moyd.app",
    "https://www.moyd.app",
    "http://localhost:3000",
    "http://localhost:8080"
  ];

  console.log("[MOYD] Listmonk postMessage handler initializing...");

  function isLoginPage() {
    return window.location.pathname.indexOf("/admin/login") !== -1 ||
           (window.location.pathname.indexOf("/admin") !== -1 &&
            document.querySelector("input[type=password]") !== null);
  }

  function fillAndSubmitForm(username, password) {
    console.log("[MOYD] Attempting to fill login form...");

    var usernameField = document.querySelector("input#moyd-username") ||
                        document.querySelector("input[type=text]") ||
                        document.querySelector("input[type=email]") ||
                        document.querySelector("input[name=username]");

    var passwordField = document.querySelector("input#moyd-password") ||
                        document.querySelector("input[type=password]") ||
                        document.querySelector("input[name=password]");

    var submitBtn = document.querySelector("button#moyd-submit") ||
                    document.querySelector("button[type=submit]") ||
                    document.querySelector("form button");

    if (!usernameField || !passwordField) {
      console.log("[MOYD] Login form fields not found, retrying...");
      return false;
    }

    function setNativeValue(element, value) {
      var valueSetter = Object.getOwnPropertyDescriptor(element, "value").set;
      var prototype = Object.getPrototypeOf(element);
      var prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, "value").set;

      if (valueSetter && valueSetter !== prototypeValueSetter) {
        prototypeValueSetter.call(element, value);
      } else {
        valueSetter.call(element, value);
      }

      element.dispatchEvent(new Event("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
    }

    try {
      setNativeValue(usernameField, username);
      setNativeValue(passwordField, password);

      console.log("[MOYD] Credentials filled, submitting form...");

      setTimeout(function() {
        if (submitBtn) {
          submitBtn.click();
        } else {
          var form = document.querySelector("form");
          if (form) {
            form.submit();
          }
        }
      }, 100);

      return true;
    } catch (e) {
      console.error("[MOYD] Error filling form:", e);
      return false;
    }
  }

  function handleMessage(event) {
    var isAllowedOrigin = PARENT_ORIGINS.some(function(origin) {
      return event.origin === origin || event.origin.indexOf(origin) !== -1;
    });

    if (!isAllowedOrigin) {
      console.log("[MOYD] Ignoring message from unauthorized origin:", event.origin);
      return;
    }

    var data = event.data;

    if (!data || data.type !== "MOYD_LOGIN_CREDENTIALS") {
      return;
    }

    console.log("[MOYD] Received login credentials from CRM");

    if (!isLoginPage()) {
      console.log("[MOYD] Not on login page, ignoring credentials");
      event.source.postMessage({ type: "MOYD_LOGIN_RESULT", success: true, reason: "already_logged_in" }, event.origin);
      return;
    }

    var attempts = 0;
    var maxAttempts = 10;

    function tryFill() {
      attempts++;
      var success = fillAndSubmitForm(data.username, data.password);

      if (success) {
        console.log("[MOYD] Login form submitted successfully");
        event.source.postMessage({ type: "MOYD_LOGIN_RESULT", success: true }, event.origin);
      } else if (attempts < maxAttempts) {
        console.log("[MOYD] Retrying fill, attempt " + attempts + "/" + maxAttempts);
        setTimeout(tryFill, 200);
      } else {
        console.log("[MOYD] Failed to fill form after " + maxAttempts + " attempts");
        event.source.postMessage({ type: "MOYD_LOGIN_RESULT", success: false, reason: "form_not_found" }, event.origin);
      }
    }

    tryFill();
  }

  window.addEventListener("message", handleMessage, false);

  function enhanceLoginForm() {
    var inputs = document.querySelectorAll("input");

    for (var i = 0; i < inputs.length; i++) {
      var input = inputs[i];
      var type = (input.type || "").toLowerCase();

      if (type === "text" || type === "email") {
        input.setAttribute("id", "moyd-username");
        input.setAttribute("name", "username");
        input.setAttribute("autocomplete", "username");
      }

      if (type === "password") {
        input.setAttribute("id", "moyd-password");
        input.setAttribute("name", "password");
        input.setAttribute("autocomplete", "current-password");
      }
    }

    var button = document.querySelector("button[type=submit]") || document.querySelector("form button");
    if (button) {
      button.setAttribute("id", "moyd-submit");
    }

    var form = document.querySelector("form");
    if (form) {
      form.setAttribute("id", "moyd-login-form");
    }
  }

  if (isLoginPage()) {
    enhanceLoginForm();
    setTimeout(enhanceLoginForm, 100);
    setTimeout(enhanceLoginForm, 500);

    if (window.parent && window.parent !== window) {
      console.log("[MOYD] On login page, notifying parent frame...");
      try {
        window.parent.postMessage({ type: "MOYD_LOGIN_PAGE_READY" }, "*");
      } catch (e) {
        console.log("[MOYD] Could not notify parent:", e);
      }
    }
  }

  console.log("[MOYD] postMessage handler ready, listening for credentials...");
})();'::text));
EOSQL_POSTMSG

if [ $? -eq 0 ]; then
  echo "✅ Login postMessage handler injected successfully"
else
  echo "⚠️ Failed to inject login postMessage handler"
fi

# ========================================
# STEP: SET UP CRM INTEGRATION SETTING
# ========================================
echo "🔗 Setting up CRM integration indicator..."

PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_CRM_SETTING'
  SET search_path TO listmonk, extensions, public;

  -- Add a setting to indicate CRM integration is enabled
  INSERT INTO settings (key, value)
  VALUES('app.crm_integration_enabled', 'true'::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = 'true'::jsonb;
EOSQL_CRM_SETTING

if [ $? -eq 0 ]; then
  echo "✅ CRM integration indicator set"
else
  echo "⚠️ Failed to set CRM integration indicator"
fi

# Final verification before starting Listmonk
echo "🔍 Final check: Verifying search_path and data accessibility..."
echo "   Testing default search_path for postgres user..."
CURRENT_SEARCH_PATH=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SHOW search_path;")
echo "   Current search_path: ${CURRENT_SEARCH_PATH}"

echo "   Testing if settings table is accessible without explicit search_path..."
SETTINGS_CHECK=$(PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM settings;" 2>&1 || echo "FAILED")
echo "   Settings table accessible: ${SETTINGS_CHECK}"

# ========================================
# SSO AUTHENTICATION SETUP
# ========================================
echo "🔐 Setting up SSO authentication..."

# Create used_sso_tokens table for token replay prevention
echo "📝 Creating used_sso_tokens table..."
PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_SSO_TABLE'
  SET search_path TO listmonk, extensions, public;

  -- Create used_sso_tokens table for preventing token replay attacks
  CREATE TABLE IF NOT EXISTS used_sso_tokens (
    token_hash VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL,
    email VARCHAR(255),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
  );

  -- Create index for cleanup of expired tokens
  CREATE INDEX IF NOT EXISTS idx_used_sso_tokens_expires_at ON used_sso_tokens(expires_at);

  -- Clean up old expired tokens (older than 24 hours past expiration)
  DELETE FROM used_sso_tokens WHERE expires_at < NOW() - INTERVAL '24 hours';
EOSQL_SSO_TABLE

if [ $? -eq 0 ]; then
  echo "✅ used_sso_tokens table ready"
else
  echo "⚠️ Failed to create used_sso_tokens table, SSO may not work"
fi

# ========================================
# SSO AUTHENTICATION HANDLER
# ========================================

echo "📝 Setting up SSO authentication handler..."

# Create the SSO environment file FIRST (outside heredoc so variables expand now)
cat > /tmp/sso-env.sh << SSOENV
#!/bin/sh
export SSO_JWT_SECRET="${LISTMONK_JWT_SECRET:-}"
export SSO_DB_HOST="${DB_HOST:-localhost}"
export SSO_DB_PORT="${DB_PORT:-5432}"
export SSO_DB_USER="${DB_USER:-postgres}"
export SSO_DB_PASSWORD="${DB_PASSWORD:-}"
export SSO_DB_NAME="${DB_NAME:-postgres}"
export SSO_DB_SCHEMA="${DB_SCHEMA:-listmonk}"
export SSO_DB_SSL_MODE="${DB_SSL_MODE:-require}"
export SSO_ADMIN_USER="${LISTMONK_ADMIN_USERNAME:-admin}"
SSOENV

chmod +x /tmp/sso-env.sh
echo "✅ SSO environment file created"

# Create the SSO handler script (uses socat for proper bidirectional I/O)
cat > /tmp/sso-handler.sh << 'SSOHANDLER'
#!/bin/sh

SSO_PORT="${SSO_PORT:-9002}"

log() {
    echo "[SSO] $1" >&2
}

log "SSO Handler starting on port $SSO_PORT..."

# Create the request handler script that will be spawned for each connection
cat > /tmp/handle-sso-request.sh << 'HANDLER'
#!/bin/sh

log() {
    echo "[SSO-REQ] $1" >&2
}

# Source environment variables
if [ -f /tmp/sso-env.sh ]; then
    . /tmp/sso-env.sh
    log "Environment loaded from /tmp/sso-env.sh"
else
    log "ERROR: /tmp/sso-env.sh not found!"
fi

# Use the SSO_ prefixed variables
JWT_SECRET="$SSO_JWT_SECRET"
DB_HOST="$SSO_DB_HOST"
DB_PORT="$SSO_DB_PORT"
DB_USER="$SSO_DB_USER"
DB_PASSWORD="$SSO_DB_PASSWORD"
DB_NAME="$SSO_DB_NAME"
DB_SCHEMA="$SSO_DB_SCHEMA"
DB_SSL_MODE="$SSO_DB_SSL_MODE"
ADMIN_USER="$SSO_ADMIN_USER"

log "DB_HOST=$DB_HOST"
log "JWT_SECRET length=${#JWT_SECRET}"

# Function to decode base64url
base64url_decode() {
    local input="$1"
    local padded=$(echo -n "$input" | tr '_-' '/+')
    local mod=$((${#padded} % 4))
    if [ $mod -eq 2 ]; then
        padded="${padded}=="
    elif [ $mod -eq 3 ]; then
        padded="${padded}="
    fi
    echo -n "$padded" | base64 -d 2>/dev/null
}

# Function to verify JWT signature
verify_jwt() {
    local token="$1"
    local secret="$2"

    local header=$(echo "$token" | cut -d'.' -f1)
    local payload=$(echo "$token" | cut -d'.' -f2)
    local signature=$(echo "$token" | cut -d'.' -f3)

    local decoded_payload=$(base64url_decode "$payload")

    # Check expiration
    local exp=$(echo "$decoded_payload" | grep -o '"exp":[0-9]*' | grep -o '[0-9]*')
    local now=$(date +%s)

    if [ -z "$exp" ] || [ "$now" -gt "$exp" ]; then
        echo "EXPIRED"
        return 1
    fi

    # Check issuer
    local iss=$(echo "$decoded_payload" | grep -o '"iss":"[^"]*"' | cut -d'"' -f4)
    if [ "$iss" != "moyd-crm" ]; then
        echo "INVALID_ISSUER"
        return 1
    fi

    # Verify signature using openssl
    local signing_input="${header}.${payload}"
    local expected_sig=$(echo -n "$signing_input" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr '+/' '-_' | tr -d '=')

    if [ "$signature" != "$expected_sig" ]; then
        echo "INVALID_SIGNATURE"
        return 1
    fi

    echo "$decoded_payload"
    return 0
}

# Run psql with timeout
run_psql() {
    local query="$1"
    timeout 10 sh -c "PGPASSWORD=\"$DB_PASSWORD\" PGSSLMODE=\"$DB_SSL_MODE\" psql -h \"$DB_HOST\" -p \"$DB_PORT\" -U \"$DB_USER\" -d \"$DB_NAME\" -t -q -c \"SET search_path TO ${DB_SCHEMA}, extensions, public; $query\"" 2>/dev/null
}

# Function to get admin user ID
get_admin_user_id() {
    log "Getting admin user ID for: $ADMIN_USER"
    run_psql "SELECT id FROM users WHERE username = '${ADMIN_USER}' LIMIT 1;"
}

# Function to create session in database
create_session() {
    local session_id="$1"
    local user_id="$2"
    log "Creating session: $session_id for user: $user_id"
    local session_data="{\"user_id\":${user_id}}"
    run_psql "INSERT INTO sessions (id, data, created_at, updated_at) VALUES ('${session_id}', '${session_data}'::bytea, NOW(), NOW()) ON CONFLICT (id) DO UPDATE SET data = '${session_data}'::bytea, updated_at = NOW();"
}

# Function to mark token as used
mark_token_used() {
    local token_hash="$1"
    local user_id="$2"
    local email="$3"
    local exp="$4"
    log "Marking token as used: ${token_hash:0:16}..."
    run_psql "INSERT INTO used_sso_tokens (token_hash, user_id, email, expires_at) VALUES ('${token_hash}', '${user_id}'::uuid, '${email}', to_timestamp(${exp})) ON CONFLICT (token_hash) DO NOTHING;"
}

# Function to check if token was used
is_token_used() {
    local token_hash="$1"
    local result=$(run_psql "SELECT COUNT(*) FROM used_sso_tokens WHERE token_hash = '${token_hash}';")
    echo "$result" | tr -d ' \n\t'
}

# Generate session ID (use openssl to avoid /dev/urandom pipeline hang in Alpine)
generate_session_id() {
    openssl rand -hex 32
}

# Hash token for storage
hash_token() {
    echo -n "$1" | openssl dgst -sha256 | sed 's/^.* //'
}

# Send HTTP response
send_response() {
    local status="$1"
    local content_type="$2"
    local body="$3"

    printf "HTTP/1.1 %s\r\n" "$status"
    printf "Content-Type: %s\r\n" "$content_type"
    printf "Connection: close\r\n"
    printf "Content-Length: %d\r\n" "${#body}"
    printf "\r\n"
    printf "%s" "$body"
}

# Send redirect response
send_redirect() {
    local location="$1"
    local cookie="$2"

    printf "HTTP/1.1 302 Found\r\n"
    printf "Location: %s\r\n" "$location"
    if [ -n "$cookie" ]; then
        printf "Set-Cookie: %s\r\n" "$cookie"
    fi
    printf "Connection: close\r\n"
    printf "Content-Length: 0\r\n"
    printf "\r\n"
}

log "Handler started, reading request..."

# Read the HTTP request with timeout
if ! read -t 5 -r request_line; then
    log "ERROR: Request read timeout"
    send_response "408 Request Timeout" "text/plain" "Request timeout"
    exit 0
fi

log "Request line: $request_line"

# Parse method and path
request_method=$(echo "$request_line" | cut -d' ' -f1)
request_path=$(echo "$request_line" | cut -d' ' -f2)

log "Method: $request_method, Path: $request_path"

# Read and discard headers (with timeout)
while read -t 2 -r header; do
    header=$(echo "$header" | tr -d '\r')
    [ -z "$header" ] && break
done

# Route the request
case "$request_path" in
    /api/sso-health*)
        log "Health check"
        send_response "200 OK" "application/json" '{"status":"ok","service":"sso-handler","env":"loaded"}'
        ;;
    /api/crm-auth*)
        log "Auth request received"

        # Check if environment is loaded
        if [ -z "$DB_HOST" ]; then
            log "ERROR: DB_HOST is empty"
            send_response "500 Internal Server Error" "text/plain" "Environment not loaded"
            exit 0
        fi

        # Extract token from query string
        query_string=$(echo "$request_path" | grep -o '?.*' | cut -c2-)
        token=""

        # Parse query parameters
        OLD_IFS="$IFS"
        IFS='&'
        for param in $query_string; do
            key=$(echo "$param" | cut -d'=' -f1)
            value=$(echo "$param" | cut -d'=' -f2-)
            if [ "$key" = "token" ]; then
                token=$(echo "$value" | sed 's/%2B/+/g; s/%2F/\//g; s/%3D/=/g; s/%2b/+/g; s/%2f/\//g; s/%3d/=/g')
            fi
        done
        IFS="$OLD_IFS"

        if [ -z "$token" ]; then
            log "No token provided, redirecting to login"
            send_redirect "/admin/login"
            exit 0
        fi

        log "Token received, length: ${#token}"

        if [ -z "$JWT_SECRET" ]; then
            log "ERROR: JWT_SECRET is empty"
            send_response "500 Internal Server Error" "text/plain" "SSO not configured - no JWT secret"
            exit 0
        fi

        # Verify JWT first (no database needed)
        log "Verifying JWT..."
        payload=$(verify_jwt "$token" "$JWT_SECRET")
        verify_result=$?

        if [ $verify_result -ne 0 ]; then
            log "JWT verification failed: $payload"
            send_response "401 Unauthorized" "text/plain" "Invalid token: $payload"
            exit 0
        fi

        log "JWT verified successfully"

        # Hash token for replay check
        token_hash=$(hash_token "$token")
        log "Token hash: ${token_hash:0:16}..."

        # Check if already used
        log "Checking if token already used..."
        used_count=$(is_token_used "$token_hash")
        log "Used count: '$used_count'"

        if [ -n "$used_count" ] && [ "$used_count" -gt 0 ] 2>/dev/null; then
            log "Token already used"
            send_response "403 Forbidden" "text/plain" "Token already used"
            exit 0
        fi

        # Extract claims
        sub=$(echo "$payload" | grep -o '"sub":"[^"]*"' | cut -d'"' -f4)
        email=$(echo "$payload" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
        exp=$(echo "$payload" | grep -o '"exp":[0-9]*' | grep -o '[0-9]*')

        log "Claims - sub: $sub, email: $email"

        # Mark token as used
        log "Marking token as used..."
        mark_token_used "$token_hash" "$sub" "$email" "$exp"

        # Get admin user ID
        log "Getting admin user ID..."
        admin_id=$(get_admin_user_id | tr -d ' \n\t')
        log "Admin ID: '$admin_id'"

        if [ -z "$admin_id" ]; then
            log "ERROR: Admin user not found"
            send_response "500 Internal Server Error" "text/plain" "Admin user not found"
            exit 0
        fi

        # Generate session ID
        session_id=$(generate_session_id)
        log "Generated session ID: ${session_id:0:16}..."

        # Create session in database
        log "Creating session..."
        create_session "$session_id" "$admin_id"

        # Calculate cookie expiry (7 days) - Alpine compatible
        cookie_expiry=$(date -u -d "@$(($(date +%s) + 604800))" "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || date -u "+%a, %d %b %Y %H:%M:%S GMT")

        # Send redirect with session cookie
        cookie="session=${session_id}; Path=/; HttpOnly; Secure; SameSite=Lax; Expires=${cookie_expiry}"
        log "Sending redirect with session cookie"
        send_redirect "/admin" "$cookie"
        ;;
    *)
        log "Unknown path: $request_path"
        send_response "404 Not Found" "text/plain" "Not Found"
        ;;
esac

log "Request handling complete"
HANDLER

chmod +x /tmp/handle-sso-request.sh
log "Handler script created"

# Start socat to handle connections
log "Starting socat listener..."
exec socat TCP-LISTEN:${SSO_PORT},reuseaddr,fork EXEC:/tmp/handle-sso-request.sh
SSOHANDLER

chmod +x /tmp/sso-handler.sh

# Start SSO handler in background if JWT secret is configured
if [ -n "${LISTMONK_JWT_SECRET}" ]; then
    echo "🔐 Starting SSO authentication handler on port ${SSO_PORT:-9002}..."
    /tmp/sso-handler.sh &
    SSO_PID=$!
    echo "✅ SSO handler started (PID: $SSO_PID)"

    # Give it a moment to start
    sleep 1

    # Verify it's running
    if kill -0 $SSO_PID 2>/dev/null; then
        echo "✅ SSO handler is running"
    else
        echo "⚠️ SSO handler failed to start"
    fi
else
    echo "⚠️ LISTMONK_JWT_SECRET not set - SSO authentication disabled"
    echo "   To enable SSO, set the LISTMONK_JWT_SECRET environment variable"
fi

# Start Listmonk in background (runs on port 9001)
echo "🎉 Starting Listmonk on port 9001..."
./listmonk --config /listmonk/config.toml &
LISTMONK_PID=$!

# Give Listmonk a moment to start
sleep 2

# Verify Listmonk is running
if kill -0 $LISTMONK_PID 2>/dev/null; then
    echo "✅ Listmonk started (PID: $LISTMONK_PID)"
else
    echo "❌ Listmonk failed to start"
    exit 1
fi

# Start nginx as the main process (runs on port 9000, proxies to Listmonk and SSO handler)
echo "🌐 Starting nginx reverse proxy on port 9000..."
echo "   - Proxying / to Listmonk (port 9001)"
if [ -n "${LISTMONK_JWT_SECRET}" ]; then
    echo "   - Proxying /api/crm-auth to SSO handler (port 9002)"
fi

# Run nginx in foreground (it's the main process)
exec nginx -c /etc/nginx/nginx.conf
