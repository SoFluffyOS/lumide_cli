/// Default configuration used by the Lumide CLI.
library;

const String kDefaultGithubRepo = 'SoFluffyOS/lumide';
const String kLumideAppBundleName = 'Lumide.app';
const String kGithubApiBaseUrl = 'https://api.github.com';
const String kLumideCliVersion = '1.1.0';

/// Lumide's desktop file and icon name on Linux.
const String kLinuxAppId = 'io.sofluffy.lumide';

/// Environment variable that points the CLI at a Lumide installed outside the
/// default location. Used by `install`, `launch`, `doctor` and plain `lumide`.
const String kLumideInstallDirEnvVar = 'LUMIDE_INSTALL_DIR';
