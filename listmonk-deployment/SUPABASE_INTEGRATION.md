# Supabase + Listmonk Integration Guide

Complete database setup and synchronization guide for integrating Listmonk with your Supabase backend.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Database Schema Setup](#database-schema-setup)
3. [Subscriber Sync - Simple Triggers](#subscriber-sync-simple-triggers)
4. [Subscriber Sync - Edge Functions](#subscriber-sync-edge-functions)
5. [Bidirectional Sync](#bidirectional-sync)
6. [Testing & Verification](#testing--verification)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌───────────────────────────────────────────────────┐
│              Supabase Database                    │
│                                                   │
│  ┌─────────────────┐      ┌──────────────────┐  │
│  │  public schema  │      │ listmonk schema  │  │
│  │                 │      │                  │  │
│  │  - subscribers  │─────▶│  - subscribers   │  │
│  │  - donors       │ sync │  - lists         │  │
│  │  - members      │      │  - campaigns     │  │
│  │  - event_atts   │      │  - templates     │  │
│  └─────────────────┘      └──────────────────┘  │
│         │                           │            │
│         ▼                           ▼            │
│   Database Triggers          Edge Functions      │
│                                                   │
└───────────────────────────────────────────────────┘
                      │
                      ▼
            ┌──────────────────┐
            │  Listmonk Server │
            │   (Railway)      │
            └──────────────────┘
```

**Key Principles:**
- **Separate Schemas:** Listmonk uses `listmonk` schema, your app uses `public` schema
- **No Data Duplication Risk:** Clear separation prevents conflicts
- **Automatic Sync:** Triggers keep data in sync automatically
- **Bidirectional:** Unsubscribes in Listmonk update your tables

---

## Database Schema Setup

### Step 1: Create Listmonk Schema

Open Supabase SQL Editor and run:

```sql
-- Create listmonk schema (Listmonk will populate it automatically)
CREATE SCHEMA IF NOT EXISTS listmonk;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA listmonk TO postgres;
GRANT ALL ON SCHEMA listmonk TO postgres;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA listmonk GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA listmonk GRANT ALL ON SEQUENCES TO postgres;
```

### Step 2: Verify Your Existing Tables

Check your current table structure:

```sql
-- View existing public.subscribers table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'subscribers';
```

**Expected columns in your existing tables:**
- `public.subscribers`: `id`, `email`, `name`, `status`, `created_at`, etc.
- `public.donors`: `id`, `email`, `name`, ...
- `public.members`: `id`, `email`, `name`, ...

### Step 3: Deploy Listmonk (Creates Schema Tables)

After deploying Listmonk to Railway/Render (see main README), Listmonk will automatically create its tables in the `listmonk` schema:

- `listmonk.subscribers`
- `listmonk.lists`
- `listmonk.campaigns`
- `listmonk.templates`
- `listmonk.campaign_views`
- `listmonk.link_clicks`

**Verify tables were created:**

```sql
-- List all Listmonk tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'listmonk';
```

---

## Subscriber Sync - Simple Triggers

### Option 1: One-Way Sync (CRM → Listmonk)

This approach automatically copies new subscribers from your public schema to Listmonk.

#### Create Sync Function

```sql
-- Function to sync subscribers to Listmonk
CREATE OR REPLACE FUNCTION public.sync_subscriber_to_listmonk()
RETURNS TRIGGER AS $$
DECLARE
  default_list_id INTEGER := 1; -- Your default mailing list ID in Listmonk
BEGIN
  -- Only sync if email is not null
  IF NEW.email IS NULL OR NEW.email = '' THEN
    RETURN NEW;
  END IF;

  -- Insert or update in listmonk.subscribers
  INSERT INTO listmonk.subscribers (
    email,
    name,
    status,
    attribs,
    created_at,
    updated_at
  )
  VALUES (
    NEW.email,
    COALESCE(NEW.name, ''),
    CASE
      WHEN NEW.status = 'active' THEN 'enabled'
      WHEN NEW.status = 'inactive' THEN 'blocklisted'
      ELSE 'enabled'
    END,
    jsonb_build_object(
      'source', 'crm',
      'crm_id', NEW.id,
      'synced_at', NOW()
    ),
    COALESCE(NEW.created_at, NOW()),
    NOW()
  )
  ON CONFLICT (email)
  DO UPDATE SET
    name = COALESCE(EXCLUDED.name, listmonk.subscribers.name),
    status = EXCLUDED.status,
    attribs = listmonk.subscribers.attribs || EXCLUDED.attribs,
    updated_at = NOW();

  -- Add to default list
  INSERT INTO listmonk.subscriber_lists (subscriber_id, list_id, status)
  SELECT
    (SELECT id FROM listmonk.subscribers WHERE email = NEW.email),
    default_list_id,
    'unconfirmed'
  ON CONFLICT (subscriber_id, list_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

#### Create Triggers on Your Tables

```sql
-- Trigger for public.subscribers
DROP TRIGGER IF EXISTS sync_subscribers_to_listmonk ON public.subscribers;
CREATE TRIGGER sync_subscribers_to_listmonk
  AFTER INSERT OR UPDATE OF email, name, status
  ON public.subscribers
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_subscriber_to_listmonk();

-- Trigger for public.donors (if you want to sync donors)
DROP TRIGGER IF EXISTS sync_donors_to_listmonk ON public.donors;
CREATE TRIGGER sync_donors_to_listmonk
  AFTER INSERT OR UPDATE OF email, name
  ON public.donors
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_subscriber_to_listmonk();

-- Trigger for public.members
DROP TRIGGER IF EXISTS sync_members_to_listmonk ON public.members;
CREATE TRIGGER sync_members_to_listmonk
  AFTER INSERT OR UPDATE OF email, name
  ON public.members
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_subscriber_to_listmonk();

-- Trigger for public.event_attendees
DROP TRIGGER IF EXISTS sync_attendees_to_listmonk ON public.event_attendees;
CREATE TRIGGER sync_attendees_to_listmonk
  AFTER INSERT OR UPDATE OF email, name
  ON public.event_attendees
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_subscriber_to_listmonk();
```

### Option 2: Custom List Assignment

If you want different tables to sync to different Listmonk lists:

```sql
-- Create table-specific sync functions
CREATE OR REPLACE FUNCTION public.sync_donor_to_listmonk()
RETURNS TRIGGER AS $$
BEGIN
  -- Sync to Donors list (ID: 2)
  PERFORM sync_to_listmonk_list(NEW.email, NEW.name, 2);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sync_member_to_listmonk()
RETURNS TRIGGER AS $$
BEGIN
  -- Sync to Members list (ID: 3)
  PERFORM sync_to_listmonk_list(NEW.email, NEW.name, 3);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function
CREATE OR REPLACE FUNCTION public.sync_to_listmonk_list(
  p_email TEXT,
  p_name TEXT,
  p_list_id INTEGER
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO listmonk.subscribers (email, name, status, created_at, updated_at)
  VALUES (p_email, p_name, 'enabled', NOW(), NOW())
  ON CONFLICT (email) DO UPDATE SET
    name = EXCLUDED.name,
    updated_at = NOW();

  INSERT INTO listmonk.subscriber_lists (subscriber_id, list_id, status)
  SELECT
    (SELECT id FROM listmonk.subscribers WHERE email = p_email),
    p_list_id,
    'confirmed'
  ON CONFLICT (subscriber_id, list_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
```

---

## Subscriber Sync - Edge Functions

For more complex sync logic (API calls, webhooks, etc.), use Supabase Edge Functions.

### Step 1: Create Edge Function

```bash
# Initialize Supabase CLI (if not already done)
npx supabase init

# Create new Edge Function
npx supabase functions new sync-to-listmonk
```

### Step 2: Implement Edge Function

Edit `supabase/functions/sync-to-listmonk/index.ts`:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const LISTMONK_URL = Deno.env.get('LISTMONK_URL') || 'https://mail.moyd.app'
const LISTMONK_USER = Deno.env.get('LISTMONK_USER') || 'admin'
const LISTMONK_PASSWORD = Deno.env.get('LISTMONK_PASSWORD') || ''

serve(async (req) => {
  try {
    const { type, record, old_record } = await req.json()

    // Handle different event types
    if (type === 'INSERT' || type === 'UPDATE') {
      await syncSubscriberToListmonk(record)
    }

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})

async function syncSubscriberToListmonk(subscriber: any) {
  const auth = btoa(`${LISTMONK_USER}:${LISTMONK_PASSWORD}`)

  // Check if subscriber exists
  const searchResponse = await fetch(
    `${LISTMONK_URL}/api/subscribers?query=email:${subscriber.email}`,
    {
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
    }
  )

  const searchData = await searchResponse.json()
  const existingSubscriber = searchData.data?.results?.[0]

  if (existingSubscriber) {
    // Update existing subscriber
    await fetch(`${LISTMONK_URL}/api/subscribers/${existingSubscriber.id}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: subscriber.email,
        name: subscriber.name || '',
        status: subscriber.status === 'active' ? 'enabled' : 'blocklisted',
        attribs: {
          crm_id: subscriber.id,
          synced_at: new Date().toISOString(),
        },
      }),
    })
  } else {
    // Create new subscriber
    await fetch(`${LISTMONK_URL}/api/subscribers`, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: subscriber.email,
        name: subscriber.name || '',
        status: 'enabled',
        lists: [1], // Default list ID
        attribs: {
          crm_id: subscriber.id,
          synced_at: new Date().toISOString(),
        },
      }),
    })
  }
}
```

### Step 3: Deploy Edge Function

```bash
# Set secrets
npx supabase secrets set LISTMONK_URL=https://mail.moyd.app
npx supabase secrets set LISTMONK_USER=admin
npx supabase secrets set LISTMONK_PASSWORD=your-password

# Deploy
npx supabase functions deploy sync-to-listmonk
```

### Step 4: Create Database Webhook

```sql
-- Create webhook trigger
CREATE OR REPLACE FUNCTION public.notify_sync_subscriber()
RETURNS TRIGGER AS $$
DECLARE
  payload JSONB;
BEGIN
  payload := jsonb_build_object(
    'type', TG_OP,
    'record', row_to_json(NEW),
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
  );

  -- Call Edge Function via pg_net or supabase_functions
  PERFORM
    net.http_post(
      url := 'https://your-project.supabase.co/functions/v1/sync-to-listmonk',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
      ),
      body := payload
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach to subscribers table
CREATE TRIGGER webhook_sync_subscribers
  AFTER INSERT OR UPDATE ON public.subscribers
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_sync_subscriber();
```

---

## Bidirectional Sync

Handle unsubscribes in Listmonk and update your CRM.

### Step 1: Enable Listmonk Webhooks

In Listmonk settings, configure webhook:
- URL: `https://your-project.supabase.co/functions/v1/handle-listmonk-webhook`
- Events: `subscriber.status.update`, `subscriber.unsubscribe`

### Step 2: Create Webhook Handler Edge Function

```bash
npx supabase functions new handle-listmonk-webhook
```

Edit `supabase/functions/handle-listmonk-webhook/index.ts`:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    const webhook = await req.json()

    // Handle unsubscribe event
    if (webhook.type === 'subscriber.unsubscribe') {
      const email = webhook.data.email

      // Update in public.subscribers
      await supabase
        .from('subscribers')
        .update({ status: 'unsubscribed', updated_at: new Date() })
        .eq('email', email)

      console.log(`Unsubscribed: ${email}`)
    }

    // Handle status update
    if (webhook.type === 'subscriber.status.update') {
      const email = webhook.data.email
      const status = webhook.data.status // 'enabled', 'blocklisted', etc.

      await supabase
        .from('subscribers')
        .update({
          status: status === 'blocklisted' ? 'inactive' : 'active',
          updated_at: new Date()
        })
        .eq('email', email)
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }
})
```

### Step 3: Deploy Webhook Handler

```bash
npx supabase functions deploy handle-listmonk-webhook
```

---

## Initial Data Migration

### Bulk Import Existing Subscribers

```sql
-- One-time migration of all existing subscribers
INSERT INTO listmonk.subscribers (email, name, status, attribs, created_at, updated_at)
SELECT
  email,
  name,
  CASE
    WHEN status = 'active' THEN 'enabled'::subscriber_status
    ELSE 'blocklisted'::subscriber_status
  END,
  jsonb_build_object('source', 'crm', 'crm_id', id),
  created_at,
  NOW()
FROM public.subscribers
WHERE email IS NOT NULL AND email != ''
ON CONFLICT (email) DO NOTHING;

-- Assign all to default list
INSERT INTO listmonk.subscriber_lists (subscriber_id, list_id, status)
SELECT s.id, 1, 'confirmed'
FROM listmonk.subscribers s
WHERE NOT EXISTS (
  SELECT 1 FROM listmonk.subscriber_lists sl
  WHERE sl.subscriber_id = s.id AND sl.list_id = 1
);
```

---

## Testing & Verification

### Test Sync Trigger

```sql
-- Insert test subscriber
INSERT INTO public.subscribers (email, name, status)
VALUES ('test@example.com', 'Test User', 'active');

-- Verify it synced to Listmonk
SELECT * FROM listmonk.subscribers WHERE email = 'test@example.com';

-- Verify list assignment
SELECT s.email, l.name as list_name
FROM listmonk.subscribers s
JOIN listmonk.subscriber_lists sl ON s.id = sl.subscriber_id
JOIN listmonk.lists l ON sl.list_id = l.id
WHERE s.email = 'test@example.com';
```

### Test Update Sync

```sql
-- Update subscriber
UPDATE public.subscribers
SET name = 'Updated Name'
WHERE email = 'test@example.com';

-- Verify update synced
SELECT email, name, updated_at
FROM listmonk.subscribers
WHERE email = 'test@example.com';
```

### Monitor Edge Function Logs

```bash
# View logs
npx supabase functions logs sync-to-listmonk

# Or in Supabase dashboard:
# Edge Functions → sync-to-listmonk → Logs
```

---

## Troubleshooting

### Sync Not Working

**Check trigger exists:**
```sql
SELECT * FROM information_schema.triggers
WHERE event_object_table = 'subscribers';
```

**Check function exists:**
```sql
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%listmonk%';
```

**Manually test function:**
```sql
-- Test the sync function directly
SELECT public.sync_subscriber_to_listmonk();
```

### Schema Permissions Issues

```sql
-- Grant all necessary permissions
GRANT USAGE ON SCHEMA listmonk TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA listmonk TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA listmonk TO postgres;
```

### Duplicate Email Errors

Listmonk enforces unique emails. Check for duplicates:

```sql
-- Find duplicate emails in public.subscribers
SELECT email, COUNT(*)
FROM public.subscribers
GROUP BY email
HAVING COUNT(*) > 1;
```

### Edge Function Timeout

If syncing large batches, use background jobs:

```sql
-- Queue-based approach
CREATE TABLE public.sync_queue (
  id SERIAL PRIMARY KEY,
  email TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Process queue in batches via cron
```

---

## Performance Optimization

### Batch Sync

For initial migration of thousands of records:

```sql
-- Create temporary sync queue
CREATE TEMP TABLE sync_batch AS
SELECT email, name, status
FROM public.subscribers
WHERE email IS NOT NULL
LIMIT 1000; -- Process in batches

-- Process batch
-- (Your sync logic here)

-- Repeat for next batch
```

### Index Optimization

```sql
-- Add indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_listmonk_subscribers_email
  ON listmonk.subscribers(email);

CREATE INDEX IF NOT EXISTS idx_public_subscribers_email
  ON public.subscribers(email);
```

---

## Monitoring & Maintenance

### Create Sync Status View

```sql
CREATE OR REPLACE VIEW public.sync_status AS
SELECT
  ps.id as crm_id,
  ps.email,
  ps.name as crm_name,
  ls.name as listmonk_name,
  ps.updated_at as crm_updated,
  ls.updated_at as listmonk_updated,
  CASE
    WHEN ls.email IS NULL THEN 'NOT_SYNCED'
    WHEN ps.updated_at > ls.updated_at THEN 'NEEDS_UPDATE'
    ELSE 'SYNCED'
  END as sync_status
FROM public.subscribers ps
LEFT JOIN listmonk.subscribers ls ON ps.email = ls.email;

-- Query sync status
SELECT sync_status, COUNT(*)
FROM public.sync_status
GROUP BY sync_status;
```

### Scheduled Sync Check (Optional)

Use Supabase cron or pg_cron:

```sql
-- Install pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule daily sync check
SELECT cron.schedule(
  'sync-check',
  '0 2 * * *', -- 2 AM daily
  $$
    -- Your sync verification query
    SELECT COUNT(*) FROM public.sync_status WHERE sync_status = 'NEEDS_UPDATE';
  $$
);
```

---

## Security Best Practices

1. **Never expose service role keys** in client code
2. **Use Row Level Security (RLS)** on public tables
3. **Restrict Edge Function access** via API keys
4. **Encrypt sensitive data** in attribs JSON
5. **Audit sync operations** via logging

---

## Next Steps

1. ✅ Set up database schema
2. ✅ Configure sync triggers
3. ✅ Test with sample data
4. Migrate existing subscribers
5. Set up bidirectional sync
6. Configure Listmonk webhooks
7. Monitor and optimize

---

## Support Resources

- Supabase Edge Functions: https://supabase.com/docs/guides/functions
- Listmonk API: https://listmonk.app/docs/apis/apis
- PostgreSQL Triggers: https://www.postgresql.org/docs/current/sql-createtrigger.html
