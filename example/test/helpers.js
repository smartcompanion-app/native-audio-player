import { browser } from '@wdio/globals'

/**
 * Helpers shared by the contract specs, which run unchanged against iOS, Android and a
 * browser. Everything here goes through the example app's DOM -- that is what lets one spec
 * hold all three implementations to the contract in src/definitions.ts instead of three
 * suites that happen to look alike.
 */

/**
 * Wait for the app to finish starting up. The example app writes its media files to the
 * filesystem first and only enables the controls afterwards -- a click on a disabled button
 * is silently swallowed, so every test has to wait for this before touching anything.
 */
export const waitForControls = async () => {
  const playPauseButton = await browser.$("#play-pause");

  await browser.waitUntil(async function () {
    return (await playPauseButton.getText()) === "PLAY" && (await playPauseButton.isEnabled())
  }, {
    timeout: 60000,
    timeoutMsg: "Controls were not enabled -- the app did not finish starting up"
  });

  return playPauseButton;
};

/**
 * The audioPlayerChange states the app has recorded, in the order the plugin reported them.
 * The app writes them to #events before acting on any of them, so this is the plugin's
 * order rather than the order the app got round to handling.
 */
export const readEvents = async () => {
  const log = await browser.execute(() => document.querySelector("#events").innerHTML.trim());
  return log === "" ? [] : log.split(/\s+/);
};

/**
 * Empties the recorded events so the next assertion is about one step rather than about
 * everything the suite has done so far. The alternative is slicing from the last known
 * state, which stops being readable as soon as a test does more than one thing.
 */
export const clearEvents = async () => {
  await browser.execute(() => {
    document.querySelector("#events").innerHTML = "";
  });
};

/**
 * Wait until exactly this sequence has been reported since the last clearEvents(). Asserting
 * the whole sequence is the point: the contract promises one event per transition, so an
 * extra or missing one is a divergence even when the app's controls end up looking right.
 */
export const waitForEvents = async (expected, message) => {
  let actual = [];

  await browser.waitUntil(async function () {
    actual = await readEvents();
    return actual.length >= expected.length
  }, {
    timeout: 20000,
    timeoutMsg: `${message} -- expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`
  });

  return actual;
};

/** Wait for the play/pause button to settle on a label, which is how the app shows the state. */
export const waitForPlayPause = async (label) => {
  const playPauseButton = await browser.$("#play-pause");

  await browser.waitUntil(async function () {
    return (await playPauseButton.getText()) === label
  }, {
    timeout: 20000,
    timeoutMsg: `The play/pause button did not become ${label}`
  });

  return playPauseButton;
};

/** Wait for an item to become the selected one, which the app marks with the active class. */
export const waitForActiveItem = async (id) => {
  const itemButton = await browser.$(`#select > [data-id="${id}"]`);

  await browser.waitUntil(async function () {
    return (await itemButton.getAttribute("class")) === "active"
  }, {
    timeout: 20000,
    timeoutMsg: `Item ${id} did not become the selected one`
  });

  return itemButton;
};

/** Wait until nothing new has been reported for a while, so the log is quiet before it is read. */
export const settleEvents = async (quietMs = 750) => {
  let seen = (await readEvents()).length;
  let quietSince = Date.now();

  await browser.waitUntil(async function () {
    const now = (await readEvents()).length;

    if (now !== seen) {
      seen = now;
      quietSince = Date.now();
      return false;
    }

    return Date.now() - quietSince >= quietMs
  }, {
    timeout: 20000,
    timeoutMsg: "The player kept reporting events and never settled"
  });
};

/**
 * Select an item to start a test from, and leave the event log empty and quiet.
 *
 * Clicking the item that is already selected is the normal case here -- a spec seeds itself
 * with a known item whatever the one before it left behind -- and then waitForActiveItem
 * returns straight away, because the class it looks for is already set. Whatever the click
 * reports is still on its way, so clearing the log at that point lets it arrive afterwards
 * and be counted as the test's own.
 *
 * Waiting for quiet rather than for an event, because whether re-selecting the current item
 * reports a skip at all is one of the things the platforms do not agree on -- and seeding a
 * test is the wrong place to depend on the answer.
 */
export const selectItem = async (id) => {
  await (await browser.$(`#select > [data-id="${id}"]`)).click();
  await waitForActiveItem(id);
  await settleEvents();
  await clearEvents();
};

/** The position slider, as a percentage of the item. */
export const readPosition = async () => {
  return browser.execute(() => Number(document.querySelector("#position").value));
};

/**
 * The seconds the plugin last reported, which the app parks on the slider -- the slider value
 * itself is a rounded percentage and cannot show them. Written while playing only, so this is
 * NaN until the app has polled at least once.
 */
export const readReportedSeconds = async () => {
  return browser.execute(() => ({
    position: Number(document.querySelector("#position").dataset.position),
    duration: Number(document.querySelector("#position").dataset.duration),
  }));
};

/**
 * Samples what the plugin reports while the audio runs, until `count` different positions have
 * been seen. The app polls twice a second, so this takes about half a second per sample.
 */
export const sampleReportedPositions = async (count) => {
  const positions = [];

  await browser.waitUntil(
    async () => {
      const { position } = await readReportedSeconds();

      if (Number.isFinite(position) && position !== positions[positions.length - 1]) {
        positions.push(position);
      }

      return positions.length >= count;
    },
    { timeout: 15000, interval: 100, timeoutMsg: `Only ${positions.length} of ${count} positions were reported` }
  );

  return positions;
};

/**
 * Drag the position slider to a percentage of the item. The slider is a range input, which
 * cannot be dragged through webdriver, and the app only seeks on the change event -- so set
 * the value and fire the events the way a drag would. The input event pauses, the change
 * event seeks and resumes.
 */
export const seekToPercent = async (percent) => {
  await browser.execute((value) => {
    const slider = document.querySelector("#position");
    slider.value = value;
    slider.dispatchEvent(new Event("input", { bubbles: true }));
    slider.dispatchEvent(new Event("change", { bubbles: true }));
  }, percent);
};
