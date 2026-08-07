import { browser, expect } from '@wdio/globals'

import { waitForControls } from '../helpers.js'

/**
 * The audio output, on the two platforms that have one to control. Not a contract spec: the
 * browser picks its own output, gives no way to route to an earpiece, and always reports
 * 'external' -- so there is no shared answer for all three to give.
 *
 * Assumes nothing external is connected. A simulator and an emulator have nothing to connect,
 * but a physical device with headphones or a bluetooth speaker paired reports 'external' and
 * this fails for a reason that has nothing to do with the default.
 */
describe("The audio output", () => {

  /**
   * What the app queried through getAudioOutput() when it started. Written before the controls
   * are enabled, so waitForControls() is enough to know it is there.
   */
  const readAudioOutput = async () => {
    return browser.execute(() => document.querySelector("#audio-output").innerText.trim());
  };

  it("starts on the speaker", async () => {
    await waitForControls();

    // iOS used to start on the earpiece while Android started on the speaker, so the same app
    // was quiet and held-to-ear on one platform and loud on the other. The speaker is the
    // default on both: the earpiece is what setEarpiece() opts into.
    expect(await readAudioOutput()).toBe("SPEAKER");
  });
});
