-- PROPERTY-LOOKUP-01: workspace-wide property search.
--
-- Until now the property list and the property switcher could only browse:
-- keyset pages in `id ASC`, with no way to jump to "Atlas" or "10115". The
-- switcher says so in its own copy, because a client-side filter over the
-- three pages that happen to be loaded is not a search and pretending
-- otherwise would be a lie about coverage.
--
-- This package makes the search real, and does it with the smallest surface
-- that can be true:
--
--   1. **No new read path.** The search is a filter on the existing
--      RLS-governed table read, not a new `security definer` RPC. That is the
--      whole security argument: the rows a search can return are, by
--      construction, exactly the rows `properties_select_property_read`
--      already allows — including the `PH01` entity scope, where a membership
--      is pinned to individual properties. A definer function would have had
--      to re-derive that rule, and a re-derived rule is a rule that can drift.
--   2. **One generated column.** `search_text` is the lower-cased
--      concatenation of the fields the spec names: name, both address lines,
--      zip and city. Generated and stored, so it cannot fall out of sync with
--      the row, and it is not writable by anyone.
--   3. **A trigram index**, so an infix match over a workspace does not
--      degrade into a sequential scan as portfolios grow.
--
-- Deliberately NOT here: ranking, fuzzy/similarity scoring, accent folding and
-- synonyms. A result order the server cannot explain is worse than `id ASC`,
-- and `unaccent` is not immutable, so it cannot back a generated column
-- without a wrapper this package has no reason to introduce. Both are named in
-- `PROPERTY_LIST_V2.md` as open, not as silently missing.

create extension if not exists pg_trgm with schema extensions;

-- Immutable by construction: `lower()` and `||` over the row's own columns.
-- `coalesce` keeps a sparsely filled record searchable by whatever it does
-- have, instead of collapsing the whole column to null.
alter table public.properties
  add column search_text text
  generated always as (
    lower(
      coalesce(name, '') || ' ' ||
      coalesce(address_line1, '') || ' ' ||
      coalesce(address_line2, '') || ' ' ||
      coalesce(zip, '') || ' ' ||
      coalesce(city, '')
    )
  ) stored;

comment on column public.properties.search_text is
  'PROPERTY-LOOKUP-01: lower-cased name/address/zip/city for infix search. '
  'Generated and stored, never written directly. Carries no data the row does '
  'not already carry, so the row''s RLS policy governs it unchanged.';

-- Infix search (`%term%`) cannot use a btree, so the workspace-scoped list
-- would fall back to a scan. The trigram index handles terms of three
-- characters and up; shorter ones still scan, which is why the client asks for
-- at least two characters and the list stays keyset-paginated either way.
create index properties_search_text_trgm_idx
  on public.properties
  using gin (search_text extensions.gin_trgm_ops);
