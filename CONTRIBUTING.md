# Contributing

## Development Setup

1. Use Xcode/Swift toolchain with Swift 6 support.
2. Clone the repository.
3. Run:

```bash
swift package dump-package
swift test
```

## Pull Request Expectations

- Keep changes focused and reviewable.
- Add or update tests for behavior changes.
- Preserve Core Data context/threading safety:
  - no cross-context `NSManagedObject` passing
  - use `NSManagedObjectID` for cross-boundary communication
- Ensure CI passes.

## Release Notes

User-visible behavior/API changes should be added to `CHANGELOG.md`.
