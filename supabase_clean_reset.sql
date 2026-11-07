-- RentLedger Fresh Start & Clean Reset Script
-- Run this in your Supabase Dashboard -> SQL Editor to clear all data and start fresh

BEGIN;

-- 1. Drop temporary migration helper tables (NO LONGER NEEDED by the application)
DROP TABLE IF EXISTS public.migration_manual_review_audit CASCADE;
DROP TABLE IF EXISTS public.migration_mapping_registry CASCADE;
DROP TABLE IF EXISTS public.migration_version_history CASCADE;

-- 2. Truncate all application data tables (Restarting identity sequences)
TRUNCATE TABLE
    public.damage_loss_payments,
    public.damage_loss_incidents,
    public.leased_sub_items,
    public.lease_item_units,
    public.lease_items,
    public.leases,
    public.inventory_component_units,
    public.inventory_units,
    public.sub_item_definitions,
    public.inventory_items,
    public.customers,
    public.categories,
    public.discounts,
    public.store_asset_registry,
    public.store_asset_counters,
    public.stores
RESTART IDENTITY CASCADE;

-- 3. Clear all auth users (Clears guest & test user accounts from Supabase Auth)
DELETE FROM auth.users;

COMMIT;
