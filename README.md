# MOYD Listmonk Email Campaign System

Complete deployment and integration configuration for Listmonk email campaign management system.

## Overview

This repository contains everything needed to deploy and integrate [Listmonk](https://github.com/knadh/listmonk) as a full-featured email campaign system for the MOYD CRM.

**Listmonk** is a self-hosted newsletter and mailing list manager with a modern UI, powerful features, and real-time analytics.

## Architecture

```
Flutter CRM ──(iframe)──> Listmonk UI (Railway/Render)
     │                         │
     └──(API)───────────────────┘
                │
                ▼
           Supabase DB
           ├── public schema (your tables)
           └── listmonk schema (auto-sync via triggers)
                │
                ▼
            Amazon SES (email sending)
```

## Repository Structure

```
moyd-listmonk/
├── listmonk-deployment/
│   ├── Dockerfile                    # Production container
│   ├── config.toml.template          # Listmonk configuration
│   ├── railway.json                  # Railway deployment
│   ├── render.yaml                   # Render deployment
│   ├── docker-compose.yml            # Local development
│   ├── .env.example                  # Environment variables template
│   ├── README.md                     # Deployment guide
│   ├── FLUTTER_INTEGRATION.md        # Flutter CRM integration
│   └── SUPABASE_INTEGRATION.md       # Database setup & sync
└── README.md                         # This file
```

## Quick Start

### 1. Deploy Listmonk

Choose your preferred platform:

**Railway (Recommended)**
```bash
cd listmonk-deployment
# Follow instructions in README.md
```

**Render**
```bash
cd listmonk-deployment
# Follow instructions in README.md
```

**Local Development**
```bash
cd listmonk-deployment
cp .env.example .env
# Edit .env with your Supabase credentials
docker-compose up -d
```

Deployment takes ~5 minutes and is covered in detail in [`listmonk-deployment/README.md`](./listmonk-deployment/README.md).

### 2. Configure Supabase Database

Set up the database schema and automatic sync:

```bash
# See listmonk-deployment/SUPABASE_INTEGRATION.md for full SQL scripts
```

Key steps:
- Create `listmonk` schema in Supabase
- Set up automatic sync triggers from your CRM tables
- Configure bidirectional sync (unsubscribes)

Full guide: [`listmonk-deployment/SUPABASE_INTEGRATION.md`](./listmonk-deployment/SUPABASE_INTEGRATION.md)

### 3. Integrate with Flutter CRM

Embed Listmonk in your Flutter app:

```dart
// Add WebView
import 'package:webview_flutter/webview_flutter.dart';

// Add API service
import 'package:moyd_crm/services/listmonk_service.dart';
```

Complete integration guide with working code: [`listmonk-deployment/FLUTTER_INTEGRATION.md`](./listmonk-deployment/FLUTTER_INTEGRATION.md)

## Features

### What You Get

- ✅ **Full Campaign Management**: Create, schedule, and send email campaigns
- ✅ **Drag-and-Drop Editor**: Built-in visual email template builder
- ✅ **Subscriber Management**: Auto-sync from your CRM (donors, members, attendees)
- ✅ **List Segmentation**: Organize subscribers into targeted lists
- ✅ **Analytics & Tracking**: Real-time opens, clicks, bounces, unsubscribes
- ✅ **Templates**: Reusable email templates with Go templating
- ✅ **Automation**: Scheduled campaigns, recurring emails
- ✅ **A/B Testing**: Test subject lines and content
- ✅ **Import/Export**: Bulk subscriber management
- ✅ **API Access**: Full REST API for programmatic control
- ✅ **Webhooks**: Real-time event notifications
- ✅ **Bounce Handling**: Automatic bounce and complaint management

### Why Listmonk?

- 🚀 **Self-hosted**: Full control over your data
- 💰 **Cost-effective**: ~$5-10/month (vs $300+/month for MailChimp)
- ⚡ **Fast**: Written in Go, handles thousands of subscribers
- 🎨 **Modern UI**: Clean, intuitive interface
- 🔧 **Open Source**: Active community, MIT licensed
- 📊 **Privacy-focused**: GDPR compliant, no third-party tracking

## Documentation

| Document | Description |
|----------|-------------|
| [Deployment README](./listmonk-deployment/README.md) | Deploy to Railway/Render, configure SMTP, custom domains |
| [Flutter Integration](./listmonk-deployment/FLUTTER_INTEGRATION.md) | WebView embedding, API service layer, dashboard widgets |
| [Supabase Integration](./listmonk-deployment/SUPABASE_INTEGRATION.md) | Database schema, sync triggers, Edge Functions |

## Technology Stack

- **Email Platform**: [Listmonk](https://listmonk.app) v3.0.0
- **Deployment**: Railway or Render (Docker container)
- **Database**: Supabase PostgreSQL
- **Email Sending**: Amazon SES
- **Frontend**: Embedded in Flutter via WebView
- **API**: REST API with Flutter service layer

## Cost Breakdown

| Service | Free Tier | Paid Tier (Monthly) |
|---------|-----------|---------------------|
| Railway | $5 credit | ~$5-10 |
| Render | 750 hours | $7 (Starter) |
| Supabase | 500MB DB | $25 (Pro) |
| Amazon SES | 62,000 emails | $0.10/1,000 emails |
| **Total** | **~$0** | **~$10-20** |

Compare to: MailChimp ($299/mo), Constant Contact ($80/mo), Sendinblue ($65/mo)

## Migration from Email Builder

This repository originally contained a React-based email builder using `@usewaypoint/email-builder`. We've pivoted to Listmonk for the following reasons:

| Feature | Old Email Builder | Listmonk |
|---------|------------------|----------|
| Campaign Management | ❌ Manual (CRM) | ✅ Built-in UI |
| Subscriber Management | ❌ CRM only | ✅ Full system |
| Analytics | ❌ None | ✅ Real-time |
| Scheduling | ❌ Manual | ✅ Automated |
| Template Library | ❌ None | ✅ Built-in |
| List Segmentation | ❌ Basic | ✅ Advanced |
| A/B Testing | ❌ None | ✅ Supported |

## Support & Resources

### Official Documentation
- **Listmonk Docs**: https://listmonk.app/docs
- **Listmonk GitHub**: https://github.com/knadh/listmonk
- **Listmonk API**: https://listmonk.app/docs/apis/apis

### Deployment Platforms
- **Railway**: https://docs.railway.app
- **Render**: https://render.com/docs

### Integration Resources
- **Supabase**: https://supabase.com/docs
- **Flutter WebView**: https://pub.dev/packages/webview_flutter
- **Amazon SES**: https://aws.amazon.com/ses

## Getting Help

1. **Deployment Issues**: See [`listmonk-deployment/README.md`](./listmonk-deployment/README.md) → Troubleshooting
2. **Database Sync**: See [`SUPABASE_INTEGRATION.md`](./listmonk-deployment/SUPABASE_INTEGRATION.md) → Troubleshooting
3. **Flutter Integration**: See [`FLUTTER_INTEGRATION.md`](./listmonk-deployment/FLUTTER_INTEGRATION.md) → Troubleshooting
4. **Listmonk Features**: Check [Listmonk Docs](https://listmonk.app/docs) or [GitHub Issues](https://github.com/knadh/listmonk/issues)

## Contributing

This is a private repository for MOYD internal use. Changes should be coordinated with the development team.

## License

Private - MOYD Internal Use Only

---

**Ready to deploy?** Start with [`listmonk-deployment/README.md`](./listmonk-deployment/README.md) 🚀
