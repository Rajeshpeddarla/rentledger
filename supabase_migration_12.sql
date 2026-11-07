-- RentLedger Migration 12: Global System Feature Settings & Package Limits
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- 1. Create System Settings Table
CREATE TABLE IF NOT EXISTS public.system_settings (
    key TEXT PRIMARY KEY,
    value BOOLEAN NOT NULL DEFAULT FALSE,
    value_text TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure value_text column exists if table was created previously
ALTER TABLE public.system_settings
ADD COLUMN IF NOT EXISTS value_text TEXT;

-- 2. Insert Default Feature Flags & Package Limits
INSERT INTO public.system_settings (key, value, value_text)
VALUES
    ('enable_coupons', FALSE, NULL),
    ('enable_loyalty', FALSE, NULL),
    ('pro_monthly_price', FALSE, '₹349'),
    ('free_items_limit', FALSE, '10'),
    ('free_monthly_leases_limit', FALSE, '100'),
    ('free_photos_limit', FALSE, '3'),
    ('pro_photos_limit', FALSE, '6')
ON CONFLICT (key) DO NOTHING;

-- 3. Enable RLS & Apply Permissive Policy
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read system settings" ON public.system_settings;
DROP POLICY IF EXISTS "Admin can update system settings" ON public.system_settings;
DROP POLICY IF EXISTS "Admin can insert system settings" ON public.system_settings;
DROP POLICY IF EXISTS "Authenticated users can manage system settings" ON public.system_settings;

CREATE POLICY "Anyone can read system settings" ON public.system_settings
    FOR SELECT USING (TRUE);

CREATE POLICY "Authenticated users can manage system settings" ON public.system_settings
    FOR ALL
    USING (TRUE)
    WITH CHECK (TRUE);

COMMIT;
