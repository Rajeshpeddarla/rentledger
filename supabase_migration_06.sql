-- RentLedger Migration 06: Per-Item Rate Discounts & Discounted Net Rent
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- 1. Add discounted rate columns to lease_items table
ALTER TABLE public.lease_items
ADD COLUMN IF NOT EXISTS discounted_rate_hourly NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS discounted_rate_daily NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS discounted_rate_weekly NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS discounted_rate_monthly NUMERIC DEFAULT 0.0;

-- 2. Add discounted_net_rent_total column to leases table
ALTER TABLE public.leases
ADD COLUMN IF NOT EXISTS discounted_net_rent_total NUMERIC DEFAULT 0.0;

-- 3. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
