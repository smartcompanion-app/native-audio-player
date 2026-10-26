import { playwright } from '@vitest/browser-playwright';
import type { Plugin } from 'vite';
import { defineConfig } from 'vitest/config';

import { createAudioBytes } from './src/test/audio-fixture';

/**
 * Audio over HTTP, for the remote item tests. A blob URL never touches the network, so it cannot
 * stand in for an item the player streams. `/__audio/<seconds>.wav` is a silent WAV of that
 * length, anything else under `/__audio/` is a 404, and `/__audio/requests` lists what was asked
 * for so a test can tell the audio was actually fetched.
 */
const remoteAudio = (): Plugin => {
  const requests: string[] = [];

  return {
    name: 'remote-audio',
    configureServer(server) {
      server.middlewares.use('/__audio/', (request, response) => {
        const path = (request.url ?? '').split('?')[0];

        if (path === '/requests') {
          response.setHeader('Content-Type', 'application/json');
          response.end(JSON.stringify(requests));
          return;
        }

        requests.push(path);
        const match = /^\/(\d+(?:\.\d+)?)\.wav$/.exec(path);

        if (!match) {
          response.statusCode = 404;
          response.end();
          return;
        }

        response.setHeader('Content-Type', 'audio/wav');
        response.end(Buffer.from(createAudioBytes(Number(match[1]))));
      });
    },
  };
};

export default defineConfig({
  plugins: [remoteAudio()],
  test: {
    include: ['src/**/*.test.ts'],
    browser: {
      enabled: true,
      headless: true,
      provider: playwright({
        launchOptions: {
          // The suite drives playback directly rather than through clicks, so without this
          // every play() would reject on the autoplay policy. Real apps get their gesture
          // from the user; the tests would only be asserting Chrome's policy.
          args: ['--autoplay-policy=no-user-gesture-required'],
        },
      }),
      instances: [{ browser: 'chromium' }],
    },
  },
});
