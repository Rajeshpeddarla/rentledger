-- RentLedger Migration 10: Automatic 60-Day Inactive Guest Account Cleanup & Foreign Key Cascade Enforcement
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- 1. Ensure Cascading Deletes across all tables referencing stores and auth.users
-- (Guarantees 100% complete data deletion when a store or guest account is deleted)

-- A. Stores -> Auth Users
ALTER TABLE public.stores DROP CONSTRAINT IF EXISTS stores_id_fkey;
ALTER TABLE public.stores
  ADD CONSTRAINT stores_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- B. Leases -> Stores
ALTER TABLE public.leases DROP CONSTRAINT IF EXISTS leases_store_id_fkey;
ALTER TABLE public.leases
  ADD CONSTRAINT leases_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;

-- C. Inventory Items -> Stores
ALTER TABLE public.inventory_items DROP CONSTRAINT IF EXISTS inventory_items_store_id_fkey;
ALTER TABLE public.inventory_items
  ADD CONSTRAINT inventory_items_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;

-- D. Customers -> Stores
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_store_id_fkey;
ALTER TABLE public.customers
  ADD CONSTRAINT customers_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;

-- E. Categories -> Stores
ALTER TABLE public.categories DROP CONSTRAINT IF EXISTS categories_store_id_fkey;
ALTER TABLE public.categories
  ADD CONSTRAINT categories_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;

-- F. Discounts -> Stores
ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS discounts_store_id_fkey;
ALTER TABLE public.discounts
  ADD CONSTRAINT discounts_store_id_fkey
  FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;

-- 2. Enable pg_cron extension if available
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 3. Create function to delete inactive guest accounts older than 60 days
CREATE OR REPLACE FUNCTION public.cleanup_inactive_guest_accounts_60_days()
RETURNS VOID AS $$
BEGIN
    -- Delete anonymous users from auth.users whose last_sign_in_at is older than 60 days
    -- (Cascading foreign keys will automatically delete associated store, inventory, leases, units, components, and receipts)
    DELETE FROM auth.users
    WHERE is_anonymous = TRUE
      AND (
          last_sign_in_at < NOW() - INTERVAL '60 days'
          OR (last_sign_in_at IS NULL AND created_at < NOW() - INTERVAL '60 days')
      );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Schedule the cron job to run every Sunday at 3:00 AM UTC
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Remove existing cron schedule if present to avoid duplicate entries
        PERFORM cron.unschedule('cleanup_inactive_guest_accounts_60_days');
        PERFORM cron.schedule(
            'cleanup_inactive_guest_accounts_60_days',
            '0 3 * * 0', -- Every Sunday at 3:00 AM
            'SELECT public.cleanup_inactive_guest_accounts_60_days();'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron schedule notice: %', SQLERRM;
END $$;

COMMIT;
