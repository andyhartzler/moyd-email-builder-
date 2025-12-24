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
    -- Admin CSS
    INSERT INTO settings (key, value)
    VALUES('appearance.admin.custom_css', to_jsonb('/* MOYD Admin Branding */

/* Hide Listmonk logo */
.navbar-brand > a:first-child,
.navbar-brand > .navbar-item:first-child,
.navbar-brand a.navbar-item:first-of-type,
.navbar-brand > a[href="/admin"],
.navbar-brand > a[href="/admin/"],
a.navbar-item[href="/admin"],
a.navbar-item[href="/admin/"] {
  display: none !important;
}

/* Hide profile dropdown */
.navbar-end > .navbar-item.has-dropdown,
.navbar-end > .navbar-item > .navbar-link,
.navbar-end > .navbar-item > .navbar-dropdown,
.navbar-item.has-dropdown.is-hoverable,
.navbar-end .dropdown,
.navbar-end > .navbar-item:last-child {
  display: none !important;
}

/* Navbar */
nav.navbar {
  background-color: #ffffff !important;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1) !important;
}

.navbar-burger {
  color: #273351 !important;
}

.navbar-burger span {
  background-color: #273351 !important;
}

/* Mobile menu */
.navbar-menu {
  background-color: #ffffff !important;
}

.navbar-menu .navbar-item {
  color: #273351 !important;
}

.navbar-menu .navbar-item:hover {
  background-color: rgba(39, 51, 81, 0.1) !important;
}

/* Hide footer */
footer.footer {
  display: none !important;
}

.modal-card-foot {
  display: flex !important;
}

/* Navy theme */
.button.is-primary, .button.is-link, .button.is-info, a.button.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

.has-background-primary, .tag.is-primary, .hero.is-primary {
  background-color: #273351 !important;
}

a, .has-text-primary, .has-text-link {
  color: #273351 !important;
}

.tabs li.is-active a {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

.menu-list a.is-active, .menu-list a.router-link-active {
  background-color: #273351 !important;
  color: white !important;
}

.input:focus, .textarea:focus, .select select:focus {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

.pagination-link.is-current {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

.switch input[type="checkbox"]:checked + .check {
  background-color: #273351 !important;
}

.modal-card-head {
  background-color: #273351 !important;
}

.title, .subtitle {
  color: #2c3e50 !important;
}

@media screen and (max-width: 768px) {
  .button, .input, .textarea, .select select {
    min-height: 44px !important;
  }
  .menu-list a {
    padding: 12px 16px !important;
    min-height: 44px !important;
  }
}
'::text))
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

  if [ $? -eq 0 ]; then
    echo "✅ Custom CSS injected successfully"

    # Inject custom JavaScript for navbar buttons
    # NOTE: Using custom_js (NOT custom_head) - Listmonk serves this as /admin/custom.js
    # NOTE: No <script> tags needed - it's served as a raw JS file
    # NOTE: Avoiding all single quotes to prevent shell escaping issues in heredoc
    echo "💻 Injecting custom JavaScript for buttons..."
    PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL2'
      SET search_path TO listmonk, extensions, public;

      -- Remove any old/broken settings
      DELETE FROM settings WHERE key = 'appearance.admin.custom_js';
      DELETE FROM settings WHERE key = 'appearance.admin.custom_head';

      -- Admin JavaScript (buttons + title fix + logout remover)
      INSERT INTO settings (key, value)
      VALUES('appearance.admin.custom_js', to_jsonb('(function(){
  console.log("[MOYD] Loading customizations...");
  var NAVY="#273351",NAVY_DARK="#1a2438";

  function fixTitle(){
    if(document.title.indexOf("listmonk")===0){
      document.title=document.title.replace("listmonk","MOYD");
    }
  }

  function removeLogout(){
    var links=document.querySelectorAll("a");
    for(var i=0;i<links.length;i++){
      var href=links[i].getAttribute("href")||"";
      var text=(links[i].textContent||"").toLowerCase().trim();
      if(href.indexOf("logout")>-1||text==="logout"){
        links[i].style.display="none";
        links[i].parentNode.removeChild(links[i]);
        console.log("[MOYD] Removed logout link");
      }
    }
  }

  function createButtons(){
    if(document.getElementById("moyd-btns"))return;
    var d=document.createElement("div");
    d.id="moyd-btns";
    d.style.cssText="position:fixed;top:10px;left:10px;z-index:99999;display:flex;gap:8px;";
    var r=document.createElement("button");
    r.innerHTML="🔄";r.title="Refresh";
    r.style.cssText="width:40px;height:40px;background:"+NAVY+";border:none;border-radius:8px;color:white;font-size:18px;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,0.15);";
    r.onmouseover=function(){this.style.background=NAVY_DARK};
    r.onmouseout=function(){this.style.background=NAVY};
    r.onclick=function(){this.style.transform="rotate(360deg)";setTimeout(function(){location.reload()},300)};
    var h=document.createElement("button");
    h.innerHTML="?";h.title="Help";
    h.style.cssText="width:40px;height:40px;background:"+NAVY+";border:none;border-radius:8px;color:white;font-size:20px;font-weight:bold;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,0.15);";
    h.onmouseover=function(){this.style.background=NAVY_DARK};
    h.onmouseout=function(){this.style.background=NAVY};
    h.onclick=function(){showHelp()};
    d.appendChild(r);d.appendChild(h);document.body.appendChild(d);
    console.log("[MOYD] Buttons created!");
  }

  function showHelp(){
    var e=document.getElementById("moyd-modal");if(e)e.remove();
    var m="Hey Andrew! I need help with the Campaigns page...";
    var o=document.createElement("div");o.id="moyd-modal";
    o.style.cssText="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:999999;padding:20px;";
    var c=document.createElement("div");
    c.style.cssText="background:white;border-radius:16px;padding:24px;max-width:340px;width:100%;text-align:center;";
    var t=document.createElement("h2");t.style.cssText="margin:0 0 6px;color:#273351;font-size:18px;";t.textContent="Having trouble with the email campaign system?";
    var sub=document.createElement("p");sub.style.cssText="margin:0 0 20px;color:#273351;font-size:16px;font-weight:600;";sub.textContent="Get help now!";
    var b=document.createElement("div");b.style.cssText="display:flex;gap:12px;margin-bottom:16px;";
    var s=document.createElement("a");s.href="sms:+18168983612?body="+encodeURIComponent(m);
    s.style.cssText="flex:1;padding:16px 12px;background:#273351;color:white;text-decoration:none;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;";
    s.innerHTML="<span style=\"font-size:24px\">💬</span><span style=\"font-weight:bold;font-size:14px\">Text</span>";
    var em=document.createElement("a");em.href="mailto:andrew@moyoungdemocrats.org?subject=Help&body="+encodeURIComponent(m);
    em.style.cssText="flex:1;padding:16px 12px;background:#273351;color:white;text-decoration:none;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;";
    em.innerHTML="<span style=\"font-size:24px\">✉️</span><span style=\"font-weight:bold;font-size:14px\">Email</span>";
    var cl=document.createElement("button");cl.textContent="Close";
    cl.style.cssText="width:100%;padding:12px;background:#e5e5e5;border:none;border-radius:8px;cursor:pointer;font-size:14px;";
    cl.onclick=function(){o.remove()};
    b.appendChild(s);b.appendChild(em);c.appendChild(t);c.appendChild(sub);c.appendChild(b);c.appendChild(cl);o.appendChild(c);
    o.onclick=function(ev){if(ev.target===o)o.remove()};
    document.body.appendChild(o);
  }

  function init(){
    fixTitle();
    removeLogout();
    createButtons();
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded",init);
  }else{
    init();
  }

  setTimeout(init,500);
  setTimeout(init,1000);
  setTimeout(init,2000);

  setInterval(function(){
    fixTitle();
    removeLogout();
    if(!document.getElementById("moyd-btns"))createButtons();
  },2000);

  window.MOYD_showHelp=showHelp;
})();'::text))
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL2

    if [ $? -eq 0 ]; then
      echo "✅ Custom JavaScript injected successfully (via custom_js)"

      # Also inject public CSS for login page
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL3
        SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

        -- Add custom CSS for public pages (login, subscription forms, etc.) (FORCE UPDATE)
        DELETE FROM settings WHERE key = 'appearance.public.custom_css';
        INSERT INTO settings (key, value)
        -- Public CSS (login pages)
        VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Public Pages */

/* Center the logo */
.logo,
.wrap .logo,
div.logo {
  text-align: center !important;
  display: flex !important;
  justify-content: center !important;
  align-items: center !important;
  margin-bottom: 20px !important;
}

.logo a,
.wrap .logo a {
  display: inline-block !important;
  margin: 0 auto !important;
}

.logo img,
.wrap .logo img,
.logo a img {
  max-width: 200px !important;
  height: auto !important;
  margin: 0 auto !important;
}

/* Login container */
.wrap {
  max-width: 400px !important;
  margin: 0 auto !important;
  padding: 20px !important;
}

.box {
  border-radius: 12px !important;
  box-shadow: 0 4px 20px rgba(0,0,0,0.1) !important;
  padding: 24px !important;
}

/* Form inputs */
.input,
input[type="text"],
input[type="password"],
input[type="email"] {
  border-radius: 8px !important;
  min-height: 44px !important;
}

.input:focus,
input:focus {
  border-color: #273351 !important;
  box-shadow: 0 0 0 3px rgba(39, 51, 81, 0.15) !important;
}

/* NAVY BLUE BUTTON - MAXIMUM SPECIFICITY */
.button,
.button.is-primary,
.button.is-link,
.button.is-info,
button,
button.button,
button.is-primary,
input[type="submit"],
input.button,
a.button,
a.button.is-primary,
.box .button,
.box button,
.wrap .button,
.wrap button,
form .button,
form button,
form input[type="submit"],
.field .button,
.control .button,
.control button {
  background-color: #273351 !important;
  background: #273351 !important;
  border-color: #273351 !important;
  border: 1px solid #273351 !important;
  color: #ffffff !important;
  border-radius: 8px !important;
  min-height: 44px !important;
  font-weight: 600 !important;
}

.button:hover,
.button.is-primary:hover,
button:hover,
input[type="submit"]:hover,
a.button:hover,
.box .button:hover,
.wrap .button:hover,
form .button:hover,
form button:hover {
  background-color: #1a2438 !important;
  background: #1a2438 !important;
  border-color: #1a2438 !important;
  border: 1px solid #1a2438 !important;
  color: #ffffff !important;
}

/* Links */
a {
  color: #273351 !important;
}

/* Hide footer */
footer.footer,
footer,
.footer {
  display: none !important;
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

      # Set site name and favicon
      echo "🏷️ Setting site name and favicon..."
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_BRANDING'
        SET search_path TO listmonk, extensions, public;

        -- Set site name to MOYD (appears in browser tab)
        INSERT INTO settings (key, value)
        VALUES ('app.site_name', '"MOYD"'::jsonb)
        ON CONFLICT (key) DO UPDATE SET value = '"MOYD"'::jsonb;

        -- Set custom favicon URL
        INSERT INTO settings (key, value)
        VALUES ('app.favicon_url', '"/uploads/favicon.png"'::jsonb)
        ON CONFLICT (key) DO UPDATE SET value = '"/uploads/favicon.png"'::jsonb;
EOSQL_BRANDING

      if [ $? -eq 0 ]; then
        echo "✅ Site name and favicon configured"
      else
        echo "⚠️ Failed to set site name/favicon"
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

        -- Admin CSS
        INSERT INTO settings (key, value)
        VALUES('appearance.admin.custom_css', to_jsonb('/* MOYD Admin Branding */

/* Hide Listmonk logo */
.navbar-brand > a:first-child,
.navbar-brand > .navbar-item:first-child,
.navbar-brand a.navbar-item:first-of-type,
.navbar-brand > a[href="/admin"],
.navbar-brand > a[href="/admin/"],
a.navbar-item[href="/admin"],
a.navbar-item[href="/admin/"] {
  display: none !important;
}

/* Hide profile dropdown */
.navbar-end > .navbar-item.has-dropdown,
.navbar-end > .navbar-item > .navbar-link,
.navbar-end > .navbar-item > .navbar-dropdown,
.navbar-item.has-dropdown.is-hoverable,
.navbar-end .dropdown,
.navbar-end > .navbar-item:last-child {
  display: none !important;
}

/* Navbar */
nav.navbar {
  background-color: #ffffff !important;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1) !important;
}

.navbar-burger {
  color: #273351 !important;
}

.navbar-burger span {
  background-color: #273351 !important;
}

/* Mobile menu */
.navbar-menu {
  background-color: #ffffff !important;
}

.navbar-menu .navbar-item {
  color: #273351 !important;
}

.navbar-menu .navbar-item:hover {
  background-color: rgba(39, 51, 81, 0.1) !important;
}

/* Hide footer */
footer.footer {
  display: none !important;
}

.modal-card-foot {
  display: flex !important;
}

/* Navy theme */
.button.is-primary, .button.is-link, .button.is-info, a.button.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

.has-background-primary, .tag.is-primary, .hero.is-primary {
  background-color: #273351 !important;
}

a, .has-text-primary, .has-text-link {
  color: #273351 !important;
}

.tabs li.is-active a {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

.menu-list a.is-active, .menu-list a.router-link-active {
  background-color: #273351 !important;
  color: white !important;
}

.input:focus, .textarea:focus, .select select:focus {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

.pagination-link.is-current {
  background-color: #273351 !important;
  border-color: #273351 !important;
}

.switch input[type="checkbox"]:checked + .check {
  background-color: #273351 !important;
}

.modal-card-head {
  background-color: #273351 !important;
}

.title, .subtitle {
  color: #2c3e50 !important;
}

@media screen and (max-width: 768px) {
  .button, .input, .textarea, .select select {
    min-height: 44px !important;
  }
  .menu-list a {
    padding: 12px 16px !important;
    min-height: 44px !important;
  }
}
'::text))
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL

      if [ $? -eq 0 ]; then
        echo "✅ Custom CSS injected successfully"

        # Inject custom JavaScript for navbar buttons
        # NOTE: Using custom_js (NOT custom_head) - Listmonk serves this as /admin/custom.js
        # NOTE: No <script> tags needed - it's served as a raw JS file
        # NOTE: Avoiding all single quotes to prevent shell escaping issues in heredoc
        echo "💻 Injecting custom JavaScript for buttons..."
        PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL2'
          SET search_path TO listmonk, extensions, public;

          -- Remove any old/broken settings
          DELETE FROM settings WHERE key = 'appearance.admin.custom_js';
          DELETE FROM settings WHERE key = 'appearance.admin.custom_head';

          -- Admin JavaScript (buttons + title fix + logout remover)
          INSERT INTO settings (key, value)
          VALUES('appearance.admin.custom_js', to_jsonb('(function(){
  console.log("[MOYD] Loading customizations...");
  var NAVY="#273351",NAVY_DARK="#1a2438";

  function fixTitle(){
    if(document.title.indexOf("listmonk")===0){
      document.title=document.title.replace("listmonk","MOYD");
    }
  }

  function removeLogout(){
    var links=document.querySelectorAll("a");
    for(var i=0;i<links.length;i++){
      var href=links[i].getAttribute("href")||"";
      var text=(links[i].textContent||"").toLowerCase().trim();
      if(href.indexOf("logout")>-1||text==="logout"){
        links[i].style.display="none";
        links[i].parentNode.removeChild(links[i]);
        console.log("[MOYD] Removed logout link");
      }
    }
  }

  function createButtons(){
    if(document.getElementById("moyd-btns"))return;
    var d=document.createElement("div");
    d.id="moyd-btns";
    d.style.cssText="position:fixed;top:10px;left:10px;z-index:99999;display:flex;gap:8px;";
    var r=document.createElement("button");
    r.innerHTML="🔄";r.title="Refresh";
    r.style.cssText="width:40px;height:40px;background:"+NAVY+";border:none;border-radius:8px;color:white;font-size:18px;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,0.15);";
    r.onmouseover=function(){this.style.background=NAVY_DARK};
    r.onmouseout=function(){this.style.background=NAVY};
    r.onclick=function(){this.style.transform="rotate(360deg)";setTimeout(function(){location.reload()},300)};
    var h=document.createElement("button");
    h.innerHTML="?";h.title="Help";
    h.style.cssText="width:40px;height:40px;background:"+NAVY+";border:none;border-radius:8px;color:white;font-size:20px;font-weight:bold;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,0.15);";
    h.onmouseover=function(){this.style.background=NAVY_DARK};
    h.onmouseout=function(){this.style.background=NAVY};
    h.onclick=function(){showHelp()};
    d.appendChild(r);d.appendChild(h);document.body.appendChild(d);
    console.log("[MOYD] Buttons created!");
  }

  function showHelp(){
    var e=document.getElementById("moyd-modal");if(e)e.remove();
    var m="Hey Andrew! I need help with the Campaigns page...";
    var o=document.createElement("div");o.id="moyd-modal";
    o.style.cssText="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:999999;padding:20px;";
    var c=document.createElement("div");
    c.style.cssText="background:white;border-radius:16px;padding:24px;max-width:340px;width:100%;text-align:center;";
    var t=document.createElement("h2");t.style.cssText="margin:0 0 6px;color:#273351;font-size:18px;";t.textContent="Having trouble with the email campaign system?";
    var sub=document.createElement("p");sub.style.cssText="margin:0 0 20px;color:#273351;font-size:16px;font-weight:600;";sub.textContent="Get help now!";
    var b=document.createElement("div");b.style.cssText="display:flex;gap:12px;margin-bottom:16px;";
    var s=document.createElement("a");s.href="sms:+18168983612?body="+encodeURIComponent(m);
    s.style.cssText="flex:1;padding:16px 12px;background:#273351;color:white;text-decoration:none;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;";
    s.innerHTML="<span style=\"font-size:24px\">💬</span><span style=\"font-weight:bold;font-size:14px\">Text</span>";
    var em=document.createElement("a");em.href="mailto:andrew@moyoungdemocrats.org?subject=Help&body="+encodeURIComponent(m);
    em.style.cssText="flex:1;padding:16px 12px;background:#273351;color:white;text-decoration:none;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;";
    em.innerHTML="<span style=\"font-size:24px\">✉️</span><span style=\"font-weight:bold;font-size:14px\">Email</span>";
    var cl=document.createElement("button");cl.textContent="Close";
    cl.style.cssText="width:100%;padding:12px;background:#e5e5e5;border:none;border-radius:8px;cursor:pointer;font-size:14px;";
    cl.onclick=function(){o.remove()};
    b.appendChild(s);b.appendChild(em);c.appendChild(t);c.appendChild(sub);c.appendChild(b);c.appendChild(cl);o.appendChild(c);
    o.onclick=function(ev){if(ev.target===o)o.remove()};
    document.body.appendChild(o);
  }

  function init(){
    fixTitle();
    removeLogout();
    createButtons();
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded",init);
  }else{
    init();
  }

  setTimeout(init,500);
  setTimeout(init,1000);
  setTimeout(init,2000);

  setInterval(function(){
    fixTitle();
    removeLogout();
    if(!document.getElementById("moyd-btns"))createButtons();
  },2000);

  window.MOYD_showHelp=showHelp;
})();'::text))
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
EOSQL2

        if [ $? -eq 0 ]; then
          echo "✅ Custom JavaScript injected successfully (via custom_js)"

          # Also inject public CSS for login page
          PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<-EOSQL3
            SET search_path TO ${DB_SCHEMA:-listmonk}, extensions, public;

            -- Add custom CSS for public pages (login, subscription forms, etc.) (FORCE UPDATE)
            DELETE FROM settings WHERE key = 'appearance.public.custom_css';
            INSERT INTO settings (key, value)
            -- Public CSS (login pages)
        VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Public Pages */

/* Center the logo */
.logo,
.wrap .logo,
div.logo {
  text-align: center !important;
  display: flex !important;
  justify-content: center !important;
  align-items: center !important;
  margin-bottom: 20px !important;
}

.logo a,
.wrap .logo a {
  display: inline-block !important;
  margin: 0 auto !important;
}

.logo img,
.wrap .logo img,
.logo a img {
  max-width: 200px !important;
  height: auto !important;
  margin: 0 auto !important;
}

/* Login container */
.wrap {
  max-width: 400px !important;
  margin: 0 auto !important;
  padding: 20px !important;
}

.box {
  border-radius: 12px !important;
  box-shadow: 0 4px 20px rgba(0,0,0,0.1) !important;
  padding: 24px !important;
}

/* Form inputs */
.input,
input[type="text"],
input[type="password"],
input[type="email"] {
  border-radius: 8px !important;
  min-height: 44px !important;
}

.input:focus,
input:focus {
  border-color: #273351 !important;
  box-shadow: 0 0 0 3px rgba(39, 51, 81, 0.15) !important;
}

/* NAVY BLUE BUTTON - MAXIMUM SPECIFICITY */
.button,
.button.is-primary,
.button.is-link,
.button.is-info,
button,
button.button,
button.is-primary,
input[type="submit"],
input.button,
a.button,
a.button.is-primary,
.box .button,
.box button,
.wrap .button,
.wrap button,
form .button,
form button,
form input[type="submit"],
.field .button,
.control .button,
.control button {
  background-color: #273351 !important;
  background: #273351 !important;
  border-color: #273351 !important;
  border: 1px solid #273351 !important;
  color: #ffffff !important;
  border-radius: 8px !important;
  min-height: 44px !important;
  font-weight: 600 !important;
}

.button:hover,
.button.is-primary:hover,
button:hover,
input[type="submit"]:hover,
a.button:hover,
.box .button:hover,
.wrap .button:hover,
form .button:hover,
form button:hover {
  background-color: #1a2438 !important;
  background: #1a2438 !important;
  border-color: #1a2438 !important;
  border: 1px solid #1a2438 !important;
  color: #ffffff !important;
}

/* Links */
a {
  color: #273351 !important;
}

/* Hide footer */
footer.footer,
footer,
.footer {
  display: none !important;
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

          # Set site name and favicon
          echo "🏷️ Setting site name and favicon..."
          PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${DB_SSL_MODE:-require}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" <<-'EOSQL_BRANDING2'
            SET search_path TO listmonk, extensions, public;

            -- Set site name to MOYD (appears in browser tab)
            INSERT INTO settings (key, value)
            VALUES ('app.site_name', '"MOYD"'::jsonb)
            ON CONFLICT (key) DO UPDATE SET value = '"MOYD"'::jsonb;

            -- Set custom favicon URL
            INSERT INTO settings (key, value)
            VALUES ('app.favicon_url', '"/uploads/favicon.png"'::jsonb)
            ON CONFLICT (key) DO UPDATE SET value = '"/uploads/favicon.png"'::jsonb;
EOSQL_BRANDING2

          if [ $? -eq 0 ]; then
            echo "✅ Site name and favicon configured"
          else
            echo "⚠️ Failed to set site name/favicon"
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
      try {
        var prototype = Object.getPrototypeOf(element);
        if (prototype) {
          var prototypeDescriptor = Object.getOwnPropertyDescriptor(prototype, "value");
          if (prototypeDescriptor && typeof prototypeDescriptor.set === "function") {
            prototypeDescriptor.set.call(element, value);
          } else {
            element.value = value;
          }
        } else {
          element.value = value;
        }
      } catch (e) {
        console.log("[MOYD] Using fallback value setter");
        element.value = value;
      }

      element.dispatchEvent(new Event("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
      element.dispatchEvent(new Event("focus", { bubbles: true }));
      element.dispatchEvent(new Event("blur", { bubbles: true }));
    }

    try {
      console.log("[MOYD] Setting username field...");
      setNativeValue(usernameField, username);

      console.log("[MOYD] Setting password field...");
      setNativeValue(passwordField, password);

      console.log("[MOYD] Credentials filled, submitting form...");

      setTimeout(function() {
        if (submitBtn) {
          console.log("[MOYD] Clicking submit button...");
          submitBtn.click();
        } else {
          var form = document.querySelector("form");
          if (form) {
            console.log("[MOYD] Submitting form directly...");
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

  function notifyDashboardLoaded() {
    if (!isLoginPage() && window.location.pathname.indexOf("/admin") !== -1) {
      console.log("[MOYD] Dashboard loaded, notifying parent frame...");
      if (window.parent && window.parent !== window) {
        try {
          window.parent.postMessage({ type: "MOYD_DASHBOARD_READY" }, "*");
        } catch (e) {
          console.log("[MOYD] Could not notify parent:", e);
        }
      }
    }
  }

  if (document.readyState === "complete") {
    notifyDashboardLoaded();
  } else {
    window.addEventListener("load", notifyDashboardLoaded);
  }

  setTimeout(notifyDashboardLoaded, 1000);
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
        # Cookie name must be exactly "listmonk_sso" - nginx map looks for this
        cookie="listmonk_sso=${session_id}; Path=/; HttpOnly; Secure; SameSite=None; Max-Age=86400"
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

# ========================================
# COPY FAVICON TO UPLOADS
# ========================================
echo "🎨 Setting up custom favicon..."
if [ -f /listmonk/static/favicon.png ]; then
  cp /listmonk/static/favicon.png /listmonk/uploads/favicon.png
  echo "✅ Favicon copied to uploads"
else
  echo "⚠️ Favicon not found at /listmonk/static/favicon.png"
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

# ===== NGINX CONFIGURATION WITH BASICAUTH INJECTION =====
echo "🌐 Configuring nginx with SSO BasicAuth injection..."

# Calculate BasicAuth base64 value from admin credentials
# This will be injected when listmonk_sso cookie is present
LISTMONK_ADMIN_PASSWORD="${LISTMONK_ADMIN_PASSWORD:-fucktrump67}"
BASIC_AUTH_B64=$(echo -n "admin:${LISTMONK_ADMIN_PASSWORD}" | base64 | tr -d '\n')
echo "   BasicAuth configured for user: admin"

# Generate nginx config with cookie→BasicAuth map
cat > /etc/nginx/nginx.conf << NGINXCONF
# Nginx configuration for Listmonk SSO proxy
# Routes /api/crm-auth to SSO handler, injects BasicAuth when SSO cookie present

daemon off;
worker_processes 1;
error_log /dev/stderr warn;
pid /run/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /dev/stdout;

    sendfile on;
    keepalive_timeout 65;

    # Upstream for Listmonk (running on port 9001)
    upstream listmonk {
        server 127.0.0.1:9001;
    }

    # Upstream for SSO handler (running on port 9002)
    upstream sso_handler {
        server 127.0.0.1:9002;
    }

    # Map: if listmonk_sso cookie exists, inject BasicAuth header
    # This allows SSO-authenticated users to access Listmonk admin
    map \$cookie_listmonk_sso \$listmonk_auth {
        ""      "";
        default "Basic ${BASIC_AUTH_B64}";
    }

    server {
        listen 9000;
        server_name _;

        # Health check endpoint - proxy to Listmonk (no auth needed)
        location = /api/health {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # SSO authentication endpoint - proxy to SSO handler
        location = /api/crm-auth {
            proxy_pass http://sso_handler;
            proxy_http_version 1.0;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 120s;
        }

        # SSO health check endpoint
        location = /api/sso-health {
            proxy_pass http://sso_handler;
            proxy_http_version 1.0;
        }

        # Admin routes - inject BasicAuth if SSO cookie present
        location /admin {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Authorization \$listmonk_auth;

            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # API routes - inject BasicAuth if SSO cookie present
        location /api/ {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Authorization \$listmonk_auth;
        }

        # Public routes - no auth injection needed
        location /public/ {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
        }

        location /subscription/ {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
        }

        # Static files
        location /uploads {
            alias /listmonk/uploads;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }

        location /static {
            alias /listmonk/static;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }

        # All other requests go to Listmonk
        location / {
            proxy_pass http://listmonk;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            # WebSocket support (if needed)
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";

            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
}
NGINXCONF

echo "✅ Nginx configured with SSO BasicAuth injection"

# Start nginx as the main process (runs on port 9000, proxies to Listmonk and SSO handler)
echo "🌐 Starting nginx reverse proxy on port 9000..."
echo "   - Proxying / to Listmonk (port 9001)"
if [ -n "${LISTMONK_JWT_SECRET}" ]; then
    echo "   - Proxying /api/crm-auth to SSO handler (port 9002)"
    echo "   - Injecting BasicAuth when listmonk_sso cookie present"
fi

# Run nginx in foreground (it's the main process)
exec nginx -c /etc/nginx/nginx.conf
