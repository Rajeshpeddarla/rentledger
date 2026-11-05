-- RentLedger Migration 08: Single-Request Transaction Stored Procedures for Create & Return Settle Lease
-- Run this in your Supabase Dashboard -> SQL Editor

BEGIN;

-- ============================================================================
-- 1. STORED PROCEDURE: CREATE / RESERVE LEASE TRANSACTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_lease_transaction(p_lease JSONB)
RETURNS JSONB AS $$
DECLARE
    v_lease_id UUID;
    v_store_id UUID;
    v_item_id UUID;
    v_customer_id UUID;
    v_status TEXT;
    v_unit_status TEXT;
    v_comp_status TEXT;
    v_line_rec JSONB;
    v_sub_rec JSONB;
    v_line_id TEXT;
    v_sub_id TEXT;
    v_unit_pk UUID;
    v_comp_unit_id UUID;
    v_unit_id UUID;
    v_start_time TIMESTAMPTZ;
BEGIN
    v_lease_id := (p_lease->>'id')::UUID;
    v_store_id := (p_lease->>'store_id')::UUID;
    v_item_id := (p_lease->>'item_id')::UUID;
    v_customer_id := (p_lease->>'customer_id')::UUID;
    v_status := COALESCE(p_lease->>'status', 'active');
    v_start_time := COALESCE((p_lease->>'start_time')::TIMESTAMPTZ, NOW());

    -- Determine target physical status ('reserved' for future bookings, 'rented' for immediate active checkouts)
    IF v_status = 'reserved' THEN
        v_unit_status := 'reserved';
        v_comp_status := 'reserved';
    ELSE
        v_unit_status := 'rented';
        v_comp_status := 'rented';
    END IF;

    -- A. Insert or Update Master Lease Record
    INSERT INTO public.leases (
        id, store_id, item_id, customer_id, start_time, expected_end_time,
        before_photo_urls, deposit_expected, deposit_paid, advance_rent_paid,
        deposit_payment_type, billing_unit_used, calculated_rent, discount_amount,
        damage_or_late_fee, net_rent_total, final_settlement_balance, return_notes,
        status, quantity, taxable_amount, applied_tax_type, applied_tax_rate,
        tax_amount, total_amount_with_tax, is_tax_inclusive, discounted_net_rent_total,
        created_at, updated_at
    ) VALUES (
        v_lease_id, v_store_id, v_item_id, v_customer_id, v_start_time,
        COALESCE((p_lease->>'expected_end_time')::TIMESTAMPTZ, NOW() + INTERVAL '1 day'),
        COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_lease->'before_photo_urls')), '{}'::TEXT[]),
        COALESCE((p_lease->>'deposit_expected')::NUMERIC, 0.0),
        COALESCE((p_lease->>'deposit_paid')::NUMERIC, 0.0),
        COALESCE((p_lease->>'advance_rent_paid')::NUMERIC, 0.0),
        COALESCE(p_lease->>'deposit_payment_type', 'full'),
        COALESCE(p_lease->>'billing_unit_used', 'auto'),
        COALESCE((p_lease->>'calculated_rent')::NUMERIC, 0.0),
        COALESCE((p_lease->>'discount_amount')::NUMERIC, 0.0),
        COALESCE((p_lease->>'damage_or_late_fee')::NUMERIC, 0.0),
        COALESCE((p_lease->>'net_rent_total')::NUMERIC, 0.0),
        COALESCE((p_lease->>'final_settlement_balance')::NUMERIC, 0.0),
        p_lease->>'return_notes',
        v_status,
        COALESCE((p_lease->>'quantity')::INT, 1),
        COALESCE((p_lease->>'taxable_amount')::NUMERIC, 0.0),
        COALESCE(p_lease->>'applied_tax_type', 'No Tax'),
        COALESCE((p_lease->>'applied_tax_rate')::NUMERIC, 0.0),
        COALESCE((p_lease->>'tax_amount')::NUMERIC, 0.0),
        COALESCE((p_lease->>'total_amount_with_tax')::NUMERIC, 0.0),
        COALESCE((p_lease->>'is_tax_inclusive')::BOOLEAN, FALSE),
        COALESCE((p_lease->>'discounted_net_rent_total')::NUMERIC, 0.0),
        NOW(), NOW()
    ) ON CONFLICT (id) DO UPDATE SET
        status = EXCLUDED.status,
        updated_at = NOW();

    -- B. Process Line Items and Sub-Items
    IF p_lease->'lease_items' IS NOT NULL AND jsonb_array_length(p_lease->'lease_items') > 0 THEN
        FOR v_line_rec IN SELECT * FROM jsonb_array_elements(p_lease->'lease_items') LOOP
            v_line_id := v_line_rec->>'id';

            INSERT INTO public.lease_items (
                id, lease_id, store_id, item_id, quantity,
                rate_hourly, rate_daily, rate_weekly, rate_monthly,
                deposit_amount, line_calculated_rent, return_status,
                discounted_rate_hourly, discounted_rate_daily,
                discounted_rate_weekly, discounted_rate_monthly,
                created_at, updated_at
            ) VALUES (
                v_line_id, v_lease_id, v_store_id::TEXT, (v_line_rec->>'item_id')::UUID,
                COALESCE((v_line_rec->>'quantity')::INT, 1),
                COALESCE((v_line_rec->>'rate_hourly')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'rate_daily')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'rate_weekly')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'rate_monthly')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'deposit_amount')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'line_calculated_rent')::NUMERIC, 0.0),
                COALESCE(v_line_rec->>'return_status', 'available'),
                COALESCE((v_line_rec->>'discounted_rate_hourly')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'discounted_rate_daily')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'discounted_rate_weekly')::NUMERIC, 0.0),
                COALESCE((v_line_rec->>'discounted_rate_monthly')::NUMERIC, 0.0),
                NOW(), NOW()
            ) ON CONFLICT (id) DO UPDATE SET
                return_status = EXCLUDED.return_status,
                updated_at = NOW();

            -- Process Sub-Items for this line item
            IF v_line_rec->'leased_sub_items' IS NOT NULL AND jsonb_array_length(v_line_rec->'leased_sub_items') > 0 THEN
                FOR v_sub_rec IN SELECT * FROM jsonb_array_elements(v_line_rec->'leased_sub_items') LOOP
                    v_sub_id := v_sub_rec->>'id';
                    v_unit_id := NULLIF(v_sub_rec->>'lease_item_unit_id', '')::UUID;
                    v_comp_unit_id := NULLIF(v_sub_rec->>'inventory_component_unit_id', '')::UUID;

                    -- Upsert lease_item_units parent checkout row using v_unit_id as PK (matching fallback)
                    IF v_unit_id IS NOT NULL THEN
                        INSERT INTO public.lease_item_units (
                            id, lease_id, lease_item_id, inventory_unit_id,
                            checked_out_at, inspection_status, created_at, updated_at
                        ) VALUES (
                            v_unit_id, v_lease_id, v_line_id, v_unit_id,
                            v_start_time, 'rented', NOW(), NOW()
                        ) ON CONFLICT (id) DO UPDATE SET
                            lease_id = EXCLUDED.lease_id,
                            lease_item_id = EXCLUDED.lease_item_id,
                            inventory_unit_id = EXCLUDED.inventory_unit_id,
                            checked_out_at = EXCLUDED.checked_out_at,
                            inspection_status = EXCLUDED.inspection_status,
                            updated_at = NOW();

                        -- Update physical unit status
                        UPDATE public.inventory_units
                        SET status = v_unit_status, updated_at = NOW()
                        WHERE id = v_unit_id;
                    END IF;

                    -- Upsert leased_sub_items
                    INSERT INTO public.leased_sub_items (
                        id, lease_id, lease_item_id, lease_item_unit_id,
                        inventory_component_unit_id, sub_item_id, item_id,
                        store_id, item_name, serial_number, replacement_cost,
                        is_excluded, condition_status, created_at, updated_at
                    ) VALUES (
                        v_sub_id, v_lease_id, v_line_id, v_unit_id,
                        v_comp_unit_id, COALESCE(v_sub_rec->>'sub_item_id', ''),
                        (v_sub_rec->>'item_id')::UUID, v_store_id::TEXT,
                        COALESCE(v_sub_rec->>'item_name', 'Component'),
                        v_sub_rec->>'serial_number',
                        COALESCE((v_sub_rec->>'replacement_cost')::NUMERIC, 0.0),
                        COALESCE((v_sub_rec->>'is_excluded')::BOOLEAN, FALSE),
                        COALESCE(v_sub_rec->>'condition_status', v_comp_status),
                        NOW(), NOW()
                    ) ON CONFLICT (id) DO UPDATE SET
                        condition_status = EXCLUDED.condition_status,
                        updated_at = NOW();

                    -- Update physical component status
                    IF v_comp_unit_id IS NOT NULL AND COALESCE((v_sub_rec->>'is_excluded')::BOOLEAN, FALSE) = FALSE THEN
                        UPDATE public.inventory_component_units
                        SET status = v_comp_status, updated_at = NOW()
                        WHERE id = v_comp_unit_id;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'lease_id', v_lease_id);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'create_lease_transaction failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- 2. STORED PROCEDURE: RETURN & SETTLE LEASE TRANSACTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.return_settle_lease_transaction(p_settlement JSONB)
