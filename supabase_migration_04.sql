-- RentLedger 1-to-Many Lease Order, Line Items & Leased Sub-Items Supabase SQL Migration
-- Run this in your Supabase Dashboard -> SQL Editor

-- 1. Create lease_items table
CREATE TABLE IF NOT EXISTS public.lease_items (
    id TEXT PRIMARY KEY,
    lease_id UUID NOT NULL REFERENCES public.leases(id) ON DELETE CASCADE,
    store_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    quantity INT DEFAULT 1,
    rate_hourly NUMERIC DEFAULT 0.0,
    rate_daily NUMERIC DEFAULT 0.0,
    rate_weekly NUMERIC DEFAULT 0.0,
    rate_monthly NUMERIC DEFAULT 0.0,
    deposit_amount NUMERIC DEFAULT 0.0,
    line_calculated_rent NUMERIC DEFAULT 0.0,
    return_status TEXT DEFAULT 'available',
    sub_item_ids JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on lease_items
ALTER TABLE public.lease_items ENABLE ROW LEVEL SECURITY;

-- Drop policy if exists before recreating
DROP POLICY IF EXISTS "Users can manage lease_items for their store" ON public.lease_items;

CREATE POLICY "Users can manage lease_items for their store" ON public.lease_items
    FOR ALL
    USING (auth.uid()::text = store_id)
    WITH CHECK (auth.uid()::text = store_id);

-- 2. Create leased_sub_items table (Individual Sub-Item / Serial Unit Leased Tracker)
CREATE TABLE IF NOT EXISTS public.leased_sub_items (
    id TEXT PRIMARY KEY,
    lease_id UUID NOT NULL REFERENCES public.leases(id) ON DELETE CASCADE,
    lease_item_id TEXT NOT NULL REFERENCES public.lease_items(id) ON DELETE CASCADE,
    sub_item_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    store_id TEXT NOT NULL,
    item_name TEXT NOT NULL,
    serial_number TEXT,
    condition_status TEXT DEFAULT 'available',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on leased_sub_items
ALTER TABLE public.leased_sub_items ENABLE ROW LEVEL SECURITY;

-- Drop policy if exists before recreating
DROP POLICY IF EXISTS "Users can manage leased_sub_items for their store" ON public.leased_sub_items;

CREATE POLICY "Users can manage leased_sub_items for their store" ON public.leased_sub_items
    FOR ALL
    USING (auth.uid()::text = store_id)
    WITH CHECK (auth.uid()::text = store_id);
