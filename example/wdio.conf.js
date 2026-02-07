const isIOS = process.env.APPIUM_PLATFORM === 'ios';

export const config = {
  runner: 'local',
  framework: 'mocha',
  port: 4723,
  capabilities: [    
    isIOS ? {
      platformName: 'iOS',
      'appium:app': './ios/build/Build/Products/Debug-iphonesimulator/App.app',
      'appium:automationName': 'XCUITest',
      'appium:deviceName': 'iPhone 16',
      'appium:platformVersion': '18.2',
      'appium:bundleId': 'app.smartcompanion.audio.plugin.example',
      'appium:useNewWDA': false,
      'appium:showXcodeLog': true,
    } : {
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
        'allow-insecure': '*:chromedriver_autodownload',
      }
    }]
  ],
  specs: [
    './test/**/*.test.js'
  ]
};