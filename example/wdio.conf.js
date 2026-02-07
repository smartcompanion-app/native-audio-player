const isIOS = process.env.APPIUM_PLATFORM === 'ios';

export const config = {
  runner: 'local',
  framework: 'mocha',
  port: 4723,
  connectionRetryTimeout: 300000,
  connectionRetryCount: 3,
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
      'appium:wdaStartupRetries': 4,
      'appium:wdaStartupRetryInterval': 20000,
      'appium:wdaLaunchTimeout': 120000,
      'appium:wdaConnectionTimeout': 240000,
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