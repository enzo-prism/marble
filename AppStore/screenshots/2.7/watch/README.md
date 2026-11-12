# Watch companion screenshot

`01-active-workout.png` is an unedited native 416 × 496 capture from the paired
watchOS 27.0 46 mm simulator. It shows the phone-connected controller with a
fictional active workout, four confirmed sets, the last exercise and rest control.
The screenshot contains no owner journal data. The Watch source matches commit
`dcdee46`; see `manifest.json` for the exact source/image hashes.

The Watch app controls an iPhone workout. It does not independently collect
wrist heart rate or own a Watch HealthKit workout. This asset is prepared for
the next verified candidate; it has not been uploaded to App Store Connect.

Local ASC preflight passes for `APP_WATCH_SERIES_10` (416 × 496). Pass the PNG
file itself to `asc screenshots validate` and `asc screenshots upload`; this
directory also holds documentation/manifest files that are not image assets.
