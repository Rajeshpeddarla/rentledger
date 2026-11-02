-- RentLedger Migration 06: Per-Item Rate Discounts, Discounted Net Rent & Replacement Cost
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

-- 3. Add replacement_cost column to sub_item_definitions table for Damage/Loss Fee per Piece
ALTER TABLE public.sub_item_definitions
ADD COLUMN IF NOT EXISTS replacement_cost NUMERIC DEFAULT 0.0;

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
