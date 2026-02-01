export const config = {
  runner: 'local',
  framework: 'mocha',
  port: 4723,
  capabilities: [
    {
      platformName: 'iOS',
      'appium:app': './ios/build/Build/Products/Debug-iphonesimulator/App.app',
      'appium:automationName': 'XCUITest',
      'appium:deviceName': 'iPhone 16',
      'appium:platformVersion': '18.2',
      'appium:bundleId': 'com.example.plugin',
      'appium:useNewWDA': false,
      'appium:showXcodeLog': true,
    },
  ],
  services: [
    ['appium', {
      args: {}
    }]
  ],
  specs: [
    './test/**/*.test.js'
  ]
};
