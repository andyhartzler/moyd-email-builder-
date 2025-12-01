# MOYD Listmonk Deployment

Complete deployment configuration for Listmonk email campaign system integrated with MOYD CRM.

## Overview

This directory contains everything needed to deploy Listmonk as a separate email campaign service that syncs with your Supabase database and embeds in your Flutter CRM.

**Architecture:**
- Listmonk runs in its own schema (`listmonk`) in your Supabase database
- Your existing tables (`public.subscribers`, `donors`, `members`) remain unchanged
- Automatic bidirectional sync via Supabase triggers and Edge Functions
- Embedded in Flutter CRM via iframe

## Prerequisites

- Supabase project (free tier works)
- Railway.app or Render.com account (free tier works)
- Domain name (optional, for custom domain like `mail.moyd.app`)

---

## Quick Start - Railway Deployment

### 1. Prepare Supabase Database

Before deploying, you need to set up the Listmonk schema in Supabase (see **Supabase Setup** section below for SQL scripts).

### 2. Deploy to Railway

1. **Create Railway Account**
   - Go to https://railway.app
   - Sign up with GitHub

2. **Create New Project**
   - Click "New Project" → "Deploy from GitHub repo"
   - Select this repository
   - Railway will detect the Dockerfile

3. **Set Environment Variables**

   Go to your Railway project → Variables → Add the following:

   ```env
   LISTMONK_ROOT_URL=https://your-project-name.up.railway.app
   LISTMONK_ADMIN_USERNAME=admin
   LISTMONK_ADMIN_PASSWORD=YourSecurePassword123!
   DB_HOST=aws-0-us-east-1.pooler.supabase.com
   DB_USER=postgres.your-project-ref
   DB_PASSWORD=your-supabase-db-password
   DB_NAME=postgres
   ```

   **Where to find Supabase credentials:**
   - Go to your Supabase project
   - Settings → Database → Connection string
   - Use the "Connection pooling" string in Transaction mode
   - Format: `postgresql://postgres.xxx:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:6543/postgres`
   - Extract: `DB_HOST`, `DB_USER`, `DB_PASSWORD`

4. **Deploy**
   - Railway will automatically build and deploy
   - Wait for deployment to complete (~2-3 minutes)
   - Note your URL: `https://[project-name].up.railway.app`

5. **Verify Deployment**
   - Visit your Railway URL
   - You should see the Listmonk login page
   - Login with your admin credentials
   - Complete initial setup wizard

---

## Quick Start - Render Deployment

### 1. Create Render Account
- Go to https://render.com
- Sign up with GitHub

### 2. Deploy Web Service

1. **New Web Service**
   - Dashboard → "New +" → "Web Service"
   - Connect this repository
   - Render will detect `render.yaml`

2. **Configure Environment Variables**

   Add these in the Render dashboard:

   ```env
   LISTMONK_ROOT_URL=https://moyd-listmonk.onrender.com
   LISTMONK_ADMIN_USERNAME=admin
   LISTMONK_ADMIN_PASSWORD=YourSecurePassword123!
   DB_HOST=aws-0-us-east-1.pooler.supabase.com
   DB_USER=postgres.your-project-ref
   DB_PASSWORD=your-supabase-db-password
   DB_NAME=postgres
   ```

3. **Deploy**
   - Click "Create Web Service"
   - Wait for build to complete (~3-5 minutes)
   - Access at `https://[your-service-name].onrender.com`

---

## Local Development

### Using Docker Compose

1. **Copy environment file**
   ```bash
   cd listmonk-deployment
   cp .env.example .env
   ```

2. **Edit `.env` with your Supabase credentials**
   ```bash
   SUPABASE_DB_HOST=aws-0-us-east-1.pooler.supabase.com
   SUPABASE_DB_PASSWORD=your-password
   ```

3. **Start Listmonk**
   ```bash
   docker-compose up -d
   ```

4. **Access Listmonk**
   - Open http://localhost:9000
   - Login: `admin` / `admin123`

