# Changelog

## Unreleased

### Bug fixes

- `Turbopuffer.request_opts` and the `Turbopuffer.Client` request docs list the options Finch takes: `:pool_timeout`, `:receive_timeout`, and `:request_timeout`. They listed `:timeout`, which Finch ignored before 0.22 and rejects with an `ArgumentError` from 0.22 on

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
