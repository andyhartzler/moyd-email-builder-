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

  function init() {
    var menu = document.querySelector(".menu");
    if (!menu) {
      setTimeout(init, 500);
      return;
    }

    var existing = document.getElementById("moyd-custom-buttons");
    if (existing) existing.remove();

    var buttonsContainer = document.createElement("div");
    buttonsContainer.id = "moyd-custom-buttons";
    buttonsContainer.style.cssText = "position: fixed; top: 15px; left: 15px; z-index: 1000; display: flex; gap: 10px;";

    var refreshBtn = document.createElement("button");
    refreshBtn.innerHTML = "🔄";
    refreshBtn.title = "Refresh Page";
    refreshBtn.style.cssText = "width: 40px; height: 40px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: 20px; cursor: pointer; transition: all 0.3s ease;";
    refreshBtn.onmouseover = function() { this.style.transform = "rotate(180deg)"; this.style.backgroundColor = "#1a2438"; };
    refreshBtn.onmouseout = function() { this.style.transform = "rotate(0deg)"; this.style.backgroundColor = "#273351"; };
    refreshBtn.onclick = function() { location.reload(); };

    var reportBtn = document.createElement("button");
    reportBtn.innerHTML = "?";
    reportBtn.title = "Report a Problem";
    reportBtn.style.cssText = "width: 40px; height: 40px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: 24px; font-weight: bold; cursor: pointer; transition: background-color 0.3s ease;";
    reportBtn.onmouseover = function() { this.style.backgroundColor = "#1a2438"; };
    reportBtn.onmouseout = function() { this.style.backgroundColor = "#273351"; };
    reportBtn.onclick = showReportModal;

    buttonsContainer.appendChild(refreshBtn);
    buttonsContainer.appendChild(reportBtn);
    document.body.appendChild(buttonsContainer);
    menu.style.marginTop = "20px";
    console.log("[MOYD] Admin buttons loaded");
  }

  function showReportModal() {
    var existing = document.getElementById("moyd-report-modal");
    if (existing) existing.remove();

    var modal = document.createElement("div");
    modal.id = "moyd-report-modal";
    modal.style.cssText = "position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 10000;";

    var modalContent = document.createElement("div");
    modalContent.style.cssText = "background: white; padding: 30px; border-radius: 12px; max-width: 500px; box-shadow: 0 4px 20px rgba(0,0,0,0.3);";
    modalContent.innerHTML = "<h2 style=\"margin: 0 0 10px 0; color: #273351; font-size: 24px;\">Report a Problem</h2><p style=\"margin: 0 0 25px 0; color: #666; font-size: 14px;\">Having an issue? Contact Andrew directly via text message or email.</p><div style=\"display: flex; gap: 15px; margin-bottom: 20px;\"><a href=\"sms:+18168983612\" style=\"flex: 1; display: flex; flex-direction: column; align-items: center; padding: 20px; background: #273351; color: white; text-decoration: none; border-radius: 8px;\"><span style=\"font-size: 32px; margin-bottom: 10px;\">💬</span><span style=\"font-size: 16px; font-weight: bold;\">Send Text</span><span style=\"font-size: 12px; margin-top: 5px; opacity: 0.9;\">816-898-3612</span></a><a href=\"mailto:andrew@moyoungdemocrats.org?subject=MOYD%20App%20Issue\" style=\"flex: 1; display: flex; flex-direction: column; align-items: center; padding: 20px; background: #273351; color: white; text-decoration: none; border-radius: 8px;\"><span style=\"font-size: 32px; margin-bottom: 10px;\">✉️</span><span style=\"font-size: 16px; font-weight: bold;\">Send Email</span><span style=\"font-size: 12px; margin-top: 5px; opacity: 0.9;\">andrew@moyoungdemocrats.org</span></a></div><button onclick=\"document.getElementById(\\\"moyd-report-modal\\\").remove();\" style=\"width: 100%; padding: 12px; background: #e0e0e0; border: none; border-radius: 8px; color: #333; font-size: 14px; cursor: pointer;\">Close</button>";

    modal.appendChild(modalContent);
    modal.onclick = function(e) {
      if (e.target === modal) modal.remove();
    };

    document.body.appendChild(modal);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
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
# STEP: ENHANCE LOGIN FORM FOR CRM AUTO-AUTH
# ========================================
echo "🔐 Configuring login form for CRM auto-authentication..."

PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_CRM_AUTH'
  SET search_path TO listmonk, extensions, public;

  -- Delete any existing public JS
  DELETE FROM settings WHERE key = 'appearance.public.custom_js';

  -- Insert login form enhancement JavaScript
  INSERT INTO settings (key, value)
  VALUES('appearance.public.custom_js', to_jsonb('(function() {
  "use strict";

  // Only run on login page
  if (window.location.pathname.indexOf("/admin") === -1) return;

  function enhanceForm() {
    // Add predictable attributes to form elements
    var inputs = document.querySelectorAll("input");
    for (var i = 0; i < inputs.length; i++) {
      var input = inputs[i];
      var type = (input.type || "").toLowerCase();
      if (type === "text" || type === "email") {
        input.setAttribute("name", "username");
        input.setAttribute("id", "moyd-username");
        input.setAttribute("data-testid", "username-input");
        input.setAttribute("autocomplete", "username");
        input.setAttribute("data-moyd-field", "username");
      }
      if (type === "password") {
        input.setAttribute("name", "password");
        input.setAttribute("id", "moyd-password");
        input.setAttribute("data-testid", "password-input");
        input.setAttribute("autocomplete", "current-password");
        input.setAttribute("data-moyd-field", "password");
      }
    }

    var button = document.querySelector("button[type=\"submit\"]") || document.querySelector("form button");
    if (button) {
      button.setAttribute("id", "moyd-submit");
      button.setAttribute("data-testid", "submit-button");
      button.setAttribute("data-moyd-field", "submit");
    }

    // Add form ID
    var form = document.querySelector("form");
    if (form) {
      form.setAttribute("id", "moyd-login-form");
      form.setAttribute("data-testid", "login-form");
    }

    console.log("[MOYD] Login form attributes added");
  }

  // Run immediately and after delays
  enhanceForm();
  setTimeout(enhanceForm, 100);
  setTimeout(enhanceForm, 500);
  setTimeout(enhanceForm, 1000);
  setTimeout(enhanceForm, 2000);

  // Also observe for dynamic changes
  if (typeof MutationObserver !== "undefined") {
    var observer = new MutationObserver(enhanceForm);
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
    }
    // Stop observing after 10 seconds
    setTimeout(function() { observer.disconnect(); }, 10000);
  }
})();'::text));

EOSQL_CRM_AUTH

if [ $? -eq 0 ]; then
  echo "✅ Login form enhancement configured"
else
  echo "⚠️ Failed to configure login form enhancement"
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

# Start Listmonk
echo "🎉 Starting Listmonk..."
exec ./listmonk --config /listmonk/config.toml
