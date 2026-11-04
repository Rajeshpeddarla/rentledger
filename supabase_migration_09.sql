-- RentLedger Migration 09: Clean & Standardized Status Constraints
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- A. Update any legacy/unwanted status values in existing tables
UPDATE public.inventory_units SET status = 'damaged' WHERE status = 'maintenance';
UPDATE public.inventory_component_units SET status = 'damaged' WHERE status = 'maintenance';
UPDATE public.leased_sub_items SET condition_status = 'damaged' WHERE condition_status = 'maintenance';
UPDATE public.lease_item_units SET inspection_status = 'damaged' WHERE inspection_status = 'maintenance';

-- B. Apply Strict Check Constraints
-- 1. inventory_units
ALTER TABLE public.inventory_units DROP CONSTRAINT IF EXISTS inventory_units_status_check;
ALTER TABLE public.inventory_units ADD CONSTRAINT inventory_units_status_check
CHECK (status IN ('available', 'rented', 'reserved', 'damaged', 'in_maintenance', 'lost', 'needed_restock'));

-- 2. inventory_component_units
ALTER TABLE public.inventory_component_units DROP CONSTRAINT IF EXISTS inventory_component_units_status_check;
ALTER TABLE public.inventory_component_units ADD CONSTRAINT inventory_component_units_status_check
CHECK (status IN ('available', 'rented', 'reserved', 'damaged', 'in_maintenance', 'lost', 'needed_restock'));

-- 3. leased_sub_items
ALTER TABLE public.leased_sub_items DROP CONSTRAINT IF EXISTS leased_sub_items_condition_status_check;
ALTER TABLE public.leased_sub_items ADD CONSTRAINT leased_sub_items_condition_status_check
CHECK (condition_status IN ('available', 'rented', 'reserved', 'damaged', 'in_maintenance', 'lost', 'needed_restock'));

-- 4. lease_item_units
ALTER TABLE public.lease_item_units DROP CONSTRAINT IF EXISTS lease_item_units_inspection_status_check;
ALTER TABLE public.lease_item_units ADD CONSTRAINT lease_item_units_inspection_status_check
CHECK (inspection_status IN ('available', 'rented', 'reserved', 'damaged', 'in_maintenance', 'lost', 'needed_restock', 'inspected_good'));

-- 5. leases (Master Order Statuses)
ALTER TABLE public.leases DROP CONSTRAINT IF EXISTS leases_status_check;
ALTER TABLE public.leases ADD CONSTRAINT leases_status_check
CHECK (status IN ('active', 'reserved', 'returned', 'cancelled'));

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
