-- RentLedger Sub-Items, Tax Management & Status Constraints Supabase SQL Migration
-- Run this in your Supabase Dashboard -> SQL Editor

-- 1. Create sub_items table
CREATE TABLE IF NOT EXISTS public.sub_items (
    id TEXT PRIMARY KEY,
    parent_item_id TEXT NOT NULL,
    store_id TEXT NOT NULL,
    name TEXT NOT NULL,
    serial_number TEXT,
    sku TEXT,
    status TEXT DEFAULT 'available',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on sub_items
ALTER TABLE public.sub_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage sub_items for their store" ON public.sub_items
    FOR ALL
    USING (auth.uid()::text = store_id)
    WITH CHECK (auth.uid()::text = store_id);

-- 2. Add Tax fields to stores table
ALTER TABLE public.stores
ADD COLUMN IF NOT EXISTS tax_registration_status TEXT DEFAULT 'not_registered',
ADD COLUMN IF NOT EXISTS tax_registration_number TEXT,
ADD COLUMN IF NOT EXISTS show_tax_on_receipts BOOLEAN DEFAULT TRUE;

-- 3. Add Tax & Stock fields to inventory_items table
ALTER TABLE public.inventory_items
ADD COLUMN IF NOT EXISTS tax_type TEXT DEFAULT 'No Tax',
ADD COLUMN IF NOT EXISTS tax_rate NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS is_tax_inclusive BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS tax_effective_date TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS tax_last_verified_date TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS is_tax_confirmed BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS awaiting_inspection_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS maintenance_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS reserved_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS lost_count INT DEFAULT 0;

-- 4. Add Tax Snapshot & Sub-Item fields to leases table
ALTER TABLE public.leases
ADD COLUMN IF NOT EXISTS taxable_amount NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS applied_tax_type TEXT DEFAULT 'No Tax',
ADD COLUMN IF NOT EXISTS applied_tax_rate NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS tax_amount NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS total_amount_with_tax NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS is_tax_inclusive BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS sub_item_ids JSONB DEFAULT '[]'::jsonb;

-- 5. Update leases status check constraint to explicitly permit 'reserved'
ALTER TABLE public.leases DROP CONSTRAINT IF EXISTS leases_status_check;
ALTER TABLE public.leases ADD CONSTRAINT leases_status_check CHECK (status IN ('active', 'upcoming', 'reserved', 'returned', 'cancelled'));