RETURNS JSONB AS $$
DECLARE
    v_lease_id UUID;
    v_actual_return TIMESTAMPTZ;
    v_line_rec JSONB;
    v_sub_rec JSONB;
    v_line_id TEXT;
    v_sub_id TEXT;
    v_unit_id UUID;
    v_comp_unit_id UUID;
    v_sub_status TEXT;
    v_target_status TEXT;
BEGIN
    v_lease_id := (p_settlement->>'id')::UUID;
    v_actual_return := COALESCE((p_settlement->>'actual_return_time')::TIMESTAMPTZ, NOW());

    -- A. Update Master Lease Order
    UPDATE public.leases SET
        actual_return_time = v_actual_return,
        billing_unit_used = COALESCE(p_settlement->>'billing_unit_used', 'auto'),
        calculated_rent = COALESCE((p_settlement->>'calculated_rent')::NUMERIC, 0.0),
        discount_amount = COALESCE((p_settlement->>'discount_amount')::NUMERIC, 0.0),
        damage_or_late_fee = COALESCE((p_settlement->>'damage_or_late_fee')::NUMERIC, 0.0),
        net_rent_total = COALESCE((p_settlement->>'net_rent_total')::NUMERIC, 0.0),
        final_settlement_balance = COALESCE((p_settlement->>'final_settlement_balance')::NUMERIC, 0.0),
        return_notes = p_settlement->>'return_notes',
        status = 'returned',
        updated_at = NOW()
    WHERE id = v_lease_id;

    -- B. Update Line Items & Sub Items
    IF p_settlement->'lease_items' IS NOT NULL THEN
        FOR v_line_rec IN SELECT * FROM jsonb_array_elements(p_settlement->'lease_items') LOOP
            v_line_id := v_line_rec->>'id';

            UPDATE public.lease_items SET
                return_status = COALESCE(v_line_rec->>'return_status', 'available'),
                updated_at = NOW()
            WHERE id = v_line_id;

            IF v_line_rec->'leased_sub_items' IS NOT NULL THEN
                FOR v_sub_rec IN SELECT * FROM jsonb_array_elements(v_line_rec->'leased_sub_items') LOOP
                    v_sub_id := v_sub_rec->>'id';
                    v_sub_status := LOWER(COALESCE(v_sub_rec->>'condition_status', 'available'));
                    v_comp_unit_id := NULLIF(v_sub_rec->>'inventory_component_unit_id', '')::UUID;
                    v_unit_id := NULLIF(v_sub_rec->>'lease_item_unit_id', '')::UUID;

                    IF v_sub_status = 'damaged' OR v_sub_status = 'maintenance' OR v_sub_status = 'in_maintenance' THEN
                        v_target_status := 'damaged';
                    ELSIF v_sub_status = 'lost' THEN
                        v_target_status := 'lost';
                    ELSE
                        v_target_status := 'available';
                    END IF;

                    -- Update leased_sub_items
                    UPDATE public.leased_sub_items SET
                        condition_status = v_sub_status,
                        returned_at = v_actual_return,
                        updated_at = NOW()
                    WHERE id = v_sub_id;

                    -- Update physical component status
                    IF v_comp_unit_id IS NOT NULL THEN
                        UPDATE public.inventory_component_units SET
                            status = v_target_status,
                            updated_at = NOW()
                        WHERE id = v_comp_unit_id;
                    ELSIF v_unit_id IS NOT NULL THEN
                        UPDATE public.inventory_component_units SET
                            status = v_target_status,
                            updated_at = NOW()
                        WHERE inventory_unit_id = v_unit_id AND LOWER(component_name) = LOWER(v_sub_rec->>'item_name');
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
    END IF;

    -- C. Sync Physical Set Units Status & Close lease_item_units
    UPDATE public.inventory_units iu SET
        status = CASE
            WHEN EXISTS (
                SELECT 1 FROM public.inventory_component_units icu
                WHERE icu.inventory_unit_id = iu.id
                AND icu.status IN ('damaged', 'maintenance', 'in_maintenance')
            ) THEN 'damaged'
            WHEN EXISTS (
                SELECT 1 FROM public.inventory_component_units icu
                WHERE icu.inventory_unit_id = iu.id
                AND icu.status IN ('lost', 'needed_restock')
            ) THEN 'lost'
            ELSE 'available'
        END,
        updated_at = NOW()
    WHERE iu.id IN (
        SELECT inventory_unit_id FROM public.lease_item_units WHERE lease_id = v_lease_id
    );

    UPDATE public.lease_item_units SET
        returned_at = v_actual_return,
        inspection_status = 'inspected_good',
        updated_at = NOW()
    WHERE lease_id = v_lease_id AND returned_at IS NULL;

    RETURN jsonb_build_object('success', true, 'lease_id', v_lease_id);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'return_settle_lease_transaction failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
