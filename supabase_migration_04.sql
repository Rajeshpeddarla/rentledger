-- RentLedger 1-to-Many Lease Order, Line Items & Leased Sub-Items Supabase SQL Migration
-- Run this in your Supabase Dashboard -> SQL Editor

-- 1. Create lease_items table
CREATE TABLE IF NOT EXISTS public.lease_items (
    id TEXT PRIMARY KEY,
    lease_id UUID NOT NULL REFERENCES public.leases(id) ON DELETE CASCADE,
    store_id TEXT NOT NULL,
    item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
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
    item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
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

-- 3. Migration Fix for Existing Databases (Safe Alter & Foreign Key Enforcement)
DO $$
BEGIN
    -- Fix lease_items.item_id type & foreign key constraint
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'lease_items' AND column_name = 'item_id' AND data_type = 'text'
    ) THEN
        ALTER TABLE public.lease_items ALTER COLUMN item_id TYPE UUID USING (item_id::uuid);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_lease_items_inventory_items'
          OR constraint_name = 'lease_items_item_id_fkey'
    ) THEN
        ALTER TABLE public.lease_items
        ADD CONSTRAINT fk_lease_items_inventory_items
        FOREIGN KEY (item_id) REFERENCES public.inventory_items(id) ON DELETE CASCADE;
    END IF;

    -- Fix leased_sub_items.item_id type & foreign key constraint
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'leased_sub_items' AND column_name = 'item_id' AND data_type = 'text'
    ) THEN
        ALTER TABLE public.leased_sub_items ALTER COLUMN item_id TYPE UUID USING (item_id::uuid);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_leased_sub_items_inventory_items'
          OR constraint_name = 'leased_sub_items_item_id_fkey'
    ) THEN
        ALTER TABLE public.leased_sub_items
        ADD CONSTRAINT fk_leased_sub_items_inventory_items
        FOREIGN KEY (item_id) REFERENCES public.inventory_items(id) ON DELETE CASCADE;
    END IF;
END $$;

-- 4. Reload PostgREST Schema Cache
NOTIFY pgrst, 'reload schema';
