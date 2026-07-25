# Marble App Store release assets

This directory is the tracked source of truth for Marble's App Store text and
screenshot plans. Generated PNGs and signed archives stay out of Git.

- `metadata/app-info/en-US.json`: app-level localization
- `metadata/version/<version>/en-US.json`: version-level localization
- `screenshots/<version>/manifest.json`: ordered screenshot story and captions
- `review/<version>.md`: reviewer notes and deterministic test path

Before any remote write, validate metadata with `asc metadata validate`, validate
the release with `asc validate`, and run the review submission dry-run. Uploads,
metadata pushes, version creation, and review submission require explicit approval.

Raw UI-test captures can be turned into benefit-led App Store artwork without
changing their device-master dimensions:

```sh
swift scripts/compose_app_store_screenshots.swift \
  AppStore/screenshots/2.2/manifest.json RAW_DIRECTORY OUTPUT_DIRECTORY
```

The compositor writes opaque RGB PNGs, uses only truthful copy from the tracked
manifest, and refuses to overwrite an existing final image.
