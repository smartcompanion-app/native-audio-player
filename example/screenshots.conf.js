import { config as e2e } from './wdio.conf.js';

// The README's screenshots, taken by driving the example app the same way the e2e suite does --
// Android only, see screenshots/readme.js. Kept out of wdio.conf.js's specs on purpose: this
// writes files into docs/ rather than asserting anything, and has no business running in CI.
export const config = {
  ...e2e,
  specs: ['./screenshots/readme.js'],
  suites: {},
  // a retry would only take the same pictures again
  specFileRetries: 0,
};