5. **Stop**
   ```bash
   docker-compose down
   ```

---

## Initial Configuration

After deployment, complete these steps:

### 1. Login to Listmonk

Access your deployed URL and login with your admin credentials.

### 2. Configure SMTP (Amazon SES)

1. **Go to Settings → SMTP**
2. **Add New SMTP Server**
   ```
   Host: email-smtp.us-east-1.amazonaws.com
   Port: 587
   Auth protocol: LOGIN
   Username: [Your AWS SES SMTP Username]
   Password: [Your AWS SES SMTP Password]
   TLS: STARTTLS
   Max connections: 10
   ```

3. **Set as default** and **Enable**

4. **Send test email** to verify

### 3. Create Your First List

1. Go to **Lists**
2. Click **New List**
   ```
   Name: MOYD Subscribers
   Type: Public
   Opt-in: Double opt-in (recommended)
   ```

### 4. Import Subscribers (Optional)

If you have existing subscribers:

1. Go to **Subscribers → Import**
2. Upload CSV with columns: `email`, `name`, `status`
3. Map fields and import

---

## Custom Domain Setup

### Option 1: Railway Custom Domain

1. **Go to Railway Project Settings → Domains**
2. **Click "Add Custom Domain"**
3. **Enter:** `mail.moyd.app`
4. **Update DNS at your domain registrar:**
   ```
   Type: CNAME
   Name: mail
   Value: [your-project].up.railway.app
   TTL: 3600
   ```

5. **Wait for DNS propagation** (up to 24 hours)

6. **Update Environment Variable:**
   ```env
   LISTMONK_ROOT_URL=https://mail.moyd.app
   ```

### Option 2: Render Custom Domain

1. **Go to Render Service → Settings**
2. **Click "Add Custom Domain"**
3. **Enter:** `mail.moyd.app`
4. **Follow DNS instructions** provided by Render
5. **Update LISTMONK_ROOT_URL** environment variable

---

## Supabase Setup

### Database Schema Setup

Run these SQL commands in Supabase SQL Editor:

```sql
-- Create listmonk schema
CREATE SCHEMA IF NOT EXISTS listmonk;

-- Grant permissions
GRANT USAGE ON SCHEMA listmonk TO postgres;
GRANT ALL ON SCHEMA listmonk TO postgres;

-- Listmonk will create its own tables on first run
-- The search_path in config.toml ensures it uses the listmonk schema
```

### Enable Realtime Sync (Optional)

To sync subscribers from your existing tables to Listmonk:

```sql
-- Create sync function
CREATE OR REPLACE FUNCTION public.sync_to_listmonk()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert or update in listmonk.subscribers
  INSERT INTO listmonk.subscribers (email, name, status, created_at, updated_at)
  VALUES (NEW.email, NEW.name, 'enabled', NOW(), NOW())
  ON CONFLICT (email)
  DO UPDATE SET
    name = NEW.name,
    updated_at = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on public.subscribers
CREATE TRIGGER sync_subscribers_to_listmonk
AFTER INSERT OR UPDATE ON public.subscribers
FOR EACH ROW
EXECUTE FUNCTION public.sync_to_listmonk();
```

**Note:** Full sync implementation requires Supabase Edge Functions (see **Integration Documentation**).

---

## Flutter Integration

To embed Listmonk in your Flutter CRM:

### 1. Add WebView Package

```yaml
# pubspec.yaml
dependencies:
  webview_flutter: ^4.4.0
```

### 2. Create Listmonk Screen

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ListmonkScreen extends StatefulWidget {
  const ListmonkScreen({Key? key}) : super(key: key);

  @override
  State<ListmonkScreen> createState() => _ListmonkScreenState();
}

