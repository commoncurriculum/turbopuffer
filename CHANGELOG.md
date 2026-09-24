# Changelog

## Unreleased

### Enhancements

- `query/2` and `hybrid_search/2` take `:vector_attribute` to search a vector attribute not named `vector`, and accept `{:embed, text}` or `{:embed, text, model}` as `:vector` to use turbopuffer's native embedding

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
