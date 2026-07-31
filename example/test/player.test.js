import { browser, driver } from '@wdio/globals'

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
});
