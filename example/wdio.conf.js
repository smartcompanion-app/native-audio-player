const isIOS = process.env.APPIUM_PLATFORM === 'ios';

export const config = {
  runner: 'local',
  framework: 'mocha',
  port: 4723,
  connectionRetryTimeout: 120000,
  connectionRetryCount: 3,

  // wdio writes its own logs here, and the appium service inherits the path for
  // the appium server log. CI uploads the whole directory on failure.
  outputDir: './logs',
  reporters: ['spec'],

  // A failed spec is retried once. Real breakage still fails twice; a flaky
  // emulator or a hiccup while attaching chromedriver does not block a PR.
  specFileRetries: 1,
  specFileRetriesDeferred: false,

  capabilities: [
    isIOS ? {
      platformName: 'iOS',
      'appium:app': './ios/build/Build/Products/Debug-iphonesimulator/App.app',
      'appium:automationName': 'XCUITest',
      'appium:deviceName': 'iPhone 16',
      'appium:platformVersion': '18.6',
      'appium:bundleId': 'app.smartcompanion.audio.plugin.example',
      'appium:useNewWDA': false,
      'appium:showXcodeLog': true,
      'appium:wdaStartupRetries': 2,
      'appium:wdaStartupRetryInterval': 30000,
      'appium:wdaLaunchTimeout': 240000,
      'appium:wdaConnectionTimeout': 240000,
      'appium:simulatorStartupTimeout': 300000,
    } : {
      platformName: 'Android',
      'appium:app': './android/app/build/outputs/apk/debug/app-debug.apk',
      'appium:automationName': 'UiAutomator2',
      'appium:deviceName': 'Android',
      'appium:appPackage': 'com.example.plugin',
      'appium:appActivity': '.MainActivity',
      // Appium fetches a chromedriver matching the device's webview when the
      // test attaches to it. CI caches the appium home directory so that this
      // usually resolves without hitting the network.
      'appium:chromedriverAutodownload': true,
      // Without this the chromedriver output is lost, which is exactly what is
      // needed when attaching to the webview fails.
      'appium:showChromedriverLog': true,
      'appium:disableWindowAnimation': true,
    },
  ],
  services: [
    ['appium', {
      logPath: './logs',
      args: {
        'allow-insecure': '*:chromedriver_autodownload',
      }
    }]
  ],
  specs: [
    './test/**/*.test.js'
  ]
};
