import type { FlutterMessage, BuilderResponse, EmailDesign } from '../types/messages';

export class MessageHandler {
  private static instance: MessageHandler;
  private currentDesign: EmailDesign | null = null;

  private constructor() {
    this.setupMessageListener();
  }

  public static getInstance(): MessageHandler {
    if (!MessageHandler.instance) {
      MessageHandler.instance = new MessageHandler();
    }
    return MessageHandler.instance;
  }

  private setupMessageListener() {
    window.addEventListener('message', async (event) => {
      // Security: In production, verify event.origin
      // if (event.origin !== 'https://app.moyd.app') return;

      const message: FlutterMessage = event.data;
      console.log('Received message from parent:', message);

      try {
        await this.handleMessage(message);
      } catch (error) {
        console.error('Error handling message:', error);
        this.postToParent({
          action: 'error',
          error: error instanceof Error ? error.message : 'Unknown error',
        });
      }
    });
  }

  private async handleMessage(message: FlutterMessage) {
    const builder = (window as any).emailBuilder;

    if (!builder) {
      console.warn('Email builder not yet initialized');
      return;
    }

    switch (message.type) {
      case 'SAVE_DESIGN':
        await this.handleSaveDesign(builder);
        break;

      case 'LOAD_DESIGN':
        this.handleLoadDesign(builder, message.design);
        break;

      case 'GET_DESIGN':
        this.handleGetDesign(builder);
        break;

      case 'RESET_EDITOR':
        builder.resetEditor();
        break;

      default:
        console.warn('Unknown message type:', message.type);
    }
  }

  private async handleSaveDesign(builder: any) {
    try {
      const design = builder.getDesign();
      const html = await builder.exportHtml();

      this.currentDesign = design;

      this.postToParent({
        action: 'save',
        html: html,
        design: JSON.stringify(design),
      });

      console.log('Design saved and sent to parent');
    } catch (error) {
      console.error('Failed to save design:', error);
      throw error;
    }
  }

  private handleLoadDesign(builder: any, designJson?: string) {
    if (!designJson) {
      console.warn('No design provided to load');
      return;
    }

    try {
      const design = JSON.parse(designJson);
      builder.loadDesign(design);
      this.currentDesign = design;
      console.log('Design loaded from parent');
    } catch (error) {
      console.error('Failed to parse and load design:', error);
      throw error;
    }
  }

  private handleGetDesign(builder: any) {
    try {
      const design = builder.getDesign();
      this.postToParent({
        action: 'save',
        design: JSON.stringify(design),
      });
    } catch (error) {
      console.error('Failed to get design:', error);
      throw error;
    }
  }

  private postToParent(message: BuilderResponse) {
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(message, '*');
    }
  }

  public setCurrentDesign(design: EmailDesign) {
    this.currentDesign = design;
  }

  public getCurrentDesign(): EmailDesign | null {
    return this.currentDesign;
  }
}
