## ADDED Requirements

### Requirement: audioproxy_info_url view helper
ActionView SHALL gain an `audioproxy_info_url(source, **opts)` helper that delegates to
`Audioproxy.info_url` with all arguments passed through.

#### Scenario: Helper available in views
- **WHEN** a view calls `audioproxy_info_url("local://previews/track.wav")`
- **THEN** it returns exactly what `Audioproxy.info_url` returns for the same arguments

#### Scenario: Options rejected through the helper
- **WHEN** a view calls `audioproxy_info_url(source, format: :opus)`
- **THEN** an `ArgumentError` is raised, as it is on the module-level entry point

### Requirement: audioproxy_peaks_url view helper
ActionView SHALL gain an `audioproxy_peaks_url(source, **opts)` helper that delegates to
`Audioproxy.peaks_url` with all arguments passed through.

#### Scenario: Helper available in views
- **WHEN** a view calls `audioproxy_peaks_url("local://a.wav", pts: 800)`
- **THEN** it returns exactly what `Audioproxy.peaks_url` returns for the same arguments

#### Scenario: Attachment source through the helper
- **WHEN** a view calls `audioproxy_peaks_url(@recording.audio, pts: 800)`
- **THEN** the attachment resolves to a source string and the peaks URL is built from it
