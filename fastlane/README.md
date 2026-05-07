fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload iOS App Store metadata only

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload iOS App Store preview screenshots only

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload iOS metadata + screenshots, and optionally binary when ipa is provided

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```



### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```



----


## Mac

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload macOS App Store metadata only

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload macOS App Store preview screenshots only

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
