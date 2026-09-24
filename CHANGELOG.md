# Changelog

## Unreleased

### Enhancements

- Retry requests that fail with 408, 429, or 5xx, or with a connection error, up to `:max_retries` times (default 3) with exponential backoff and jitter from `:retry_delay` (default 500ms), following `retry-after` when turbopuffer sends it. turbopuffer returns 429 when writes outpace indexing

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
