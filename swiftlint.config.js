const ionicConfig = require('@ionic/swiftlint-config');

// @ionic/swiftlint-config excludes a directory named "example-app", ours is
// "example" -- without this swiftlint lints the example's dependencies and
// build output once they are present locally.
module.exports = {
  ...ionicConfig,
  excluded: [
    ...ionicConfig.excluded,
    '${PWD}/example/node_modules',
    '${PWD}/example/ios/build',
    // where a device build puts its derived data -- this is the path example/ios/.gitignore
    // knows about, and it holds both generated sources and the checked-out dependencies
    '${PWD}/example/ios/App/build',
  ],
};
