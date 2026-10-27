import { browser, expect } from '@wdio/globals'

import {
  readEvents,
  readProgress,
  selectItem,
  waitForActiveItem,
  waitForControls,
  waitForPlayPause,
} from '../helpers.js'

/**
 * The progress event, which reports the playhead while the audio runs. The example app used to
 * poll getPosition() for its slider, which every app ended up reimplementing -- it now follows
 * this event instead, and records each one so these specs can count them. See the progress
 * event in src/definitions.ts.
 */
describe("The progress event", () => {

  it("reports the playhead of the playing item while it plays", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");
    const before = (await readProgress()).count;

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");

    const samples = [];
    await browser.waitUntil(async () => {
      const progress = await readProgress();
      if (progress.count > before && progress.position !== samples[samples.length - 1]?.position) {
        samples.push(progress);
      }
      return samples.length >= 3;
    }, { timeout: 15000, interval: 100, timeoutMsg: "The playhead was not reported three times while playing" });

    samples.forEach((sample) => {
      expect(sample.id).toBe("1");
      expect(sample.duration).toBeGreaterThan(sample.position);
    });

    const positions = samples.map((sample) => sample.position);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));

    await playPauseButton.click();
    await waitForPlayPause("PLAY");
  });

  it("reports about twice a second", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");

    const before = (await readProgress()).count;
    await browser.pause(3000);
    const reported = (await readProgress()).count - before;

    await playPauseButton.click();
    await waitForPlayPause("PLAY");

    // six in three seconds by default, with room for timers that do not land exactly and for
    // the webdriver round trips on either side of the pause
    expect(reported).toBeGreaterThanOrEqual(4);
    expect(reported).toBeLessThanOrEqual(8);
  });

  it("stops reporting once paused", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    await browser.pause(1000);

    await playPauseButton.click();
    await waitForPlayPause("PLAY");
    // one that was already on its way across the bridge is allowed to land
    await browser.pause(500);

    const paused = (await readProgress()).count;
    await browser.pause(2000);
    expect((await readProgress()).count).toBe(paused);
  });

  it("reports nothing for an item that is selected but not playing", async () => {
    await waitForControls();
    await selectItem("1");
    const before = (await readProgress()).count;

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");
    await browser.pause(2000);

    expect((await readProgress()).count).toBe(before);
  });

  it("is an event of its own, and adds nothing to audioPlayerChange", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    await browser.pause(2000);
    await playPauseButton.click();
    await waitForPlayPause("PLAY");

    expect(await readEvents()).toEqual(["playing", "paused"]);
  });
});
