-- RentLedger Migration 05 Scenario Testing Suite
-- Run in Supabase SQL Editor to test end-to-end functionality

-- Scenario A: Physical Inventory Verification
SELECT
    iu.asset_code AS unit_code,
    icu.component_name,
    icu.asset_code AS comp_code,
    icu.serial_number
FROM public.inventory_units iu
LEFT JOIN public.inventory_component_units icu ON icu.inventory_unit_id = iu.id
ORDER BY iu.asset_code, icu.asset_code;

-- Scenario B: Component Exclusion Verification
SELECT
    lsi.item_name,
    lsi.is_excluded,
    icu.status AS physical_component_status
FROM public.leased_sub_items lsi
JOIN public.inventory_component_units icu ON icu.id = lsi.inventory_component_unit_id
WHERE lsi.is_excluded = TRUE;

-- Scenario C: Incident & Payment Trigger Reconciliation Verification
SELECT
    i.id AS incident_id,
    i.customer_charge,
    i.customer_amount_paid,
    i.payment_status,
    COALESCE(SUM(p.amount_paid), 0) AS total_payments_sum
FROM public.damage_loss_incidents i
LEFT JOIN public.damage_loss_payments p ON p.incident_id = i.id
GROUP BY i.id, i.customer_charge, i.customer_amount_paid, i.payment_status;
