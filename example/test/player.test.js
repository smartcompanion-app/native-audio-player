import { browser, driver, expect } from '@wdio/globals'

/**
 * Wait for the app to finish starting up. The example app writes its media
 * files to the filesystem first and only enables the controls afterwards --
 * a click on a disabled button is silently swallowed, so every test has to
 * wait for this before touching anything.
 */
const waitForControls = async () => {
  const playPauseButton = await browser.$("#play-pause");

  await browser.waitUntil(async function () {
    return (await playPauseButton.getText()) === "PLAY" && (await playPauseButton.isEnabled())
  }, {
    timeout: 60000,
    timeoutMsg: "Controls were not enabled -- the app did not finish starting up"
  });

  return playPauseButton;
};

describe("Native Audio Player Test", () => {

  // Attaching to the webview starts a chromedriver session, so do it once for
  // the whole suite rather than per test.
  before(async () => {
    const contexts = await driver.getContexts();
    const webviewContext = contexts.find(context => context.startsWith("WEBVIEW"));
    await browser.switchContext(webviewContext);
  });

  it("Should show play button and on click it should toggle to pause", async () => {
    const playPauseButton = await waitForControls();

    await playPauseButton.click();

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PAUSE"
    }, {
      timeout: 10000,
      timeoutMsg: "Pause button did not appear"
    });

    await playPauseButton.click();

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PLAY"
    }, {
      timeout: 10000,
      timeoutMsg: "Play button did not reappear"
    });
  });

  it("Should move to next player item and move back to previous item", async () => {
    await waitForControls();

    const nextButton = await browser.$("#next");
    const prevButton = await browser.$("#prev");
    const itemButton1 = await browser.$('#select > [data-id="1"]');
    const itemButton2 = await browser.$('#select > [data-id="2"]');

    await browser.waitUntil(async function () {
      return (await itemButton1.getAttribute("class")) === "active"
    }, {
      timeout: 10000,
      timeoutMsg: "Item 1 button did not become active"
    });

    await nextButton.click();

    await browser.waitUntil(async function () {
      return (await itemButton2.getAttribute("class")) === "active"
    }, {
      timeout: 10000,
      timeoutMsg: "Item 2 button did not become active"
    });

    await prevButton.click();

    await browser.waitUntil(async function () {
      return (await itemButton1.getAttribute("class")) === "active"
    }, {
      timeout: 10000,
      timeoutMsg: "Item 1 button did not become active again"
    });
  });

  // An item used to roll into the next one and be pulled back, which made the first
  // milliseconds of the next item audible. It now stops at the boundary and rewinds
  // itself instead. Seeking close to the end keeps this to a few seconds of playback
  // rather than the length of the track.
  it("Should stop at the end of an item, rewind it and stay on it", async () => {
    const playPauseButton = await waitForControls();
    const itemButton1 = await browser.$('#select > [data-id="1"]');

    await itemButton1.click();

    await browser.waitUntil(async function () {
      return (await itemButton1.getAttribute("class")) === "active"
    }, {
      timeout: 10000,
      timeoutMsg: "Item 1 button did not become active"
    });

    // The slider is a range input, which cannot be dragged through webdriver, and the
    // app only seeks on the change event -- so set the value and fire the events the
    // way a drag would. The input event pauses, the change event seeks and resumes.
    await browser.execute(() => {
      const slider = document.querySelector("#position");
      slider.value = 98;
      slider.dispatchEvent(new Event("input", { bubbles: true }));
      slider.dispatchEvent(new Event("change", { bubbles: true }));
    });

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PAUSE"
    }, {
      timeout: 10000,
      timeoutMsg: "Playback did not resume after seeking close to the end"
    });

    // nothing clicks pause here -- the item runs out and the player parks itself
    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PLAY"
    }, {
      timeout: 30000,
      timeoutMsg: "The item did not pause itself once it played out"
    });

    // the whole point: it stopped rather than moving on to item 2
    expect(await itemButton1.getAttribute("class")).toBe("active");

    await browser.waitUntil(async function () {
      return (await browser.execute(() => Number(document.querySelector("#position").value))) < 5
    }, {
      timeout: 10000,
      timeoutMsg: "The item that played out was not rewound to its start"
    });
  });
});
