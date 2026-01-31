import { remote } from 'webdriverio';

const capabilities = {
  platformName: 'Android',
  'appium:automationName': 'UiAutomator2',
  'appium:deviceName': 'Android',
  'appium:appPackage': 'com.example.plugin',
  'appium:appActivity': '.MainActivity',
  'appium:chromedriverAutodownload': true,
};

const wdOpts = {
  hostname: process.env.APPIUM_HOST || 'localhost',
  port: parseInt(process.env.APPIUM_PORT, 10) || 4723,
  logLevel: 'info',
  capabilities,
};

async function runTest() {
  const browser = await remote(wdOpts);

  try { 
    //const contexts = await browser.getContexts();

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
  } finally {
    await browser.pause(1000);
    await browser.deleteSession();
  }
}

runTest().catch(console.error);
