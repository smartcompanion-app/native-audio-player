import { spawn } from 'node:child_process';

// Which implementation this run drives. The specs in test/contract are the same for all
// three -- they only touch the example app's DOM, which is what makes them one contract
// suite rather than three that happen to look alike.
const platform = process.env.APPIUM_PLATFORM ?? 'android';
const isIOS = platform === 'ios';
const isBrowser = platform === 'browser';

// vite's own default preview port. The app is served from the build output, the same
// bundle the native runs load out of their app package.
const PREVIEW_PORT = 4173;

let preview;

/** Wait for the preview server to answer, so the session does not open on nothing. */
const waitForPreview = async () => {
  const deadline = Date.now() + 30000;

  while (Date.now() < deadline) {
    try {
      await fetch(`http://localhost:${PREVIEW_PORT}/`);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }

  throw new Error(`The preview server did not come up on port ${PREVIEW_PORT}`);
};

const browserCapability = {
  browserName: 'chrome',
  'goog:chromeOptions': {
    args: [
      '--headless=new',
      // The app seeks by dispatching input and change events, which carry no user gesture,
      // so the resume that seekTo promises would be refused by the autoplay policy. On a
      // real page the drag itself is the gesture; here there is nothing to inherit one from.
      '--autoplay-policy=no-user-gesture-required',
      '--mute-audio',
      // headless chrome on a CI runner has neither
      '--no-sandbox',
      '--disable-dev-shm-usage',
    ],
  },
};

const iosCapability = {
  platformName: 'iOS',
  'appium:app': './ios/build/Build/Products/Debug-iphonesimulator/App.app',
  'appium:automationName': 'XCUITest',
  'appium:deviceName': 'iPhone 16',
  'appium:platformVersion': '18.6',
  'appium:bundleId': 'app.smartcompanion.audio.plugin.example',
  // as on android: the build number never moves, so a rebuilt app has to be forced onto
  // the simulator or the run tests the one before it
  'appium:enforceAppInstall': true,
  'appium:useNewWDA': false,
  'appium:showXcodeLog': true,
  // Fewer retries bound the worst case, and the interval is the only one of
  // these that is actually spent -- it is a sleep between attempts. The
  // timeouts below are upper bounds and stay generous on purpose.
  'appium:wdaStartupRetries': 2,
  'appium:wdaStartupRetryInterval': 30000,
  'appium:wdaLaunchTimeout': 600000,
  'appium:wdaConnectionTimeout': 600000,
  'appium:simulatorStartupTimeout': 600000,
};

const androidCapability = {
  platformName: 'Android',
  'appium:app': './android/app/build/outputs/apk/debug/app-debug.apk',
  'appium:automationName': 'UiAutomator2',
  'appium:deviceName': 'Android',
  'appium:appPackage': 'com.example.plugin',
  'appium:appActivity': '.MainActivity',
  // The version code never changes, so without this appium leaves whatever is already
  // installed in place and the run silently tests the build before the one just made.
  'appium:enforceAppInstall': true,
  // Appium fetches a chromedriver matching the device's webview when the
  // test attaches to it. CI caches the appium home directory so that this
  // usually resolves without hitting the network.
  // Which device to drive when more than one is attached. Appium otherwise takes
  // whichever adb lists first, and a phone plugged in for manual testing usually
  // wins -- physical devices also refuse the helper apk the driver installs
  // (Play Protect rejects it), so the run stalls until the session times out.
  // CI attaches a single emulator and leaves this unset.
  ...(process.env.APPIUM_UDID ? { 'appium:udid': process.env.APPIUM_UDID } : {}),
  'appium:chromedriverAutodownload': true,
  // Without this the chromedriver output is lost, which is exactly what is
  // needed when attaching to the webview fails.
  'appium:showChromedriverLog': true,
  'appium:disableWindowAnimation': true,
};

export const config = {
  runner: 'local',
  framework: 'mocha',
  // Appium's port. A browser run has no appium in it -- webdriverio manages
  // chromedriver itself -- and pointing it at 4723 would leave it waiting on
  // a server nobody started.
  ...(isBrowser ? {} : { port: 4723 }),
  ...(isBrowser ? { baseUrl: `http://localhost:${PREVIEW_PORT}` } : {}),
  // Creating the iOS session includes compiling WebDriverAgent from source,
  // which takes several minutes on a cold runner. This is an upper bound, not
  // a delay -- lowering it saves nothing and just cuts off a slow build.
  connectionRetryTimeout: 600000,
  connectionRetryCount: 3,

  // One spec file at a time. wdio otherwise runs them in parallel, and a native run has a
  // single emulator or simulator to drive -- the second session lands on a device that is
  // still being set up by the first and fails to start at all. The browser run has no such
  // limit to hit, but it only ever gets the one contract suite anyway.
  maxInstances: 1,

  // The boundary spec plays an item out and then waits to see that it stays stopped, which
  // is longer than mocha's own default allows for.
  mochaOpts: {
    timeout: 120000,
  },

  // wdio writes its own logs here, and the appium service inherits the path for
  // the appium server log. CI uploads the whole directory on failure.
  outputDir: './logs',
  reporters: ['spec'],

  // A failed spec is retried once. Real breakage still fails twice; a flaky
  // emulator or a hiccup while attaching chromedriver does not block a PR.
  specFileRetries: 1,
  specFileRetriesDeferred: false,

  capabilities: [isBrowser ? browserCapability : isIOS ? iosCapability : androidCapability],

  services: isBrowser
    ? []
    : [
        ['appium', {
          logPath: './logs',
          args: {
            'allow-insecure': '*:chromedriver_autodownload',
          }
        }]
      ],

  suites: {
    contract: ['./test/contract/**/*.test.js'],
    native: ['./test/native/**/*.test.js'],
  },
  // A browser run has no native side to test, so it only ever gets the contract suite.
  specs: isBrowser ? ['./test/contract/**/*.test.js'] : ['./test/**/*.test.js'],

  onPrepare: async () => {
    if (!isBrowser) {
      return;
    }

    // Serves ./dist, the same build the native runs load out of their app package.
    preview = spawn('npx', ['vite', 'preview', '--port', String(PREVIEW_PORT), '--strictPort'], {
      stdio: 'inherit',
    });
    await waitForPreview();
  },

  onComplete: () => {
    preview?.kill();
  },

  before: async () => {
    if (isBrowser) {
      await browser.url('/');
      return;
    }

    // Attaching to the webview starts a chromedriver session, so do it once for
    // the whole suite rather than per test. A browser session is already in the
    // only context there is.
    const contexts = await browser.getContexts();
    const webviewContext = contexts.find((context) => context.startsWith('WEBVIEW'));
    await browser.switchContext(webviewContext);
  },
};
