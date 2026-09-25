# Changelog

## Unreleased

### Enhancements

- Support Elixir 1.15+: the client uses Elixir's `JSON` on 1.18+ and `Jason` before that, or the module set with `config :turbopuffer, :json_library, ...`
- `:region` accepts any turbopuffer region, as a string (`"aws-us-east-1"`) or an atom (`:aws_us_east_1`), instead of four GCP regions. An unknown region no longer crashes when `:base_url` is also given
- `write/2` supports the rest of the documented write options: `patch_by_filter`, `patch_by_filter_allow_partial`, `delete_by_filter_allow_partial`, `return_affected_ids`, `branch_from_namespace`, `sharding`, and `disable_backpressure`
- `multi_query/2` and `hybrid_search/2` take `rerank_by: :rrf` (or `{:rrf, rank_constant: ..., weights: [...]}`) to have turbopuffer fuse the rankings with reciprocal rank fusion, with `:top_k` limiting the fused results. Without it, `multi_query/2` still returns results one query after another with duplicate ids removed, which the docs now say instead of "rank fusion"
- `query/2` and `hybrid_search/2` take `:vector_attribute` to search a vector attribute not named `vector`, and accept `{:embed, text}` or `{:embed, text, model}` as `:vector` to use turbopuffer's native embedding. `:include_vectors` returns `:vector_attribute`, so it raises with `{:embed, ...}`, whose vector lives in an attribute only the schema names
- Retry requests that fail with 408, 429, or 5xx, or with a connection error, up to `:max_retries` times (default 3) with exponential backoff and jitter from `:retry_delay` (default 500ms), following `retry-after` when turbopuffer sends it. turbopuffer returns 429 when writes outpace indexing

### Breaking changes

- `write/2`, `query/2`, `text_search/2`, `hybrid_search/2`, and `multi_query/2` raise `ArgumentError` for unknown or repeated options instead of dropping them, so a typo like `upsert_conditon:` no longer turns a conditional write into an unconditional one
- `hybrid_search/2` fuses the vector and BM25 rankings with reciprocal rank fusion by default. It returns one ranking of at most `:top_k` results, and each result's `dist` is its RRF score instead of a vector distance or BM25 score. Pass `rerank_by: nil` for the old results: the vector rows, then the BM25 rows, with duplicate ids removed

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
