# kubectlgetall 0.5.0 (2026-02-01)

## Features

- Version flag, `--version` flag can be used to get the current version of the application.
- Zig port. This release has moved the application to zig 0.15.2.
  This has the added advantage of shipping binaries for cross-platform.
  Only Linux x86_64 has being tested locally.

## Misc

- Add release scripts to build the different platform releases.
- Configure changelog to be a zig build command


# Kubectlgetall 0.4.0 (2025-02-09)

### Features

- Groundwork of the logger has being added. (#2)
- Optional formatting on tty print with the use of the rich library. This is an optional external dependency. (#3)
- Set up of mypy to find type issue. Workflows are going to be using mypy in a strict mode. (#4)
- Set up towncrier to create a change log for the project. (#5)
- Add the first version of the GitHub workflow (#6)
- Scan all namespaces can now be done with using `-A / --all-namespaces`. This overrides specifying the namespace flag. (#11)

### Deprecations and Removals

- Remove click as a dependency. This means there is no external dependencies in the project. (#1)
- Switch the positional argument NAMESPACE to a required flag, `-n / --namespace`. (#21)
- As the 2.0 stream of poetry does not have `poetry-export` function anymore the `requirements.txt` has being removed as it would be too much work to ensure it stays up to date.

### Misc

- #7
- update versions for the pre-commit
