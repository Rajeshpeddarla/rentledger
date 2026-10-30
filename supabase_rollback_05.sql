-- RentLedger Complete Guarded Rollback Migration Script
DO $$
DECLARE
    v_post_incidents INT;
    v_post_payments INT;
BEGIN
    -- Abort rollback if operational damage/loss tracking has been used post-migration.
    SELECT COUNT(*) INTO v_post_incidents FROM public.damage_loss_incidents;
    SELECT COUNT(*) INTO v_post_payments FROM public.damage_loss_payments;

    IF v_post_incidents > 0 OR v_post_payments > 0 THEN
        RAISE EXCEPTION 'ROLLBACK_ABORTED: Post-migration incidents (%) or payments (%) exist! Ensure all financial dependencies are resolved or backed up.', v_post_incidents, v_post_payments USING ERRCODE = '55000';
    END IF;
END $$;

BEGIN;

DROP TRIGGER IF EXISTS trg_sync_incident_charge ON public.damage_loss_incidents;
DROP TRIGGER IF EXISTS trg_sync_incident_payments ON public.damage_loss_payments;
DROP FUNCTION IF EXISTS public.fn_sync_damage_incident_payments();
DROP TRIGGER IF EXISTS trg_validate_component_unit_ownership ON public.inventory_component_units;
DROP FUNCTION IF EXISTS public.fn_validate_component_unit_ownership();
DROP FUNCTION IF EXISTS public.generate_store_asset_code(UUID, TEXT, TEXT);

ALTER TABLE public.leased_sub_items
DROP COLUMN IF EXISTS lease_item_unit_id,
DROP COLUMN IF EXISTS inventory_component_unit_id,
DROP COLUMN IF EXISTS is_excluded,
DROP COLUMN IF EXISTS checkout_condition,
DROP COLUMN IF EXISTS checkout_notes,
DROP COLUMN IF EXISTS checked_out_at,
DROP COLUMN IF EXISTS return_condition,
DROP COLUMN IF EXISTS return_notes,
DROP COLUMN IF EXISTS returned_at;

-- Revert units to 'available' safely before dropping assignments
UPDATE public.inventory_units u
SET status = 'available'
FROM public.lease_item_units liu
WHERE liu.inventory_unit_id = u.id AND liu.returned_at IS NULL;

-- Drop tables carefully (respect foreign keys)
DROP TABLE IF EXISTS public.damage_loss_payments CASCADE;
DROP TABLE IF EXISTS public.damage_loss_incidents CASCADE;
DROP TABLE IF EXISTS public.lease_item_units CASCADE;
DROP TABLE IF EXISTS public.inventory_component_units CASCADE;
DROP TABLE IF EXISTS public.inventory_units CASCADE;
DROP TABLE IF EXISTS public.sub_item_definitions CASCADE;
DROP TABLE IF EXISTS public.store_asset_registry CASCADE;
DROP TABLE IF EXISTS public.store_asset_counters CASCADE;
DROP TABLE IF EXISTS public.migration_manual_review_audit CASCADE;
DROP TABLE IF EXISTS public.migration_mapping_registry CASCADE;
DROP TABLE IF EXISTS public.migration_version_history CASCADE;

COMMIT;
