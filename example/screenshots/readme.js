import { execFileSync } from 'node:child_process';

import { browser } from '@wdio/globals'

import { waitForControls, waitForPlayPause } from '../test/helpers.js'

/**
 * Takes the README's Android screenshots: the example app, and the media card the system draws
 * for it in the notification shade. Run with `npm run screenshots` against a running emulator.
 *
 * There is no iOS counterpart. The simulator draws no system player anywhere -- the lock screen
 * and Notification Center show no Now Playing widget and Control Center opens empty, although
 * the plugin has published the item -- so docs/ios-player.jpg has to come from a device.
 *
 * The status bar is pinned to a fixed clock and full bars first, so a retake does not differ
 * from the last one only by the time and battery of the machine it was taken on.
 */

const docs = new URL('../../docs/', import.meta.url).pathname;

/** The device appium is driving, so adb reaches the same one. */
const adb = (...args) => execFileSync('adb', ['-s', browser.capabilities.deviceUDID, 'shell', ...args]);

/** Android's System UI demo mode, which holds the status bar still. */
const demo = (command, extras = {}) => {
  const flags = Object.entries(extras).flatMap(([key, value]) => ['-e', key, value]);
  adb('am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', command, ...flags);
};

const pinStatusBar = () => {
  adb('settings', 'put', 'global', 'sysui_demo_allowed', '1');
  demo('enter');
  demo('clock', { hhmm: '0941' });
  demo('battery', { level: '100', plugged: 'false' });
  // `fully` drops the exclamation mark an emulator's wifi carries for having no internet
  demo('network', { wifi: 'show', level: '4', fully: 'true' });
  demo('network', { mobile: 'hide' });
  demo('notifications', { visible: 'false' });
};

describe("The README screenshots", () => {

  before(pinStatusBar);
  after(() => demo('exit'));

  it("show the app and the system's player", async () => {
    await (await waitForControls()).click();
    await waitForPlayPause("PAUSE");

    // The webview context screenshots the page alone, without the status bar around it
    await browser.switchContext("NATIVE_APP");
    await browser.saveScreenshot(`${docs}example-app.png`);

    // the notification shade rather than quick settings: it shows the media card with only
    // the first row of tiles above it
    adb('cmd', 'statusbar', 'expand-notifications');
    await browser.pause(2000);
    // a fresh emulator nags about setting a screen lock, right under the media card. Looking
    // for the button can close the shade, so it is opened again either way.
    const clearAll = await browser.$('android=new UiSelector().text("Clear all")');
    if (await clearAll.isExisting()) {
      await clearAll.click();
    }
    adb('cmd', 'statusbar', 'expand-notifications');
    await browser.pause(2000);
    await browser.saveScreenshot(`${docs}android-player.png`);
    adb('cmd', 'statusbar', 'collapse');
  });
});
