<!doctype html>
<html>
    <head>
        <title>{{ .Campaign.Subject }}</title>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1">
        <base target="_blank">
        <style>
            body {
                background-color: #f5f7fa;
                font-family: 'Montserrat', 'Helvetica Neue', 'Segoe UI', Helvetica, Arial, sans-serif;
                font-size: 16px;
                line-height: 1.6;
                margin: 0;
                padding: 0;
                color: #273351;
                -webkit-font-smoothing: antialiased;
            }

            pre {
                background: #f8f9fb;
                padding: 16px;
                border-radius: 8px;
                overflow-x: auto;
                font-size: 14px;
            }

            code {
                background: #f8f9fb;
                padding: 2px 6px;
                border-radius: 4px;
                font-size: 14px;
            }

            table {
                width: 100%;
                border-collapse: collapse;
            }

            table td, table th {
                border: 1px solid #e4e8ed;
                padding: 12px;
            }

            .wrap {
                background-color: #ffffff;
                padding: 32px;
                max-width: 520px;
                margin: 0 auto;
                border-radius: 14px;
            }

            .header {
                background-color: #273351;
                padding: 24px 32px;
                margin: -32px -32px 28px -32px;
                border-radius: 14px 14px 0 0;
                text-align: center;
            }

            .header img {
                max-width: 180px;
                height: auto;
            }

            .content {
                /* Campaign body content appears here */
            }

            .button {
                background-color: #32A6DE;
                border-radius: 10px;
                text-decoration: none !important;
                color: #ffffff !important;
                font-weight: 600;
                padding: 14px 32px;
                display: inline-block;
            }

            .button:hover {
                background-color: #2890c4;
            }

            .footer {
                text-align: center;
                font-size: 14px;
                color: #5a6578;
                margin-top: 28px;
                padding-top: 24px;
                border-top: 1px solid #e4e8ed;
            }

            .footer a {
                color: #5a6578;
                text-decoration: none;
            }

            .footer a:hover {
                color: #273351;
                text-decoration: underline;
            }

            .footer-org {
                font-weight: 600;
                color: #273351;
                margin-bottom: 4px;
            }

            .footer-tagline {
                color: #5a6578;
                margin-bottom: 12px;
            }

            .footer-links {
                margin: 16px 0;
            }

            .footer-links a {
                margin: 0 8px;
            }

            .footer-actions {
                margin-top: 16px;
            }

            .footer-actions a {
                color: #8a94a6;
                font-size: 13px;
            }

            .footer-legal {
                font-size: 11px;
                color: #8a94a6;
                margin-top: 16px;
            }

            .gutter {
                padding: 32px;
            }

            img {
                max-width: 100%;
                height: auto;
            }

            a {
                color: #32A6DE;
            }

            a:hover {
                color: #273351;
            }

            h1, h2, h3, h4, h5, h6 {
                color: #273351;
                font-weight: 600;
                margin-top: 0;
            }

            h1 { font-size: 26px; }
            h2 { font-size: 22px; }
            h3 { font-size: 18px; }

            ul, ol {
                padding-left: 24px;
            }

            li {
                margin-bottom: 8px;
            }

            blockquote {
                border-left: 4px solid #32A6DE;
                margin: 16px 0;
                padding: 12px 20px;
                background: #f8f9fb;
                color: #5a6578;
            }

            hr {
                border: none;
                border-top: 1px solid #e4e8ed;
                margin: 24px 0;
            }

            @media screen and (max-width: 600px) {
                .wrap {
                    max-width: 100% !important;
                    border-radius: 0 !important;
                }
                .header {
                    margin: -32px -32px 24px -32px;
                    border-radius: 0 !important;
                }
                .gutter {
                    padding: 16px;
                }
            }
        </style>
    </head>
<body style="background-color: #f5f7fa;">
    <div class="gutter">&nbsp;</div>
    <div class="wrap">
        <!-- Header with Logo -->
        <div class="header">
            {{ if ne LogoURL "" }}
                <a href="https://www.moyoungdemocrats.org/" target="_blank">
                    <img src="{{ LogoURL }}" alt="Missouri Young Democrats" />
                </a>
            {{ end }}
        </div>

        <!-- Campaign Content (REQUIRED) -->
        <div class="content">
            {{ template "content" . }}
        </div>

        <!-- Footer -->
        <div class="footer">
            <p class="footer-org">Missouri Young Democrats</p>
            <p class="footer-tagline">Building a Missouri that works for everyone.</p>

            <p class="footer-links">
                <a href="https://moyoungdemocrats.org">Website</a> ·
                <a href="https://instagram.com/moyoungdems">Instagram</a> ·
                <a href="https://twitter.com/moyoungdems">Twitter</a>
            </p>

            <p class="footer-actions">
                <a href="{{ UnsubscribeURL }}">{{ L.T "email.unsub" }}</a>
                &nbsp;·&nbsp;
                <a href="{{ MessageURL }}">{{ L.T "email.viewInBrowser" }}</a>
            </p>

            <p class="footer-legal">Paid for by Missouri Young Democrats, Dustin Bax, Treasurer</p>
        </div>
    </div>

    <!-- Tracking Pixel (REQUIRED - use exactly once) -->
    <div class="gutter">&nbsp;{{ TrackView }}</div>
</body>
</html>
