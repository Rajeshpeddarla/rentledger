-- RentLedger Migration 11: Support Ticket System & RLS Policies
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- 1. Create Support Tickets Table
CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    store_name TEXT NOT NULL,
    user_email TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT CHECK (status IN ('open', 'processing', 'closed', 'reopened')) DEFAULT 'open',
    image_urls TEXT[] DEFAULT '{}'::TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_support_tickets_store_id ON public.support_tickets(store_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at ON public.support_tickets(created_at DESC);

-- 3. Enable RLS
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies
DROP POLICY IF EXISTS "Store owners can insert their own support tickets" ON public.support_tickets;
CREATE POLICY "Store owners can insert their own support tickets" ON public.support_tickets
    FOR INSERT WITH CHECK (auth.uid() = store_id OR (auth.jwt()->>'email') = 'varunsai428@gmail.com');

DROP POLICY IF EXISTS "Store owners can view their own support tickets" ON public.support_tickets;
CREATE POLICY "Store owners can view their own support tickets" ON public.support_tickets
    FOR SELECT USING (auth.uid() = store_id OR (auth.jwt()->>'email') = 'varunsai428@gmail.com');

DROP POLICY IF EXISTS "Store owners can update their own support tickets" ON public.support_tickets;
CREATE POLICY "Store owners can update their own support tickets" ON public.support_tickets
    FOR UPDATE USING (auth.uid() = store_id OR (auth.jwt()->>'email') = 'varunsai428@gmail.com');

COMMIT;
