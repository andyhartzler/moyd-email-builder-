// Message types for communication with Flutter parent window

export interface FlutterMessage {
  type: 'SAVE_DESIGN' | 'LOAD_DESIGN' | 'GET_DESIGN' | 'RESET_EDITOR';
  design?: string; // JSON string
}

export interface BuilderResponse {
  action: 'save' | 'ready' | 'error';
  html?: string;
  design?: string; // JSON string
  error?: string;
}

export type EmailDesign = {
  body: {
    rows: Array<{
      cells: Array<{
        contents: Array<any>;
      }>;
    }>;
  };
  schemaVersion: number;
};
