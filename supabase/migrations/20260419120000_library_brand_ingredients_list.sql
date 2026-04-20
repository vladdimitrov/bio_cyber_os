-- Optional columns for library barcode import (brand + label/ingredients text).
-- If these are missing, the app falls back to inserts without them.

alter table public.ingredients
  add column if not exists brand text,
  add column if not exists ingredients_list text;

alter table public.supplements
  add column if not exists brand text,
  add column if not exists ingredients_list text;

alter table public.medications
  add column if not exists brand text,
  add column if not exists ingredients_list text;
