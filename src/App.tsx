import { useEffect, useState } from 'react';
import EmailBuilder from './components/EmailBuilder';
import { MessageHandler } from './utils/messageHandler';
import type { EmailDesign } from './types/messages';

function App() {
  const [isReady, setIsReady] = useState(false);
  const messageHandler = MessageHandler.getInstance();

  const handleDesignChange = (design: EmailDesign) => {
    messageHandler.setCurrentDesign(design);
  };

  const handleReady = () => {
    setIsReady(true);

    // Notify parent that builder is ready
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ action: 'ready' }, '*');
    }

    console.log('Email builder is ready');
  };

  return (
    <div className="w-screen h-screen overflow-hidden">
      <EmailBuilder
        onDesignChange={handleDesignChange}
        onReady={handleReady}
      />
    </div>
  );
}

export default App;
