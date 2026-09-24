# Changelog

## Unreleased

### Enhancements

- Support Elixir 1.15+: the JSON library is configurable with the `:json_library` client option or application setting, defaulting to Elixir's `JSON` on 1.18+ and `Jason` before that
- `:region` accepts any turbopuffer region, as a string (`"aws-us-east-1"`) or an atom (`:aws_us_east_1`), instead of four GCP regions. An unknown region no longer crashes when `:base_url` is also given
- `write/2` supports the rest of the documented write options: `patch_by_filter`, `patch_by_filter_allow_partial`, `delete_by_filter_allow_partial`, `return_affected_ids`, `branch_from_namespace`, `sharding`, and `disable_backpressure`

### Breaking changes

- `write/2`, `query/2`, `text_search/2`, `hybrid_search/2`, and `multi_query/2` raise `ArgumentError` for unknown options instead of dropping them, so a typo like `upsert_conditon:` no longer turns a conditional write into an unconditional one

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
