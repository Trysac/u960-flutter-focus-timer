# Contributing

Thanks for helping improve the Dart package `trysac_flutter_focus_timer`.

## Workflow

1. Branch from `main`; never push to `main` directly.
2. `dart pub get --enforce-lockfile` to fetch the packages pinned in `pubspec.lock`.
3. Write a failing test, then the change.
4. `dart run scripts/check.dart` must pass.
5. Update `CHANGELOG.md` under **Unreleased** and the docs the change affects.
6. Open a pull request describing the problem and the solution.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add strict mode to normalize
fix: reject tab-only input
docs: document the thrown errors
```

`feat` bumps the minor version, `fix` the patch version, and a `BREAKING CHANGE:` footer the major
version. Releases are git tags `vMAJOR.MINOR.PATCH`; the release manager sets the top-level
`version:` of `pubspec.yaml`.

## Code of conduct

Be respectful and constructive. Maintainers may close contributions that ignore this guide.
