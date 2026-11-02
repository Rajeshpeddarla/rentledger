-- RentLedger Migration 07: Scope Asset Code Unique Constraints Per-Item
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- 1. Scope inventory_units asset_code constraint per-item
ALTER TABLE public.inventory_units
DROP CONSTRAINT IF EXISTS unique_unit_asset_code_per_store;

ALTER TABLE public.inventory_units
DROP CONSTRAINT IF EXISTS unique_unit_asset_code_per_item;

ALTER TABLE public.inventory_units
ADD CONSTRAINT unique_unit_asset_code_per_item UNIQUE (store_id, inventory_item_id, asset_code);

-- 2. Scope inventory_component_units asset_code constraint per-item
ALTER TABLE public.inventory_component_units
DROP CONSTRAINT IF EXISTS unique_comp_asset_code_per_store;

ALTER TABLE public.inventory_component_units
DROP CONSTRAINT IF EXISTS unique_comp_asset_code_per_item;

ALTER TABLE public.inventory_component_units
ADD CONSTRAINT unique_comp_asset_code_per_item UNIQUE (store_id, inventory_item_id, asset_code);

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
