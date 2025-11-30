import { useEffect, useRef, useState } from 'react';
import { renderEmailBuilder } from 'email-builder-js';
import type { EmailDesign } from '../types/messages';

interface EmailBuilderProps {
  onDesignChange?: (design: EmailDesign) => void;
  onReady?: () => void;
}

export default function EmailBuilder({ onDesignChange, onReady }: EmailBuilderProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const builderRef = useRef<any>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (!containerRef.current || builderRef.current) return;

    try {
      // Initialize the email builder
      builderRef.current = renderEmailBuilder({
        container: containerRef.current,

        // Configuration
        appearance: {
          theme: 'light',
          panels: {
            tools: {
              dock: 'left',
            },
          },
        },

        // Callback when design changes
        onDesignChange: (design) => {
          if (onDesignChange) {
            onDesignChange(design as EmailDesign);
          }
        },

        // Custom tools configuration
        options: {
          features: {
            textEditor: {
              tables: true,
              spellCheck: true,
            },
            imageEditor: true,
          },
        },
      });

      setIsReady(true);
      if (onReady) {
        onReady();
      }

      console.log('Email builder initialized successfully');
    } catch (error) {
      console.error('Failed to initialize email builder:', error);
      postMessageToParent({
        action: 'error',
        error: 'Failed to initialize email builder',
      });
    }

    // Cleanup
    return () => {
      if (builderRef.current) {
        builderRef.current = null;
      }
    };
  }, [onDesignChange, onReady]);

  // Export HTML from current design
  const exportHtml = async (): Promise<string> => {
    if (!builderRef.current) {
      throw new Error('Builder not initialized');
    }

    try {
      const html = await builderRef.current.exportHtml();
      return html;
    } catch (error) {
      console.error('Failed to export HTML:', error);
      throw error;
    }
  };

  // Get current design JSON
  const getDesign = (): EmailDesign | null => {
    if (!builderRef.current) {
      return null;
    }

    try {
      return builderRef.current.getDesign();
    } catch (error) {
      console.error('Failed to get design:', error);
      return null;
    }
  };

  // Load a design into the builder
  const loadDesign = (design: EmailDesign) => {
    if (!builderRef.current) {
      console.error('Builder not initialized');
      return;
    }

    try {
      builderRef.current.loadDesign(design);
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
    if (!builderRef.current) {
      return;
    }

    try {
      builderRef.current.loadDesign({
        body: {
          rows: [],
        },
        schemaVersion: 4,
      });
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
      <div
        ref={containerRef}
        className="w-full h-full"
        style={{ minHeight: '100vh' }}
      />
      {!isReady && (
        <div className="absolute inset-0 flex items-center justify-center bg-white bg-opacity-75">
          <div className="text-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
            <p className="text-gray-600">Loading email builder...</p>
          </div>
        </div>
      )}
    </div>
  );
}

// Helper to post messages to Flutter parent
function postMessageToParent(message: any) {
  if (window.parent && window.parent !== window) {
    window.parent.postMessage(message, '*');
  }
}
