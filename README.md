# MOYD Email Campaign Builder

A standalone email campaign builder using the open-source [@usewaypoint/email-builder](https://github.com/usewaypoint/email-builder) library. This application is deployed at `mail.moyd.app` and embedded via iframe in the main Flutter CRM application.

## Purpose

Provide a drag-and-drop email editor that outputs HTML and design JSON to be saved in Supabase and used for email campaigns.

## Technology Stack

- **Framework:** Vite + React + TypeScript
- **Email Builder:** `@usewaypoint/email-builder` (v0.0.8)
- **Styling:** Tailwind CSS
- **Build Tool:** Vite
- **Deployment:** Netlify
- **Domain:** `mail.moyd.app`

## Project Structure

```
moyd-email-builder/
├── public/
├── src/
│   ├── App.tsx              # Main application component
│   ├── main.tsx             # Entry point
│   ├── index.css            # Global styles
│   ├── types/
│   │   └── messages.ts      # TypeScript type definitions
│   ├── components/
│   │   └── EmailBuilder.tsx # Email builder component
│   └── utils/
│       └── messageHandler.ts # PostMessage communication handler
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.js
└── netlify.toml
```

## Getting Started

### Prerequisites

- Node.js 18+ and npm

### Installation

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Access at http://localhost:3000
```

### Build for Production

```bash
npm run build
```

## Communication Protocol

The email builder communicates with the parent Flutter application via PostMessage API.

### Messages FROM Flutter TO Builder

```javascript
// Save current design
window.postMessage({ type: 'SAVE_DESIGN' }, '*');

// Load existing design
window.postMessage({
  type: 'LOAD_DESIGN',
  design: '{"body":{"rows":[]},"schemaVersion":4}'
}, '*');

// Get current design without HTML export
window.postMessage({ type: 'GET_DESIGN' }, '*');

// Reset to blank
window.postMessage({ type: 'RESET_EDITOR' }, '*');
```

### Messages FROM Builder TO Flutter

```javascript
// Ready notification
{ action: 'ready' }

// Save response (includes both HTML and JSON)
{
  action: 'save',
  html: '<html>...</html>',
  design: '{"body":{"rows":[...]}}'
}

// Error notification
{
  action: 'error',
  error: 'Error message here'
}
```

## Testing Locally

### Test with iframe

Create a test HTML file:

```html
<!DOCTYPE html>
<html>
<head>
  <title>Email Builder Test</title>
</head>
<body>
  <h1>Email Builder Test</h1>
  <button onclick="saveDesign()">Save Design</button>
  <button onclick="loadSample()">Load Sample</button>
  <button onclick="resetEditor()">Reset</button>

  <iframe
    id="builder"
    src="http://localhost:3000"
    style="width: 100%; height: 80vh; border: 1px solid #ccc;"
  ></iframe>

  <script>
    const iframe = document.getElementById('builder');

    // Listen for messages from builder
    window.addEventListener('message', (event) => {
      console.log('Received from builder:', event.data);

      if (event.data.action === 'save') {
        console.log('HTML:', event.data.html);
        console.log('Design JSON:', event.data.design);
      }
    });

    function saveDesign() {
      iframe.contentWindow.postMessage({ type: 'SAVE_DESIGN' }, '*');
    }

    function loadSample() {
      const sampleDesign = {
        body: {
          rows: [
            {
              cells: [
                {
                  contents: [
                    {
                      type: 'text',
                      props: {
                        text: 'Hello from MOYD!'
                      }
                    }
                  ]
                }
              ]
            }
          ]
        },
        schemaVersion: 4
      };

      iframe.contentWindow.postMessage({
        type: 'LOAD_DESIGN',
        design: JSON.stringify(sampleDesign)
      }, '*');
    }

    function resetEditor() {
      iframe.contentWindow.postMessage({ type: 'RESET_EDITOR' }, '*');
    }
  </script>
</body>
</html>
```

## Deployment to Netlify

### Prerequisites

- Netlify account (https://netlify.com)
- Netlify CLI installed: `npm install -g netlify-cli`

### Deploy via CLI

```bash
# Login to Netlify
netlify login

# Initialize the site (first time only)
netlify init

# Deploy to production
netlify deploy --prod
```

### Deploy via Git (Recommended)

1. Push your code to GitHub/GitLab/Bitbucket
2. Go to Netlify dashboard
3. Click "Add new site" → "Import an existing project"
4. Connect your repository
5. Build settings will be auto-detected from `netlify.toml`
6. Click "Deploy site"

### Configure Custom Domain

1. Go to Netlify site settings → Domain management
2. Click "Add custom domain"
3. Enter `mail.moyd.app`
4. Follow DNS configuration instructions

**DNS Configuration (in your domain registrar):**
```
Type: CNAME
Name: mail
Value: <your-site-name>.netlify.app
```

Or use Netlify DNS for easier setup.

## Features

- Drag-and-drop email editor
- Rich text editing with tables and spell check
- Image editor
- Export to HTML
- Save/load design JSON
- Full-screen responsive interface
- PostMessage API for parent communication

## Browser Support

Modern browsers only:
- Chrome
- Firefox
- Safari
- Edge

## Known Limitations

1. **No Authentication:** Security is handled by Flutter parent application
2. **No Database Access:** Builder is stateless - all data flows through Flutter
3. **Mobile:** Works but drag-and-drop may be less intuitive on touch devices

## Troubleshooting

### Builder Not Loading
- Check browser console for errors
- Verify `@usewaypoint/email-builder` package installed correctly
- Ensure React 18+ is being used

### PostMessage Not Working
- Verify iframe src matches deployed URL
- Check browser security settings
- Ensure CORS headers are configured in `netlify.toml`

### Design Not Saving
- Check console for export errors
- Verify design structure matches schema
- Test with simple design first

## Support & Documentation

- **@usewaypoint/email-builder Docs:** https://github.com/usewaypoint/email-builder
- **React Docs:** https://react.dev
- **Vite Docs:** https://vitejs.dev
- **Netlify Docs:** https://docs.netlify.com

## License

Private - MOYD Internal Use Only
