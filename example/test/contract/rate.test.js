import { browser, expect } from '@wdio/globals'

import {
  chooseRate,
  measurePlaybackSpeed,
  readEvents,
  selectItem,
  waitForActiveItem,
  waitForControls,
  waitForPlayPause,
} from '../helpers.js'

/**
 * The playback rate. Spoken word -- audio guides, narration -- is often listened to faster or
 * slower than it was recorded. See setRate in src/definitions.ts.
 *
 * The speed is measured rather than read back: how far the playhead moves between two progress
 * events against how far the clock moved. A rate that is reported but never reaches the audio
 * would pass every check that only asks getRate().
 */
describe("The playback rate", () => {

  const play = async () => {
    const playPauseButton = await browser.$("#play-pause");
    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
  };

  const pause = async () => {
    const playPauseButton = await browser.$("#play-pause");
    await playPauseButton.click();
    await waitForPlayPause("PLAY");
  };

  // left at normal speed for whatever runs next, whatever a spec did to it
  afterEach(async () => {
    await chooseRate(1);
  });

  it("plays at normal speed by default", async () => {
    await waitForControls();
    await selectItem("1");

    await play();
    const speed = await measurePlaybackSpeed();
    await pause();

    expect(speed).toBeGreaterThan(0.8);
    expect(speed).toBeLessThan(1.2);
  });

  it("reports the rate it was given", async () => {
    await waitForControls();

    expect(await chooseRate(1.5)).toBe("1.5");
    expect(await chooseRate(2)).toBe("2");
  });

  it("plays the audio at that rate", async () => {
    await waitForControls();
    await selectItem("1");
    await chooseRate(2);

    await play();
    const speed = await measurePlaybackSpeed();
    await pause();

    expect(speed).toBeGreaterThan(1.6);
    expect(speed).toBeLessThan(2.4);
  });

  it("changes the rate of audio that is already playing", async () => {
    await waitForControls();
    await selectItem("1");

    await play();
    await chooseRate(1.5);
    const speed = await measurePlaybackSpeed();
    await pause();

    expect(speed).toBeGreaterThan(1.2);
    expect(speed).toBeLessThan(1.8);
  });

  // iOS builds a new player for every item, so this is the one most likely to drop it
  it("keeps the rate across a change of item", async () => {
    await waitForControls();
    await selectItem("1");
    await chooseRate(2);

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");

    await play();
    const speed = await measurePlaybackSpeed();
    await pause();

    expect(speed).toBeGreaterThan(1.6);
    expect(speed).toBeLessThan(2.4);
  });

  it("refuses a rate outside 0.5 to 2, and keeps the one it had", async () => {
    await waitForControls();
    await chooseRate(1.5);

    const refused = await chooseRate(3);

    expect(refused).toMatch(/^error/);
    expect(refused).toMatch(/\(rate 1\.5\)$/);
  });

  it("reports nothing, since the playback state does not change", async () => {
    await waitForControls();
    await selectItem("1");

    await chooseRate(2);
    await chooseRate(1);
    await browser.pause(1000);

    expect(await readEvents()).toEqual([]);
  });
});
