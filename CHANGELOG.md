# Changelog

## Unreleased

### Enhancements

- `multi_query/2` and `hybrid_search/2` take `rerank_by: :rrf` (or `{:rrf, rank_constant: ..., weights: [...]}`) to have turbopuffer fuse the rankings with reciprocal rank fusion, with `:top_k` limiting the fused results. Without it, `multi_query/2` still returns results one query after another with duplicate ids removed, which the docs now say instead of "rank fusion"

### Breaking changes

- `hybrid_search/2` fuses the vector and BM25 rankings with reciprocal rank fusion by default. It returns one ranking of at most `:top_k` results, and each result's `dist` is its RRF score instead of a vector distance or BM25 score. Pass `rerank_by: nil` for the old results: the vector rows, then the BM25 rows, with duplicate ids removed

## 0.2.0 (2026-02-19)

### Enhancements

- Add `Turbopuffer.list_namespaces/1,2` for enumerating namespaces via `GET /v1/namespaces` with support for `prefix`, `page_size`, and `cursor` pagination (#4)

### Bug fixes

- Fix `include_attributes: :all` causing 422 from the API by normalizing `:all` to `true`. Invalid values now raise `ArgumentError` (#3)

## 0.1.0

- Initial release
