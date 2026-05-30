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

### ios test_connection

```sh
[bundle exec] fastlane ios test_connection
```

ASC API key で接続テスト（既存アプリ一覧取得・副作用なし）

### ios register_bundle_ids

```sh
[bundle exec] fastlane ios register_bundle_ids
```

[不可逆] bundle id 登録 (ASC API 経由・2FA不要)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build, archive, upload to TestFlight

### ios submit_metadata

```sh
[bundle exec] fastlane ios submit_metadata
```

Submit text metadata only (no screenshots, no binary, no review submission)

### ios submit_screenshots

```sh
[bundle exec] fastlane ios submit_screenshots
```

Submit screenshots only (after generation)

### ios audit

```sh
[bundle exec] fastlane ios audit
```

Run 4-point audit (review/availability/price/IAP)

### ios list_builds

```sh
[bundle exec] fastlane ios list_builds
```

List TestFlight builds for the app

### ios check_state

```sh
[bundle exec] fastlane ios check_state
```

Check current ASC state (versions / localizations / metadata)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
