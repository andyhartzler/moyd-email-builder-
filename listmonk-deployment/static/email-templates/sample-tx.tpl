<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap');
    body {
      font-family: 'Montserrat', sans-serif;
      color: #273351;
      padding: 20px;
    }
  </style>
</head>
<body>
  <p>Hello {{ .Subscriber.Name }},</p>
  <p>This is a transactional email from Missouri Young Democrats.</p>
  <p style="margin-top: 30px; font-size: 12px; color: #888;">
    Missouri Young Democrats<br>
    Paid for by Missouri Young Democrats, Dustin Bax, Treasurer
  </p>
</body>
</html>
