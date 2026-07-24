const ionicConfig = require('@ionic/swiftlint-config');

// @ionic/swiftlint-config excludes a directory named "example-app", ours is
// "example" -- without this swiftlint lints the example's dependencies and
// build output once they are present locally.
module.exports = {
  ...ionicConfig,
  excluded: [...ionicConfig.excluded, '${PWD}/example/node_modules', '${PWD}/example/ios/build'],
};