class _ListmonkScreenState extends State<ListmonkScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // Inject authentication token if needed
          },
        ),
      )
      ..loadRequest(Uri.parse('https://mail.moyd.app'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Campaigns'),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
```

### 3. Add to Navigation

```dart
ListTile(
  leading: const Icon(Icons.email),
  title: const Text('Email Campaigns'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ListmonkScreen()),
    );
  },
),
```

---

## API Integration

Listmonk provides a REST API for programmatic access:

### Authentication

Use HTTP Basic Auth with your admin credentials:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ListmonkService {
  final String baseUrl = 'https://mail.moyd.app';
  final String username = 'admin';
  final String password = 'your-password';

  String get _authHeader {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  Future<List<dynamic>> getCampaigns() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/campaigns'),
      headers: {'Authorization': _authHeader},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['data']['results'];
    } else {
      throw Exception('Failed to load campaigns');
    }
  }

  Future<void> createSubscriber({
    required String email,
    required String name,
    required List<int> listIds,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/subscribers'),
      headers: {
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'email': email,
        'name': name,
        'status': 'enabled',
        'lists': listIds,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create subscriber');
    }
  }
}
```

### Common API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/campaigns` | List all campaigns |
| POST | `/api/campaigns` | Create new campaign |
| GET | `/api/subscribers` | List subscribers |
| POST | `/api/subscribers` | Add subscriber |
| GET | `/api/lists` | Get mailing lists |
| POST | `/api/campaigns/:id/start` | Start campaign |

Full API docs: https://listmonk.app/docs/apis/apis

---

## Troubleshooting

### Deployment Issues

**Problem:** "Cannot connect to database"
- Verify Supabase credentials are correct
- Ensure you're using the **Connection Pooling** string (port 6543)
- Check that `search_path=listmonk,public` is set

**Problem:** "Port already in use" (local development)
- Change port in docker-compose.yml: `"9001:9000"`

### SMTP Issues

**Problem:** Emails not sending
- Verify Amazon SES is out of sandbox mode
- Check SES sending limits
- Verify domain is verified in SES
- Test SMTP credentials with telnet

**Problem:** "550 Unauthenticated email"
- Verify sender email domain in SES
- Add SPF/DKIM records to DNS

### iframe Embedding Issues

**Problem:** "Refused to display in a frame"
- Verify `frame_options = "SAMEORIGIN"` in config.toml
- Check CORS settings allow your Flutter app domain

---

## Security Best Practices

1. **Change default admin password** immediately after deployment
2. **Use strong passwords** (16+ characters, mixed case, numbers, symbols)
3. **Enable 2FA** in Listmonk settings (if available)
4. **Restrict database access** to only Railway/Render IPs
5. **Use environment variables** for all secrets (never commit to git)
6. **Enable HTTPS** (automatic with Railway/Render)
7. **Regularly update** Listmonk version

---

## Monitoring & Maintenance

### Check Application Health

```bash
curl https://mail.moyd.app/api/health
```

Expected response: `{"status": "ok"}`

### View Logs

**Railway:**
- Go to project → Deployments → Click latest → View logs

**Render:**
- Go to service → Logs

### Database Backup

**Supabase** automatically backs up your database. To manually export:

1. Supabase Dashboard → Database → Backups
2. Download latest backup

### Update Listmonk Version

Edit `Dockerfile`:

```dockerfile
FROM listmonk/listmonk:v3.1.0  # Update version
```

Commit and push - Railway/Render will auto-deploy.

---

## Cost Estimates

| Service | Free Tier | Paid Tier |
|---------|-----------|-----------|
| **Railway** | $5 credit/month | ~$5-10/month |
| **Render** | 750 hours/month | $7/month (Starter) |
| **Supabase** | 500MB database | $25/month (Pro) |
| **Amazon SES** | 62,000 emails/month (from EC2) | $0.10/1000 emails |

**Total monthly cost (estimated):** $0-15 for small-medium usage

---

## Support & Resources

- **Listmonk Docs:** https://listmonk.app/docs
- **Listmonk GitHub:** https://github.com/knadh/listmonk
- **Railway Docs:** https://docs.railway.app
- **Render Docs:** https://render.com/docs
- **Supabase Docs:** https://supabase.com/docs

---

## License

Private - MOYD Internal Use Only
