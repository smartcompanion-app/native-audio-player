import { registerPlugin } from '@capacitor/core';

import type { NativeAudioPlayerPlugin } from './definitions';

const NativeAudioPlayer = registerPlugin<NativeAudioPlayerPlugin>(
  'NativeAudioPlayer',
  {
    web: () => import('./web').then(m => new m.NativeAudioPlayerWeb()),
  },
);

export * from './definitions';
export { NativeAudioPlayer };
