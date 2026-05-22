/// Sideload build flag to disable services that require entitlements on iOS.
const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);
