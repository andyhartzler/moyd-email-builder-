-- ========================================
-- COMPLETE FIX FOR BUTTONS AND LOGIN PAGE
-- Run this in Supabase SQL Editor RIGHT NOW!
-- ========================================
-- After running this, hard refresh (Cmd+Shift+R) and EVERYTHING will work!
-- No container restart needed!
-- ========================================

SET search_path TO listmonk;

-- ========================================
-- STEP 1: FIX ADMIN CSS (REMOVE pointer-events: none)
-- ========================================
DELETE FROM settings WHERE key = 'appearance.admin.custom_css';

INSERT INTO settings (key, value)
VALUES('appearance.admin.custom_css', to_jsonb('/* MOYD Custom Branding - Missouri Young Democrats */

/* ===== FIX DARK TEXT ON TEMPLATE PAGE ===== */
.template-header h1,
.template-header .tag,
.template-header small,
.content h1, .content h2, .content h3,
.title, .subtitle {
  color: #2c3e50 !important;
}

.template-header .tag.is-light,
small, .help-text {
  color: #666 !important;
}

/* ===== REMOVE ONLY THE TOP NAVBAR ===== */
nav.navbar.is-fixed-top {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
}

body.has-navbar-fixed-top {
  padding-top: 0 !important;
}

/* ===== REMOVE PAGE FOOTER BRANDING ===== */
body > footer:not(.modal-card-foot),
.app-footer:not(.modal-card-foot),
.page-footer:not(.modal-card-foot) {
  display: none !important;
}

.modal-card-foot,
.modal-footer,
.modal .modal-card-foot {
  display: flex !important;
  visibility: visible !important;
}

/* ===== CHANGE ALL BLUE TO #273351 ===== */
.button.is-primary, .button.is-link,
.button.is-info, a.button.is-primary,
.has-background-primary, .tag.is-primary,
.notification.is-primary, .message.is-primary,
.hero.is-primary, .navbar.is-primary {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
}

a, a:hover, a:active, a:focus,
.has-text-primary, .has-text-link, .has-text-info {
  color: #273351 !important;
}

.tabs a:hover, .tabs li.is-active a {
  border-bottom-color: #273351 !important;
  color: #273351 !important;
}

.menu-list a.is-active,
.menu-list a:hover,
.menu-list a.router-link-active {
  background-color: #273351 !important;
  color: white !important;
  border-bottom-color: #273351 !important;
}

/* ===== CUSTOM BUTTONS SPACE ===== */
.menu {
  margin-top: 70px !important;
}

/* HIDE CSS PSEUDO-ELEMENT BUTTONS (JavaScript will create real buttons) */
.menu::before,
.menu::after {
  display: none !important;
}

.progress::-webkit-progress-value,
.progress::-moz-progress-bar {
  background-color: #273351 !important;
}

.input:focus, .textarea:focus, .select select:focus,
.input:active, .textarea:active, .select select:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

.checkbox:hover, .radio:hover,
input[type="checkbox"]:checked,
input[type="radio"]:checked {
  border-color: #273351 !important;
  background-color: #273351 !important;
}

.pagination-link.is-current,
.pagination-previous:hover, .pagination-next:hover,
.pagination-link:hover {
  background-color: #273351 !important;
  border-color: #273351 !important;
  color: white !important;
}

.table tr.is-selected {
  background-color: #273351 !important;
  color: white !important;
}

.tag.is-info, .tag.is-link, .badge {
  background-color: #273351 !important;
}

.switch input[type="checkbox"]:checked + .check {
  background-color: #273351 !important;
}

.loader, .spinner {
  border-color: #273351 transparent transparent transparent !important;
}

.dropdown-item.is-active, .dropdown-item:hover {
  background-color: #273351 !important;
  color: white !important;
}

.modal-card-head, .panel-heading {
  background-color: #273351 !important;
}

.menu-list a.router-link-active,
.menu-list a.is-active {
  background-color: #273351 !important;
  color: white !important;
}
'::text));

-- ========================================
-- STEP 2: ADD JAVASCRIPT FOR BUTTONS (INLINE CODE)
-- ========================================
-- This is the CORRECT key: appearance.admin.custom_js (NOT custom_head!)
DELETE FROM settings WHERE key = 'appearance.admin.custom_js';
DELETE FROM settings WHERE key = 'appearance.admin.custom_head'; -- Remove the wrong one

INSERT INTO settings (key, value)
VALUES('appearance.admin.custom_js', to_jsonb('// MOYD Custom Buttons - Refresh and Report Problem
(function() {
  "use strict";

  // Wait for DOM to load
  function init() {
    const menu = document.querySelector(".menu");
    if (!menu) {
      setTimeout(init, 500);
      return;
    }

    // Remove any existing buttons first
    const existing = document.getElementById("moyd-custom-buttons");
    if (existing) existing.remove();

    // Create buttons container
    const buttonsContainer = document.createElement("div");
    buttonsContainer.id = "moyd-custom-buttons";
    buttonsContainer.style.cssText = "position: fixed; top: 15px; left: 15px; z-index: 1000; display: flex; gap: 10px;";

    // Create refresh button
    const refreshBtn = document.createElement("button");
    refreshBtn.innerHTML = "🔄";
    refreshBtn.title = "Refresh Page";
    refreshBtn.style.cssText = "width: 40px; height: 40px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: 20px; cursor: pointer; transition: all 0.3s ease;";
    refreshBtn.onmouseover = function() { this.style.transform = "rotate(180deg)"; this.style.backgroundColor = "#1a2438"; };
    refreshBtn.onmouseout = function() { this.style.transform = "rotate(0deg)"; this.style.backgroundColor = "#273351"; };
    refreshBtn.onclick = function() { location.reload(); };

    // Create report problem button
    const reportBtn = document.createElement("button");
    reportBtn.innerHTML = "?";
    reportBtn.title = "Report a Problem";
    reportBtn.style.cssText = "width: 40px; height: 40px; background-color: #273351; border: none; border-radius: 8px; color: white; font-size: 24px; font-weight: bold; cursor: pointer; transition: background-color 0.3s ease;";
    reportBtn.onmouseover = function() { this.style.backgroundColor = "#1a2438"; };
    reportBtn.onmouseout = function() { this.style.backgroundColor = "#273351"; };
    reportBtn.onclick = showReportModal;

    // Add buttons to container
    buttonsContainer.appendChild(refreshBtn);
    buttonsContainer.appendChild(reportBtn);
    document.body.appendChild(buttonsContainer);

    // Adjust menu margin
    menu.style.marginTop = "20px";
  }

  // Create and show report modal
  function showReportModal() {
    // Remove existing modal if any
    const existing = document.getElementById("moyd-report-modal");
    if (existing) existing.remove();

    // Create modal overlay
    const modal = document.createElement("div");
    modal.id = "moyd-report-modal";
    modal.style.cssText = "position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 10000;";

    // Create modal content
    const modalContent = document.createElement("div");
    modalContent.style.cssText = "background: white; padding: 30px; border-radius: 12px; max-width: 500px; box-shadow: 0 4px 20px rgba(0,0,0,0.3);";

    // Modal HTML
    modalContent.innerHTML = `
      <h2 style="margin: 0 0 10px 0; color: #273351; font-size: 24px;">Report a Problem</h2>
      <p style="margin: 0 0 25px 0; color: #666; font-size: 14px;">
        Having an issue? Contact Andrew directly via text message or email.
      </p>
      <div style="display: flex; gap: 15px; margin-bottom: 20px;">
        <a href="sms:+18168983612&body=Hey%20Andrew%2C%20I%27m%20currently%20having%20a%20problem%20with%20the%20email%20campaign%20feature%20on%20moyd.app.%20"
           style="flex: 1; display: flex; flex-direction: column; align-items: center; padding: 20px; background: #273351; color: white; text-decoration: none; border-radius: 8px; transition: background 0.3s;"
           onmouseover="this.style.backgroundColor=''#1a2438''"
           onmouseout="this.style.backgroundColor=''#273351''">
          <span style="font-size: 32px; margin-bottom: 10px;">💬</span>
          <span style="font-size: 16px; font-weight: bold;">Send Text</span>
          <span style="font-size: 12px; margin-top: 5px; opacity: 0.9;">816-898-3612</span>
        </a>
        <a href="mailto:andrew@moyoungdemocrats.org?subject=MOYD%20App%20Issue&body=Hey%20Andrew%2C%0A%0AI%27m%20currently%20having%20a%20problem%20with%20the%20email%20campaign%20feature%20on%20moyd.app.%0A%0ADetails%3A%0A"
           style="flex: 1; display: flex; flex-direction: column; align-items: center; padding: 20px; background: #273351; color: white; text-decoration: none; border-radius: 8px; transition: background 0.3s;"
           onmouseover="this.style.backgroundColor=''#1a2438''"
           onmouseout="this.style.backgroundColor=''#273351''">
          <span style="font-size: 32px; margin-bottom: 10px;">✉️</span>
          <span style="font-size: 16px; font-weight: bold;">Send Email</span>
          <span style="font-size: 12px; margin-top: 5px; opacity: 0.9;">andrew@moyoungdemocrats.org</span>
        </a>
      </div>
      <button onclick="document.getElementById(''moyd-report-modal'').remove();"
              style="width: 100%; padding: 12px; background: #e0e0e0; border: none; border-radius: 8px; color: #333; font-size: 14px; cursor: pointer; transition: background 0.3s;"
              onmouseover="this.style.backgroundColor=''#d0d0d0''"
              onmouseout="this.style.backgroundColor=''#e0e0e0''">
        Close
      </button>
    `;

    modal.appendChild(modalContent);

    // Close modal when clicking outside
    modal.onclick = function(e) {
      if (e.target === modal) {
        modal.remove();
      }
    };

    document.body.appendChild(modal);
  }

  // Initialize when DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
'::text));

-- ========================================
-- STEP 3: FIX LOGIN PAGE CSS
-- ========================================
DELETE FROM settings WHERE key = 'appearance.public.custom_css';

INSERT INTO settings (key, value)
VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Login Page Customization - Missouri Young Democrats */

/* ===== LOGIN PAGE LOGO ===== */
.login .container {
  max-width: 500px;
  margin: 0 auto;
  padding: 40px 20px;
}

/* Login logo container - CENTERED */
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

.login .input:focus,
.login .input:active {
  border-color: #273351 !important;
  box-shadow: 0 0 0 0.125em rgba(39, 51, 81, 0.25) !important;
}

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
.login .box {
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  border-radius: 8px;
}

.login .title {
  color: #273351 !important;
  text-align: center;
  margin-bottom: 25px;
}
'::text));

-- ========================================
-- STEP 4: VERIFY ALL SETTINGS
-- ========================================
SELECT
  key,
  CASE
    WHEN key LIKE '%custom_js%' THEN LEFT(value::text, 150) || '...'
    WHEN key LIKE '%custom_css%' THEN LEFT(value::text, 150) || '...'
    ELSE value::text
  END as value_preview
FROM settings
WHERE key LIKE 'appearance%'
ORDER BY key;

-- ========================================
-- DONE! Now do this:
-- 1. Hard refresh your browser (Cmd+Shift+R)
-- 2. Click the refresh button (🔄) - it should reload the page
-- 3. Click the help button (?) - a modal should pop up
-- 4. Check the login page - should have MOYD logo and navy colors
-- ========================================
