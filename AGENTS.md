# Posey development

Posey is a Flutter application for Android and iOS. Keep the existing Flutter version, pub lockfile, native projects and ChangeNotifier state model unless the user requests a migration. The root Node scripts are independent research utilities.

- `mobile/lib/app` owns startup, dependency assembly, navigation and cross-feature flows.
- `mobile/lib/features` groups views, view models, models and data access by feature. Views call feature commands rather than plugins or storage directly.
- `mobile/lib/core` contains shared platform adapters and UI primitives; it must not depend on feature views.
- Keep one source of truth for each state. Derive filters and counts. Publish saved settings and favorites only after persistence succeeds.
- Preserve stored keys and formats when refactoring. Credentials belong in system secure storage and must not enter logs, source files or generated artifacts.
- Dispose listeners, native sessions and timers. Ignore stale asynchronous work and prevent duplicate submissions.

Run the checks in `mobile/ARCHITECTURE.md` for application changes. Keep behavioral and boundary tests focused on the changed flow. Use CI for Android/iOS builds when local toolchains are unavailable, and distinguish mocked tests from physical-device validation.
