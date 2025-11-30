import EmailBuilder from './components/EmailBuilder';

function App() {
  const handleReady = () => {
    // Notify parent that builder is ready
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ action: 'ready' }, '*');
    }

    console.log('Email builder is ready');
  };

  return (
    <div className="w-screen h-screen overflow-hidden">
      <EmailBuilder onReady={handleReady} />
    </div>
  );
}

export default App;
