-- IMMEDIATE BUTTON FIX - Run this in Supabase SQL Editor NOW!
-- This will make the buttons clickable by removing pointer-events: none
--
-- IMPORTANT: After running this SQL, you MUST restart the container for the full fix!
-- The container restart will apply the corrected CSS from the updated entrypoint.sh

SET search_path TO listmonk;

-- Step 1: Fix the admin CSS to remove pointer-events: none from buttons
DELETE FROM settings WHERE key = 'appearance.admin.custom_css';

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

/* ===== CUSTOM BUTTONS ABOVE SIDEBAR MENU (CSS FALLBACK) ===== */
/* Create space above the menu for custom buttons */
.menu {
  margin-top: 70px !important;
}

/* Refresh button using ::before pseudo-element (fallback if JS does not load) */
.menu::before {
  content: "🔄";
  display: block;
  position: fixed;
  top: 15px;
  left: 15px;
  width: 40px;
  height: 40px;
  background-color: #273351;
  border-radius: 8px;
  cursor: pointer;
  color: white;
  font-size: 20px;
  text-align: center;
  line-height: 40px;
  transition: background-color 0.3s ease;
  z-index: 999;
  pointer-events: auto;
}

/* Report problem button using ::after pseudo-element (fallback if JS does not load) */
.menu::after {
  content: "?";
  display: block;
  position: fixed;
  top: 15px;
  left: 65px;
  width: 40px;
  height: 40px;
  background-color: #273351;
  border-radius: 8px;
  cursor: pointer;
  color: white;
  font-size: 24px;
  font-weight: bold;
  text-align: center;
  line-height: 40px;
  transition: background-color 0.3s ease;
  z-index: 999;
  pointer-events: auto;
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
'::text));

-- Step 2: Verify the custom CSS was updated
SELECT key, LEFT(value::text, 100) as value_preview
FROM settings
WHERE key = 'appearance.admin.custom_css';

-- Step 3: Verify JavaScript injection is still set
SELECT key, value
FROM settings
WHERE key = 'appearance.admin.custom_head';

-- Step 4: Verify login page CSS is set
SELECT key, LEFT(value::text, 100) as value_preview
FROM settings
WHERE key = 'appearance.public.custom_css';

-- NEXT STEPS:
-- 1. After running this SQL, HARD REFRESH your browser (Ctrl+Shift+R or Cmd+Shift+R)
-- 2. The buttons should now be clickable!
-- 3. For the full fix with JavaScript functionality, restart the container
