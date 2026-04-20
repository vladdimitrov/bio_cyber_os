-- Barcode / GTIN storage for library scanning (ingredients, supplements, medications).
-- PostgREST picks up new columns immediately after this runs on the Supabase project.

alter table public.ingredients
  add column if not exists barcode text;

alter table public.supplements
  add column if not exists barcode text;

alter table public.medications
  add column if not exists barcode text;

-- Exact-match barcode lookups during scan flows (partial: only rows with a code)
create index if not exists idx_ingredients_barcode
  on public.ingredients (barcode)
  where barcode is not null;

create index if not exists idx_supplements_barcode
  on public.supplements (barcode)
  where barcode is not null;

create index if not exists idx_medications_barcode
  on public.medications (barcode)
  where barcode is not null;
