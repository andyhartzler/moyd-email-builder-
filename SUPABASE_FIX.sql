-- SUPABASE SQL FIX - Run this in your Supabase SQL editor
-- This will immediately set the public CSS, custom head JavaScript, and fix the login page

SET search_path TO listmonk;

-- Step 1: Delete existing empty values
DELETE FROM settings WHERE key IN ('appearance.public.custom_css', 'appearance.admin.custom_head');

-- Step 2: Insert custom JavaScript to load buttons
INSERT INTO settings (key, value)
VALUES('appearance.admin.custom_head', to_jsonb('<script src="/static/custom-buttons.js"></script>'::text));

-- Step 3: Insert public CSS for login page
INSERT INTO settings (key, value)
VALUES('appearance.public.custom_css', to_jsonb('/* MOYD Login Page Customization - Missouri Young Democrats */

/* ===== LOGIN PAGE LOGO ===== */
/* Center the login container */
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

-- Step 4: Verify the values were inserted
SELECT key, LEFT(value::text, 100) as value_preview
FROM settings
WHERE key LIKE 'appearance%'
ORDER BY key;
