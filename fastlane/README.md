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

### ios build_binary

```sh
[bundle exec] fastlane ios build_binary
```

Build iOS App Store IPA

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Build and upload iOS IPA to TestFlight

### ios asc_state

```sh
[bundle exec] fastlane ios asc_state
```

Print iOS App Store Connect edit state

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload iOS App Store metadata only

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit the current iOS version and build for App Review

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload iOS App Store screenshots and preview videos only

### ios upload_preview_videos

```sh
[bundle exec] fastlane ios upload_preview_videos
```

Upload iOS App Store preview videos only

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



### ios preview_assets

```sh
[bundle exec] fastlane ios preview_assets
```



----


## Mac

### mac build_binary

```sh
[bundle exec] fastlane mac build_binary
```

Build macOS App Store PKG

### mac upload_testflight

```sh
[bundle exec] fastlane mac upload_testflight
```

Build and upload macOS PKG to TestFlight

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload macOS App Store metadata only

### mac submit_review

```sh
[bundle exec] fastlane mac submit_review
```

Submit the current macOS version and build for App Review

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload macOS App Store screenshots and preview videos only

### mac upload_preview_videos

```sh
[bundle exec] fastlane mac upload_preview_videos
```

Upload macOS App Store preview videos only

### mac screenshots

```sh
[bundle exec] fastlane mac screenshots
```



### mac preview_assets

```sh
[bundle exec] fastlane mac preview_assets
```



----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
