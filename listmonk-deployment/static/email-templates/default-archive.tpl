<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ .Campaign.Subject }}</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap');
    body {
      margin: 0;
      padding: 0;
      background: #f5f5f5;
      font-family: 'Montserrat', -apple-system, BlinkMacSystemFont, sans-serif;
    }
  </style>
</head>
<body>
  {{ template "content" . }}
</body>
</html>
