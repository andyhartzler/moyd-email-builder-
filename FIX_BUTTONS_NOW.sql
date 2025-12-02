-- RUN THIS IN SUPABASE SQL EDITOR TO FIX BUTTONS RIGHT NOW
-- This will make the buttons functional immediately

SET search_path TO listmonk;

-- Force delete and re-insert the custom head JavaScript
DELETE FROM settings WHERE key = 'appearance.admin.custom_head';

INSERT INTO settings (key, value)
VALUES('appearance.admin.custom_head', to_jsonb('<script src="/static/custom-buttons.js"></script>'::text));

-- Verify it was inserted
SELECT key, value FROM settings WHERE key = 'appearance.admin.custom_head';

-- AFTER RUNNING THIS:
-- 1. Hard refresh the page (Ctrl+Shift+R or Cmd+Shift+R)
-- 2. The buttons should become functional (clickable)
-- 3. Check browser console for any JavaScript errors
