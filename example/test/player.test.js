import assert from "node:assert";
import { browser, driver } from '@wdio/globals'

describe("Native Audio Player Test", () => {

  beforeEach(async () => {
    const contexts = await driver.getContexts();
    const webviewContext = contexts.find(context => context.startsWith("WEBVIEW"));
    await browser.switchContext(webviewContext);
  });

  it("Should show play button and on click it should toggle to pause", async () => {
    const playPauseButton = await browser.$("#play-pause");

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PLAY"
    }, {
      timeout: 5000,
      timeoutMsg: "Play button did not appear"
    });

    await playPauseButton.click();

    await browser.pause(1000);

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === "PAUSE"
    }, {
      timeout: 5000,
      timeoutMsg: "Pause button did not appear"
    });

    await playPauseButton.click();
  });

  it("Should move to next player item and move back to previous item", async () => {
    const nextButton = await browser.$("#next");
    const prevButton = await browser.$("#prev");
    const itemButton1 = await browser.$('#select > [data-id="1"]');
    const itemButton2 = await browser.$('#select > [data-id="2"]');

    assert.strictEqual("active", await itemButton1.getAttribute("class"));

    await nextButton.click();

    assert.strictEqual("active", await itemButton2.getAttribute("class"));

    await prevButton.click();

    assert.strictEqual("active", await itemButton1.getAttribute("class"));
  });    
});
