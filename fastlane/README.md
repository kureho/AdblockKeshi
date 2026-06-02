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

### ios clone_review_info

```sh
[bundle exec] fastlane ios clone_review_info
```

Clone Review Information from an existing app (StillCam) to AdblockKeshi

### ios set_category

```sh
[bundle exec] fastlane ios set_category
```

Set Primary Category (UTILITIES)

### ios set_price

```sh
[bundle exec] fastlane ios set_price
```

Set Price (¥400 = price point JPY 400)

### ios attach_build

```sh
[bundle exec] fastlane ios attach_build
```

TestFlight build 1.0.0(3) を AppStoreVersion v1.0 に attach

### ios set_territories

```sh
[bundle exec] fastlane ios set_territories
```

Set App Availability to all territories

### ios set_content_rights

```sh
[bundle exec] fastlane ios set_content_rights
```

Set Content Rights Declaration (no third party content)

### ios final_check

```sh
[bundle exec] fastlane ios final_check
```

スクショ + メタデータ最終全件確認

### ios set_secondary_category

```sh
[bundle exec] fastlane ios set_secondary_category
```

Set Secondary Category PRODUCTIVITY

### ios patch_promo_desc_kw

```sh
[bundle exec] fastlane ios patch_promo_desc_kw
```

Patch promotional_text + extended description + keywords

### ios compare_with_other_apps

```sh
[bundle exec] fastlane ios compare_with_other_apps
```

AdblockKeshi vs 他アプリの全メタデータ差分監査

### ios patch_app_name

```sh
[bundle exec] fastlane ios patch_app_name
```

Update App Store name (with ASO suffix) via ASC API

### ios pre_submit_audit

```sh
[bundle exec] fastlane ios pre_submit_audit
```

提出前全項目監査 (feedback_apple_submission_state_audit 4点 + 必須メタデータ)

### ios set_price_raw

```sh
[bundle exec] fastlane ios set_price_raw
```

Set Price ¥400 via raw ASC API (appPriceSchedules)

### ios set_category_raw

```sh
[bundle exec] fastlane ios set_category_raw
```

Set Primary Category UTILITIES via raw ASC API

### ios set_age_rating_raw

```sh
[bundle exec] fastlane ios set_age_rating_raw
```

Set Age Rating (4+) via raw ASC API

### ios create_review_info_adblockkeshi

```sh
[bundle exec] fastlane ios create_review_info_adblockkeshi
```

Create new App Review Information for AdblockKeshi via raw curl

### ios migrate_all_review_info_to_corp

```sh
[bundle exec] fastlane ios migrate_all_review_info_to_corp
```

Migrate all apps' App Review Information to corp (info@kureho.app, Kureho/Support)

### ios list_all_review_info

```sh
[bundle exec] fastlane ios list_all_review_info
```

List all apps' App Review Information (連絡先 一覧)

### ios patch_metadata

```sh
[bundle exec] fastlane ios patch_metadata
```

Patch description/keywords/url metadata directly (full text refresh)

### ios patch_urls

```sh
[bundle exec] fastlane ios patch_urls
```

Patch URLs directly via ASC API (bypass deliver's review_attachment_file bug)

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

### ios verify_terr_v1

```sh
[bundle exec] fastlane ios verify_terr_v1
```

territories check via v1

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
