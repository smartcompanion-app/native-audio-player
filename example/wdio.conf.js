export const config = {
  runner: 'local',
  port: 4723,
  capabilities: [
    {
      platformName: 'Android',
      'appium:app': './android/app/build/outputs/apk/debug/app-debug.apk',
      'appium:automationName': 'UiAutomator2',
      'appium:deviceName': 'Android',
      'appium:appPackage': 'com.example.plugin',
      'appium:appActivity': '.MainActivity',
      'appium:chromedriverAutodownload': true,
    },
  ],
  services: [
    ['appium', {
      args: {
        "allow-insecure": "uiautomator2:chromedriver_autodownload",
      }
    }]
  ],
  specs: [
    './test/**/*.test.js'
  ]
};