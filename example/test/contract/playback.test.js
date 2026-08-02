import { browser, expect } from '@wdio/globals'

import {
  clearEvents,
  readEvents,
  readPosition,
  seekToPercent,
  selectItem,
  waitForActiveItem,
  waitForControls,
  waitForEvents,
  waitForPlayPause,
} from '../helpers.js'

/**
 * The player contract, asserted against whichever implementation this run drives. Nothing
 * in here is platform-specific: it goes through the example app's controls and the
 * audioPlayerChange events the app records, both of which iOS, Android and the web
 * implementation are supposed to produce identically. See src/definitions.ts.
 *
 * Anything that only one platform can do -- the earpiece and speaker routing -- belongs in
 * test/native instead, since the browser picks its own output and reports 'external'.
 */
describe("The audio player contract", () => {

  it("reports playing and then paused as the player is toggled", async () => {
    const playPauseButton = await waitForControls();
    await clearEvents();

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    expect(await waitForEvents(["playing"], "Playing was not reported")).toEqual(["playing"]);

    await playPauseButton.click();
    await waitForPlayPause("PLAY");
    expect(await waitForEvents(["playing", "paused"], "Paused was not reported")).toEqual(["playing", "paused"]);
  });

  it("moves to the next item and back, reporting a skip for each", async () => {
    await waitForControls();
    await waitForActiveItem("1");
    await clearEvents();

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");
    expect(await waitForEvents(["skip"], "Skip was not reported for next")).toEqual(["skip"]);

    await (await browser.$("#prev")).click();
    await waitForActiveItem("1");
    expect(await waitForEvents(["skip", "skip"], "Skip was not reported for previous")).toEqual(["skip", "skip"]);
  });

  // A slider fires input on every step of a drag, so an app that pauses while scrubbing pauses
  // many times over one gesture. None of those change anything on a player that was already
  // stopped, and a state is reported per change rather than per call -- see the behaviour
  // overview in the README. The plugin absorbs the repeats because it is the only place that
  // can: how often an app calls pause is the app's business.
  it("reports a pause only when something was playing", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await browser.execute(() => {
      const slider = document.querySelector("#position");
      [10, 20, 30].forEach((value) => {
        slider.value = value;
        slider.dispatchEvent(new Event("input", { bubbles: true }));
      });
    });

    await browser.pause(2000);
    expect(await readEvents()).toEqual([]);

    // and letting go of the scrubber still starts it, which is what seeking promises
    await browser.execute(() => {
      document.querySelector("#position").dispatchEvent(new Event("change", { bubbles: true }));
    });

    await waitForPlayPause("PAUSE");
    expect(await waitForEvents(["playing"], "Seeking did not resume playback")).toEqual(["playing"]);

    // put it back to a stopped player for whatever runs next
    await playPauseButton.click();
    await waitForPlayPause("PLAY");
  });

  // The list wraps at both ends rather than stopping there, so a player parked on the last
  // item still has somewhere to go. Two clicks cover both ends and land back where they
  // started: back off the front onto the last item, then forward off the end onto the first.
  it("wraps around both ends of the playlist", async () => {
    await waitForControls();
    await selectItem("1");

    await (await browser.$("#prev")).click();
    await waitForActiveItem("3");

    await (await browser.$("#next")).click();
    await waitForActiveItem("1");

    expect(await waitForEvents(["skip", "skip"], "A skip was not reported for each wrap")).toEqual(["skip", "skip"]);
  });

  it("selects an item from the list and reports a skip", async () => {
    await waitForControls();
    await clearEvents();

    await (await browser.$('#select > [data-id="3"]')).click();
    await waitForActiveItem("3");
    expect(await waitForEvents(["skip"], "Skip was not reported for select")).toEqual(["skip"]);
  });

  // A skip selects the new item but does not start it -- see next, previous and select in the
  // behaviour overview in the README. Every other spec here skips from a player that was
  // already paused, so nothing would notice an implementation that carried playback across
  // the item change and left the listener hearing an item they did not ask for.
  it("selects the new item without starting to play it", async () => {
    const playPauseButton = await waitForControls();
    await selectItem("1");

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    await waitForEvents(["playing"], "Playing was not reported");

    // let it get somewhere first, so this is a player being stopped rather than one that
    // had not started yet
    await browser.waitUntil(async function () {
      return (await readPosition()) > 0
    }, {
      timeout: 20000,
      timeoutMsg: "The item never started playing"
    });

    await (await browser.$("#next")).click();
    await waitForActiveItem("2");

    // The contract in events: one skip and nothing else. An implementation that kept playing
    // would either report a playing for the new item or report nothing and keep going.
    await waitForPlayPause("PLAY");
    expect(await readEvents()).toEqual(["playing", "skip"]);

    await browser.waitUntil(async function () {
      return (await readPosition()) < 5
    }, {
      timeout: 20000,
      timeoutMsg: "The new item was not selected at its start"
    });

    // and it stays stopped a moment later rather than running on quietly
    await browser.pause(2000);
    expect(await readEvents()).toEqual(["playing", "skip"]);
    expect(await playPauseButton.getText()).toBe("PLAY");
  });

  // An item used to roll into the next one and be pulled back, which made the first
  // milliseconds of the next item audible. It now stops at the boundary and rewinds itself
  // instead. Seeking close to the end keeps this to a few seconds of playback rather than
  // the length of the track.
  it("stops at the end of an item, rewinds it and stays on it", async () => {
    const playPauseButton = await waitForControls();

    // selected here rather than assumed from whatever the spec before left behind, so this
    // starts from a known item however the suite is filtered or reordered
    await selectItem("1");
    const itemButton1 = await browser.$('#select > [data-id="1"]');

    await seekToPercent(98);

    // seeking resumes, which is the contract for seekTo
    await waitForPlayPause("PAUSE");

    // nothing clicks pause here -- the item runs out and the player parks itself
    await waitForPlayPause("PLAY");

    // the whole point: it stopped rather than moving on to item 2
    expect(await itemButton1.getAttribute("class")).toBe("active");

    await browser.waitUntil(async function () {
      return (await readPosition()) < 5
    }, {
      timeout: 20000,
      timeoutMsg: "The item that played out was not rewound to its start"
    });

    // The contract, rather than the parts of it that happen to show in the controls: an item
    // that plays out reports completed and nothing else. The rewind above is the plugin's
    // doing either way, so without this the event could stop firing unnoticed.
    //
    // Read from the last playing rather than from the top, because the seek above starts
    // from a paused player and the three platforms do not agree on whether pausing an
    // already-paused player is a change worth reporting.
    const states = await readEvents();
    expect(states.slice(states.lastIndexOf("playing"))).toEqual(["playing", "completed"]);

    // and it stays stopped rather than starting itself over. The plugin hands a finished item
    // to the app and lets it decide what comes next, so a repeat is the player getting away
    // from it -- and everything above is true at the moment the item ends whether it repeats
    // or not, which is why this looks again a little later.
    await browser.pause(3000);

    expect(await playPauseButton.getText()).toBe("PLAY");
    const settled = await readEvents();
    expect(settled[settled.length - 1]).toBe("completed");

    // and it is genuinely ready to go again, which is what the rewind is for
    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
  });

  // stop clears the playlist and leaves the player needing a start before it is usable
  // again -- see stop in the behaviour overview in the README. This runs last because it is
  // the one spec that takes the playlist away, and it deliberately does not wait for the
  // player to be paused first: stop is allowed at any time, including mid-playback, which is
  // the state the spec before this one leaves behind.
  it("clears the playlist on stop and is usable again after a start", async () => {
    const playPauseButton = await browser.$("#play-pause");
    const startStopButton = await browser.$("#start-stop");

    await browser.waitUntil(async function () {
      return (await startStopButton.getText()) === "STOP" && (await startStopButton.isEnabled())
    }, {
      timeout: 60000,
      timeoutMsg: "The stop button was never offered"
    });
    await clearEvents();

    await startStopButton.click();

    // a paused is reported whether or not anything was playing, and nothing else follows it
    expect(await waitForEvents(["paused"], "Paused was not reported for stop")).toEqual(["paused"]);

    await browser.waitUntil(async function () {
      return (await startStopButton.getText()) === "START"
    }, {
      timeout: 20000,
      timeoutMsg: "The start button did not come back after stopping"
    });

    // the playlist is gone rather than merely paused, which is what makes a start necessary
    expect(await playPauseButton.isEnabled()).toBe(false);
    expect(await (await browser.$("#select")).getText()).toBe("");

    await browser.pause(2000);
    expect(await readEvents()).toEqual(["paused"]);

    await startStopButton.click();

    // and the player comes back as a fresh one, on the first item and ready to play
    await waitForControls();
    await waitForActiveItem("1");
    await clearEvents();

    await playPauseButton.click();
    await waitForPlayPause("PAUSE");
    expect(await waitForEvents(["playing"], "The restarted player did not play")).toEqual(["playing"]);

    await playPauseButton.click();
    await waitForPlayPause("PLAY");
  });
});
