-- Let one vendor account hold several listings, one per service
-- (for example photography and videography). Each listing is still
-- approved on its own and has its own plan.
drop index if exists public.one_listing_per_vendor;
create index if not exists listings_owner_idx on public.listings(owner);

-- Vendors may delete their own listings that have never been live.
drop policy if exists "vendor deletes own draft" on public.listings;
create policy "vendor deletes own draft" on public.listings for delete
  using (owner = auth.uid() and live is null);
