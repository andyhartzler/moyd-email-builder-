import { useEffect, useRef, useState } from 'react';
import EmailEditor from 'react-email-editor';
import type { EmailDesign } from '../types/messages';

interface EmailBuilderProps {
  onReady?: () => void;
}

export default function EmailBuilder({ onReady }: EmailBuilderProps) {
  const emailEditorRef = useRef<any>(null);
  const [isReady, setIsReady] = useState(false);

  const handleReady = () => {
    setIsReady(true);
    if (onReady) {
      onReady();
    }
    console.log('Email builder is ready');
  };

  // Export HTML from current design
  const exportHtml = async (): Promise<string> => {
    return new Promise((resolve, reject) => {
      if (!emailEditorRef.current) {
        reject(new Error('Editor not initialized'));
        return;
      }

      emailEditorRef.current.editor.exportHtml((data: any) => {
        const { html } = data;
        resolve(html);
      });
    });
  };

  // Get current design JSON
  const getDesign = (): Promise<EmailDesign> => {
    return new Promise((resolve, reject) => {
      if (!emailEditorRef.current) {
        reject(new Error('Editor not initialized'));
        return;
      }

      emailEditorRef.current.editor.saveDesign((design: EmailDesign) => {
        resolve(design);
      });
    });
  };

  // Load a design into the builder
  const loadDesign = (design: EmailDesign) => {
    if (!emailEditorRef.current) {
      console.error('Editor not initialized');
      return;
    }

    try {
      emailEditorRef.current.editor.loadDesign(design);
      console.log('Design loaded successfully');
    } catch (error) {
      console.error('Failed to load design:', error);
      postMessageToParent({
        action: 'error',
        error: 'Failed to load design',
      });
    }
  };

  // Reset editor to blank state
  const resetEditor = () => {
    if (!emailEditorRef.current) {
      return;
    }

    try {
      emailEditorRef.current.editor.loadDesign({});
      console.log('Editor reset');
    } catch (error) {
      console.error('Failed to reset editor:', error);
    }
  };

  // Expose methods to parent component
  useEffect(() => {
    if (isReady && window) {
      (window as any).emailBuilder = {
        exportHtml,
        getDesign,
        loadDesign,
        resetEditor,
      };
    }
  }, [isReady]);

  return (
    <div className="w-full h-full">
      {!isReady && (
        <div className="absolute inset-0 flex items-center justify-center bg-white bg-opacity-75 z-50">
          <div className="text-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
            <p className="text-gray-600">Loading email builder...</p>
          </div>
        </div>
      )}
      <EmailEditor
        ref={emailEditorRef}
        onReady={handleReady}
        minHeight="100vh"
        options={{
          displayMode: 'email',
          appearance: {
            theme: 'light',
          },
        }}
      />
    </div>
  );
}

// Helper to post messages to Flutter parent
function postMessageToParent(message: any) {
  if (window.parent && window.parent !== window) {
    window.parent.postMessage(message, '*');
  }
}
