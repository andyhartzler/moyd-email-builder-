/// <reference types="vite/client" />

import * as ZodLib from 'zod';

declare global {
  namespace Zod {
    export type ZodError = ZodLib.ZodError;
  }
}
