import { browser } from '@wdio/globals'

describe("Native Audio Player Smoke Test", () => {
  it("should show play button and on click it should toggle to pause", async () => {
    await browser.switchContext('WEBVIEW_com.example.plugin');

    const playPauseButton = await browser.$("#play-pause");

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === 'PLAY'
    }, {
      timeout: 5000,
      timeoutMsg: 'Play button did not appear'
    });

    await playPauseButton.click();

    await browser.pause(1000);

    await browser.waitUntil(async function () {
      return (await playPauseButton.getText()) === 'PAUSE'
    }, {
      timeout: 5000,
      timeoutMsg: 'Pause button did not appear'
    });

    await playPauseButton.click();
  });
});
