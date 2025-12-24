<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap');

    body {
      margin: 0;
      padding: 0;
      background: #f5f5f5;
      font-family: 'Montserrat', -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 16px;
      line-height: 1.6;
      color: #273351;
    }

    .wrapper {
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
    }

    .container {
      background: #ffffff;
      border-radius: 12px;
      overflow: hidden;
    }

    .header {
      background: #273351;
      padding: 24px 32px;
      text-align: center;
    }

    .header img {
      max-width: 180px;
    }

    .content {
      padding: 32px;
    }

    .content h1, .content h2, .content h3 {
      color: #273351;
      margin-top: 0;
    }

    .content a {
      color: #32A6DE;
    }

    .btn {
      display: inline-block;
      padding: 14px 28px;
      background: #32A6DE;
      color: #ffffff !important;
      text-decoration: none;
      border-radius: 8px;
      font-weight: 600;
    }

    .footer {
      background: #f8f9fa;
      padding: 24px 32px;
      text-align: center;
      font-size: 13px;
      color: #6c757d;
      border-top: 1px solid #e9ecef;
    }

    .footer a {
      color: #32A6DE;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <img src="{{ RootURL }}/public/static/logo.png" alt="Missouri Young Democrats">
      </div>

      <div class="content">
        {{ template "content" . }}
      </div>

      <div class="footer">
        <p><strong>Missouri Young Democrats</strong><br>Building a Missouri that works for everyone.</p>
        <p>
          <a href="https://moyoungdemocrats.org">Website</a> ·
          <a href="https://instagram.com/moyoungdems">Instagram</a> ·
          <a href="https://twitter.com/moyoungdems">Twitter</a>
        </p>
        <p style="margin-top: 16px; font-size: 12px;">
          <a href="{{ UnsubscribeURL }}">Manage preferences</a> ·
          <a href="{{ MessageURL }}">View in browser</a>
        </p>
        <p style="font-size:11px;color:#999;margin-top:16px;">
          Paid for by Missouri Young Democrats, Dustin Bax, Treasurer
        </p>
      </div>
    </div>
  </div>
  {{ TrackView }}
</body>
</html>
