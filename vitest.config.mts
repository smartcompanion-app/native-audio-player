import { playwright } from '@vitest/browser-playwright';
import { defineConfig } from 'vitest/config';

export default defineConfig({
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
