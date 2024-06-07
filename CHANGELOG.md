# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Calendar Versioning](https://calver.org/) with a `YYYY.MM.patch` scheme.
All dates in this file are given in the [UTC time zone](https://en.wikipedia.org/wiki/Coordinated_Universal_Time).

## v2024.0.0 - 2024-03-26

### Added

- The files which record installer versioning information (previously recorded in files in `~/.local/etc/pkscope-distro`) are now also saved to `/usr/share/planktoscope/installer-config.yml` and `/usr/share/planktoscope/installer-versioning.yml`.

### Changed

- (Breaking change) Changed the default hardware platform from `pscopehat` to `planktoscopehat`.

### Deprecated

- The installer versioning information files at `~/.local/etc/pkscope-distro/installer-config.yml` and `~/.local/etc/pkscope-distro/installer-versioning.yml` should not be used anymore. Instead, the corresponding files in `/usr/share/planktoscope` should be used.

## v2023.9.0 - 2023-12-30

### Changed

- (Breaking change) Changed the default version query from `stable` to `software/stable`.

## v2023.9.0-beta.2 - 2023-12-02

### Added

- Added the initial PlanktoScope software distro installer script, `distro.sh`.
