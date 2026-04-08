# Photo Cleaner

Photo Cleaner is a fast photo triage app for your camera roll: swipe to review, keep, or queue photos for deletion.
It’s designed to help you quickly reduce clutter while staying in control of what gets removed.

## Preview

<p align="center">
  <img src="assets/app_icon.png" alt="Photo Cleaner app icon" width="140" />
</p>

![App screenshot](assets/screenshot.png)

## Features

- **Swipe-based review**: quickly go through recent photos one-by-one.
- **Keep (persistent)**: photos marked as *Keep* are remembered between app launches and appear at the end of the review deck.
- **Deletion queue**: mark photos for deletion, then review the queue before committing.
- **Favorites support**: favorite photos are excluded from the swipe deck.
- **Undo**: revert the last swipe action.

## How it works

- The app loads your **Recents** photos with newest first.
- Photos you **haven’t reviewed yet** always show up first.
- Photos you marked as **Keep** are kept out of the way (moved to the bottom) and are remembered across restarts.
- Photos marked for deletion go into a **queue** so you can review before deleting.

## Getting Started

- This is a **personal project** and it has been tested only on **iOS** so far. Android hasn’t been tested.

- Install Flutter (stable) and the project dependencies:

```bash
flutter pub get
```

- Run on iOS:

```bash
flutter run
```

- Run on your device in **Release** mode:

```bash
flutter run --release -d "<your device name>"
```

### Notes

- **Permissions**: the app needs photo library permissions to load and review pictures, and to delete photos after you confirm.
- **Local Network prompt in Debug**: if you see a local network permission prompt on first launch, it’s typically due to the Debug tooling (Dart VM Service discovery). A Release build shouldn’t require it.

## License

MIT

