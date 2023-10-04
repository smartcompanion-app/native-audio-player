import { WebPlugin } from '@capacitor/core';

import type { NativeAudioPlayerPlugin } from './definitions';

export class NativeAudioPlayerWeb
  extends WebPlugin
  implements NativeAudioPlayerPlugin
{
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
