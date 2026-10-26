import { browser, expect } from '@wdio/globals'

import {
  readEvents,
  readState,
  selectItem,
  waitForActiveItem,
  waitForControls,
  waitForPlayPause,
} from '../helpers.js'

/**
 * getState(), which reads the player rather than following it. Everything else in the contract
 * is only observable through audioPlayerChange, so an app that mounts late or missed an event
 * has nothing to recover the state from. See getState in src/definitions.ts.
 *
 * Every answer is checked against what the events already said, since the two describe the
 * same player and an app will trust whichever it reads.
 */
describe("The player state", () => {

  it("reports the selected item as paused before anything plays", async () => {
    await waitForControls();
    await selectItem("1");

    const state = await readState();

    expect(state.id).toBe("1");
    expect(state.state).toBe("paused");
    expect(state.position).toBeLessThan(1);
    expect(state.duration).toBeGreaterThan(0);
  });

  it("reports playing while the audio runs, and the position it has reached", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");

    const first = await readState();
    expect(first.state).toBe("playing");
    expect(first.id).toBe("1");

    await browser.pause(1500);
    const later = await readState();
    expect(later.state).toBe("playing");
    expect(later.position).toBeGreaterThan(first.position);
    expect(later.position).toBeLessThan(later.duration);

    await playPauseButton.click();
    await waitForPlayPause("PLAY");

    const paused = await readState();
    expect(paused.state).toBe("paused");
    expect(paused.position).toBeGreaterThanOrEqual(later.position);

    // and it is the paused player's position, which stays put
    await browser.pause(1000);
    expect((await readState()).position).toBe(paused.position);
  });

  it("follows the selected item", async () => {
    await waitForControls();
    await selectItem("1");

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");

    const state = await readState();
    expect(state.id).toBe("2");
    expect(state.state).toBe("paused");
    expect(state.position).toBeLessThan(1);
  });

  it("asking reports nothing, since it changes nothing", async () => {
    await waitForControls();
    await selectItem("1");

    await readState();
    await readState();
    await browser.pause(1000);

    expect(await readEvents()).toEqual([]);
  });

  // last, because it takes the playlist away
  it("reports stopped once the playlist is gone, and the first item again after a start", async () => {
    await waitForControls();
    const startStopButton = await browser.$("#start-stop");

    await startStopButton.click();
    await browser.waitUntil(async function () {
      return (await startStopButton.getText()) === "START"
    }, {
      timeout: 20000,
      timeoutMsg: "The start button did not come back after stopping"
    });

    expect(await readState()).toEqual({ id: "", state: "stopped", position: 0, duration: 0 });

    await startStopButton.click();
    await waitForControls();
    await waitForActiveItem("1");

    const restarted = await readState();
    expect(restarted.id).toBe("1");
    expect(restarted.state).toBe("paused");
  });
});
