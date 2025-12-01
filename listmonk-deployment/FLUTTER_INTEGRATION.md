# Flutter CRM - Listmonk Integration Guide

Complete guide for integrating Listmonk email campaign system into your Flutter CRM application.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup](#setup)
3. [WebView Integration](#webview-integration)
4. [API Service Layer](#api-service-layer)
5. [Admin Dashboard UI](#admin-dashboard-ui)
6. [Subscriber Sync](#subscriber-sync)
7. [Advanced Features](#advanced-features)

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         Flutter CRM Application         │
│                                         │
│  ┌─────────────┐     ┌──────────────┐  │
│  │   WebView   │     │ API Service  │  │
│  │  (iframe)   │     │   Layer      │  │
│  │             │     │              │  │
│  │  Listmonk   │◄────┤  REST API    │  │
│  │     UI      │     │   Calls      │  │
│  └─────────────┘     └──────────────┘  │
│                                         │
└─────────────────────────────────────────┘
           │                    │
           ▼                    ▼
    ┌──────────────┐    ┌──────────────┐
    │   Listmonk   │    │   Supabase   │
    │    Server    │◄───┤   Database   │
    │ (Railway)    │    │              │
    └──────────────┘    └──────────────┘
```

**Data Flow:**
1. **View Campaigns:** WebView displays Listmonk UI
2. **Create Subscribers:** API calls create subscribers programmatically
3. **Sync Data:** Supabase triggers sync subscribers to Listmonk
4. **Send Campaigns:** Listmonk sends via Amazon SES

---

## Setup

### 1. Add Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # WebView for embedding Listmonk
  webview_flutter: ^4.4.0

  # HTTP for API calls
  http: ^1.1.0

  # State management (choose one)
  provider: ^6.1.1
  # OR
  riverpod: ^2.4.9

  # Secure storage for credentials
  flutter_secure_storage: ^9.0.0

  # Environment variables
  flutter_dotenv: ^5.1.0
```

Run:
```bash
flutter pub get
```

### 2. Environment Configuration

Create `.env` file in your Flutter project root:

```env
LISTMONK_URL=https://mail.moyd.app
LISTMONK_API_USER=admin
LISTMONK_API_PASSWORD=your-secure-password
```

Add to `.gitignore`:
```
.env
```

Load in `main.dart`:
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}
```

---

## WebView Integration

### Basic WebView Screen

Create `lib/screens/campaigns/listmonk_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ListmonkScreen extends StatefulWidget {
  const ListmonkScreen({Key? key}) : super(key: key);

  @override
  State<ListmonkScreen> createState() => _ListmonkScreenState();
}

class _ListmonkScreenState extends State<ListmonkScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    final listmonkUrl = dotenv.env['LISTMONK_URL'] ?? 'https://mail.moyd.app';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _isLoading = progress < 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            _showErrorSnackBar('Failed to load page: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(listmonkUrl));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Campaigns'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
```

### Add to Navigation Drawer

In your main drawer/navigation:

```dart
ListTile(
  leading: const Icon(Icons.email),
  title: const Text('Email Campaigns'),
  onTap: () {
    Navigator.pop(context); // Close drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ListmonkScreen(),
      ),
    );
  },
),
```

---

## API Service Layer

### Create Listmonk Service

Create `lib/services/listmonk_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ListmonkService {
  final String baseUrl;
  final String username;
  final String password;

  ListmonkService({
    String? baseUrl,
    String? username,
    String? password,
  })  : baseUrl = baseUrl ?? dotenv.env['LISTMONK_URL'] ?? '',
        username = username ?? dotenv.env['LISTMONK_API_USER'] ?? '',
        password = password ?? dotenv.env['LISTMONK_API_PASSWORD'] ?? '';

  // Generate Basic Auth header
  Map<String, String> get _headers {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
    };
  }

  // ============== CAMPAIGNS ==============

  /// Get all campaigns
  Future<List<Campaign>> getCampaigns() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/campaigns'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['data']['results'];
      return results.map((json) => Campaign.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load campaigns: ${response.statusCode}');
    }
  }

  /// Get single campaign by ID
  Future<Campaign> getCampaign(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/campaigns/$id'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Campaign.fromJson(data['data']);
    } else {
      throw Exception('Failed to load campaign: ${response.statusCode}');
    }
  }

  /// Create new campaign
  Future<Campaign> createCampaign({
    required String name,
    required String subject,
    required List<int> listIds,
    String? body,
    String? templateId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/campaigns'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'subject': subject,
        'lists': listIds,
        'type': 'regular',
        'content_type': 'html',
        'body': body ?? '',
        if (templateId != null) 'template_id': templateId,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Campaign.fromJson(data['data']);
    } else {
      throw Exception('Failed to create campaign: ${response.statusCode}');
    }
  }

  /// Start campaign
  Future<void> startCampaign(int campaignId) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/campaigns/$campaignId/status'),
      headers: _headers,
      body: json.encode({'status': 'running'}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to start campaign: ${response.statusCode}');
    }
  }

  // ============== SUBSCRIBERS ==============

  /// Get all subscribers
  Future<List<Subscriber>> getSubscribers({
    int page = 1,
    int perPage = 100,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/subscribers?page=$page&per_page=$perPage'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['data']['results'];
      return results.map((json) => Subscriber.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load subscribers: ${response.statusCode}');
    }
  }

  /// Create subscriber
  Future<Subscriber> createSubscriber({
    required String email,
    required String name,
    required List<int> listIds,
    Map<String, dynamic>? attributes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/subscribers'),
      headers: _headers,
      body: json.encode({
        'email': email,
        'name': name,
        'status': 'enabled',
        'lists': listIds,
        if (attributes != null) 'attribs': attributes,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Subscriber.fromJson(data['data']);
    } else {
      throw Exception('Failed to create subscriber: ${response.statusCode}');
    }
  }

  /// Update subscriber
  Future<Subscriber> updateSubscriber({
    required int id,
    String? email,
    String? name,
    String? status,
    List<int>? listIds,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/subscribers/$id'),
      headers: _headers,
      body: json.encode({
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (status != null) 'status': status,
        if (listIds != null) 'lists': listIds,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Subscriber.fromJson(data['data']);
    } else {
      throw Exception('Failed to update subscriber: ${response.statusCode}');
    }
  }

  /// Delete subscriber
  Future<void> deleteSubscriber(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/subscribers/$id'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete subscriber: ${response.statusCode}');
    }
  }

  // ============== LISTS ==============

  /// Get all mailing lists
  Future<List<MailingList>> getLists() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/lists'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['data']['results'];
      return results.map((json) => MailingList.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load lists: ${response.statusCode}');
    }
  }

  /// Create mailing list
  Future<MailingList> createList({
    required String name,
    String type = 'public',
    String optin = 'double',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/lists'),
      headers: _headers,
      body: json.encode({
        'name': name,
        'type': type,
        'optin': optin,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return MailingList.fromJson(data['data']);
    } else {
      throw Exception('Failed to create list: ${response.statusCode}');
    }
  }

  // ============== TEMPLATES ==============

  /// Get all templates
  Future<List<Template>> getTemplates() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/templates'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List results = data['data'];
      return results.map((json) => Template.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load templates: ${response.statusCode}');
    }
  }
}

// ============== DATA MODELS ==============

class Campaign {
  final int id;
  final String name;
  final String subject;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Campaign({
    required this.id,
    required this.name,
    required this.subject,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id: json['id'],
      name: json['name'],
      subject: json['subject'],
      status: json['status'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }
}

class Subscriber {
  final int id;
  final String email;
  final String name;
  final String status;
  final Map<String, dynamic>? attributes;

  Subscriber({
    required this.id,
    required this.email,
    required this.name,
    required this.status,
    this.attributes,
  });

  factory Subscriber.fromJson(Map<String, dynamic> json) {
    return Subscriber(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      status: json['status'],
      attributes: json['attribs'],
    );
  }
}

class MailingList {
  final int id;
  final String name;
  final String type;
  final int subscriberCount;

  MailingList({
    required this.id,
    required this.name,
    required this.type,
    required this.subscriberCount,
  });

  factory MailingList.fromJson(Map<String, dynamic> json) {
    return MailingList(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      subscriberCount: json['subscriber_count'] ?? 0,
    );
  }
}

class Template {
  final int id;
  final String name;
  final String body;

  Template({
    required this.id,
    required this.name,
    required this.body,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'],
      name: json['name'],
      body: json['body'],
    );
  }
}
```

---

## Admin Dashboard UI

### Campaign Dashboard Widget

Create `lib/widgets/campaigns/campaign_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import '../../services/listmonk_service.dart';

class CampaignDashboard extends StatefulWidget {
  const CampaignDashboard({Key? key}) : super(key: key);

  @override
  State<CampaignDashboard> createState() => _CampaignDashboardState();
}

class _CampaignDashboardState extends State<CampaignDashboard> {
  final ListmonkService _listmonk = ListmonkService();
  List<Campaign>? _campaigns;
  List<MailingList>? _lists;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final campaigns = await _listmonk.getCampaigns();
      final lists = await _listmonk.getLists();

      setState(() {
        _campaigns = campaigns;
        _lists = lists;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Total Campaigns',
                    value: '${_campaigns?.length ?? 0}',
                    icon: Icons.campaign,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'Mailing Lists',
                    value: '${_lists?.length ?? 0}',
                    icon: Icons.list,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Campaigns
            Text(
              'Recent Campaigns',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_campaigns == null || _campaigns!.isEmpty)
              const Text('No campaigns yet')
            else
              ..._campaigns!.take(5).map((campaign) => Card(
                    child: ListTile(
                      leading: Icon(
                        _getStatusIcon(campaign.status),
                        color: _getStatusColor(campaign.status),
                      ),
                      title: Text(campaign.name),
                      subtitle: Text(campaign.subject),
                      trailing: Chip(
                        label: Text(campaign.status.toUpperCase()),
                        backgroundColor: _getStatusColor(campaign.status).withOpacity(0.2),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'running':
        return Icons.play_circle;
      case 'finished':
        return Icons.check_circle;
      case 'draft':
        return Icons.edit;
      default:
        return Icons.circle;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'finished':
        return Colors.green;
      case 'draft':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Subscriber Sync

### Automatic Sync from CRM to Listmonk

When a new subscriber/donor/member is added in your CRM, automatically sync to Listmonk:

```dart
import 'package:flutter/material.dart';
import '../services/listmonk_service.dart';

class SubscriberSyncService {
  final ListmonkService _listmonk = ListmonkService();

  /// Sync a single subscriber to Listmonk
  Future<void> syncSubscriber({
    required String email,
    required String name,
    int listId = 1, // Default list ID
    Map<String, dynamic>? customAttributes,
  }) async {
    try {
      await _listmonk.createSubscriber(
        email: email,
        name: name,
        listIds: [listId],
        attributes: customAttributes,
      );
      debugPrint('✅ Synced subscriber: $email');
    } catch (e) {
      debugPrint('❌ Failed to sync subscriber: $e');
      // Handle error (log, retry, etc.)
    }
  }

  /// Bulk sync subscribers
  Future<void> bulkSyncSubscribers(List<Map<String, dynamic>> subscribers) async {
    for (final subscriber in subscribers) {
      await syncSubscriber(
        email: subscriber['email'],
        name: subscriber['name'],
        customAttributes: subscriber['attributes'],
      );

      // Add delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}
```

### Usage in Your CRM Forms

```dart
// When creating a new donor/member
final syncService = SubscriberSyncService();

await syncService.syncSubscriber(
  email: donorEmail,
  name: donorName,
  customAttributes: {
    'donor_id': donorId,
    'total_donations': totalDonations,
    'membership_level': membershipLevel,
  },
);
```

---

## Advanced Features

### 1. Campaign Preview

```dart
class CampaignPreviewScreen extends StatelessWidget {
  final int campaignId;

  const CampaignPreviewScreen({Key? key, required this.campaignId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final listmonk = ListmonkService();

    return Scaffold(
      appBar: AppBar(title: const Text('Campaign Preview')),
      body: FutureBuilder<Campaign>(
        future: listmonk.getCampaign(campaignId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const CircularProgressIndicator();

          final campaign = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name: ${campaign.name}'),
                Text('Subject: ${campaign.subject}'),
                Text('Status: ${campaign.status}'),
                // Add HTML preview here
              ],
            ),
          );
        },
      ),
    );
  }
}
```

### 2. Send Test Campaign

```dart
Future<void> sendTestCampaign() async {
  final listmonk = ListmonkService();

  // Create test campaign
  final campaign = await listmonk.createCampaign(
    name: 'Test Campaign',
    subject: 'Test Email',
    listIds: [1],
    body: '<h1>Hello World</h1>',
  );

  // Start immediately
  await listmonk.startCampaign(campaign.id);

  print('Test campaign sent!');
}
```

---

## Testing

### Unit Tests

Create `test/services/listmonk_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moyd_crm/services/listmonk_service.dart';

void main() {
  group('ListmonkService', () {
    test('should get campaigns', () async {
      final service = ListmonkService();
      final campaigns = await service.getCampaigns();
      expect(campaigns, isA<List<Campaign>>());
    });
  });
}
```

---

## Troubleshooting

### WebView not loading
- Check LISTMONK_URL in .env file
- Verify Listmonk server is running
- Check network connectivity

### API calls failing
- Verify credentials in .env
- Check Listmonk server health: `curl https://mail.moyd.app/api/health`
- Enable debug logging: `print(response.body);`

### CORS errors
- Add your Flutter app domain to Listmonk CORS settings
- For local development, use `http://localhost:*` in config.toml

---

## Next Steps

1. Implement subscriber sync triggers
2. Add campaign analytics dashboard
3. Create custom email templates
4. Set up automated campaigns
5. Implement webhook receivers for bounce handling

---

## Support

For issues or questions, refer to:
- Listmonk API docs: https://listmonk.app/docs/apis/apis
- Flutter WebView docs: https://pub.dev/packages/webview_flutter
