# WhitegramArabic NodeFix v8

Arabic localization dylib project for Whitegram 12.9.2 (60).

## Why v7 crashed

v7 wrote translated attributed strings directly into Swift stored properties through the Objective-C runtime. Those fields are owned and laid out by Swift, so changing them with `object_setIvar` can corrupt the object. The corruption appeared when opening Settings, registration and other text-heavy screens.

## v8 translation path

Whitegram/Telegram ItemList rows create their visible titles and descriptions as immutable `NSAttributedString` objects. v8 translates exact dictionary entries during that normal construction step. It does not modify an existing Swift object after creation.

The project intentionally contains no:

- direct Swift ivar mutation
- global `NSBundle` localization hook
- `UITextView` hook
- `_ASDisplayView` private hook

## Build

Run the GitHub Actions workflow or execute:

```bash
chmod +x build.sh
./build.sh
```

The build runs translation coverage checks, runtime-safety checks, generates `GeneratedTranslations.inc`, and produces:

```text
build/WhitegramArabic.dylib
```

Inject the dylib once into a clean Whitegram 12.9.2 IPA. Do not stack it over v7 or keep two `LC_LOAD_DYLIB` entries.
