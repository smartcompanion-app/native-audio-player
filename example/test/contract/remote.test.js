import { browser, expect } from '@wdio/globals'

import { MEDIA_SERVER_PORT } from '../media-server.js'
import {
  clearEvents,
  readState,
  sampleReportedPositions,
  seekToPercent,
  waitForActiveItem,
  waitForControls,
  waitForEvents,
  waitForPlayPause,
} from '../helpers.js'

/**
 * Remote items: an http(s) URL is played from where it is rather than downloaded into the app
 * first. See Item.audioUri in src/definitions.ts.
 *
 * The app's REMOTE button starts the same three items streamed from test/media-server.js, which
 * wdio starts for every platform. Every spec here asks that server what it served as well as
 * what the player reports, since a player that quietly read a local copy would report the same.
 */
describe("Remote items", () => {

  /** The media paths the server was asked for, which is what tells streaming from a local copy. */
  const servedPaths = async () => {
    const response = await fetch(`http://localhost:${MEDIA_SERVER_PORT}/__requests`);
    return response.json();
  };

  const startRemote = async () => {
    await (await browser.$("#start-remote")).click();
    // The controls of the local playlist the app started with are enabled already, and so is
    // its first item -- waiting on those alone passes before the swap has even begun. The click
    // clears the marker synchronously, and the app sets it again once the remote playlist is up.
    await browser.waitUntil(async function () {
      return (await browser.execute(() => document.body.dataset.playlist)) === "remote";
    }, {
      timeout: 60000,
      timeoutMsg: "The remote playlist never finished starting"
    });
    await waitForControls();
    await waitForActiveItem("1");
    await clearEvents();
  };

  it("start a playlist that is streamed, knowing the first item's length", async () => {
    await waitForControls();
    await startRemote();

    const state = await readState();
    expect(state.id).toBe("1");
    expect(state.state).toBe("paused");
    // start() resolves once the item can be played, so its length is already known
    expect(state.duration).toBeGreaterThan(100);

    expect(await servedPaths()).toContain("/media/elephant.mp3");
  });

  it("play while they are being streamed", async () => {
    await waitForControls();
    await startRemote();
    const playPauseButton = await browser.$("#play-pause");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    expect(await waitForEvents(["playing"], "Playing was not reported")).toEqual(["playing"]);

    const positions = await sampleReportedPositions(3);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(positions[positions.length - 1]).toBeGreaterThan(positions[0]);

    await playPauseButton.click();
    await waitForPlayPause("PLAY");
  });

  it("move to another remote item, which is streamed in turn", async () => {
    await waitForControls();
    await startRemote();

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");
    expect(await waitForEvents(["skipped"], "Skip was not reported for next")).toEqual(["skipped"]);

    const state = await readState();
    expect(state.id).toBe("2");
    expect(state.duration).toBeGreaterThan(30);
    expect(state.duration).toBeLessThan(100);

    expect(await servedPaths()).toContain("/media/leopard.mp3");
  });

  it("play out to their end, and rewind like any other item", async () => {
    await waitForControls();
    await startRemote();

    await seekToPercent(98);
    await waitForPlayPause("PAUSE");
    await waitForPlayPause("PLAY");

    const state = await readState();
    expect(state.id).toBe("1");
    expect(state.position).toBeLessThan(1);
    expect(await waitForEvents(["playing", "completed"], "Completed was not reported")).toEqual(["playing", "completed"]);
  });

  // last, because it leaves the player without a playlist
  it("are refused by start() when they cannot be loaded", async () => {
    await waitForControls();

    await (await browser.$("#start-missing")).click();

    let error = "";
    await browser.waitUntil(async function () {
      error = await browser.execute(() => document.querySelector("#start-error").innerText.trim());
      return error !== "";
    }, {
      timeout: 60000,
      timeoutMsg: "start() never answered for a remote item that is not there"
    });

    expect(error).toMatch(/^error/);
    expect(await servedPaths()).toContain("/media/missing.mp3");
    expect((await readState()).state).toBe("stopped");
    expect(await (await browser.$("#play-pause")).isEnabled()).toBe(false);

    // and the local playlist still starts afterwards
    await (await browser.$("#start-stop")).click();
    await waitForControls();
  });
});
