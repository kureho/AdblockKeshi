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

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

[不可逆] App ID + ASC アプリ作成

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build, archive, upload to TestFlight

### ios submit_metadata

```sh
[bundle exec] fastlane ios submit_metadata
```

Submit metadata + screenshots (does NOT submit for review)

### ios audit

```sh
[bundle exec] fastlane ios audit
```

Run 4-point audit (review/availability/price/IAP)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
