-- RentLedger Restore Lease Quota Trigger & Upgrade Store to Pro Plan
-- Run this in your Supabase Dashboard -> SQL Editor

-- 1. Upgrade your store(s) to Pro Plan
UPDATE public.stores
SET plan_tier = 'pro_monthly'
WHERE plan_tier = 'free';

-- 2. Re-create the PostgreSQL function enforcing 50 leases/month quota ONLY for 'free' stores
CREATE OR REPLACE FUNCTION public.check_free_lease_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_tier TEXT;
    v_monthly_count INT;
BEGIN
    -- Get store plan tier
    SELECT plan_tier INTO v_plan_tier
    FROM public.stores
    WHERE id = NEW.store_id;

    -- If store is Free, check current month lease count
    IF v_plan_tier IS NULL OR v_plan_tier = 'free' THEN
        SELECT COUNT(*) INTO v_monthly_count
        FROM public.leases
        WHERE store_id = NEW.store_id
          AND status != 'cancelled'
          AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NOW());

        IF v_monthly_count >= 50 THEN
            RAISE EXCEPTION 'FREE_LEASE_LIMIT_REACHED: Upgrade to Pro for unlimited monthly leases.'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Re-attach the trigger to public.leases table
DROP TRIGGER IF EXISTS check_free_lease_limit_trigger ON public.leases;

CREATE TRIGGER check_free_lease_limit_trigger
BEFORE INSERT ON public.leases
FOR EACH ROW
EXECUTE FUNCTION public.check_free_lease_limit();
