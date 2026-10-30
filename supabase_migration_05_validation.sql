-- RentLedger Migration 05 Comprehensive Validation Suite

-- 1. Compare legacy inventory quantity to generated physical units
SELECT i.id, i.name, i.total_quantity, COUNT(u.id) AS generated_units
FROM public.inventory_items i
LEFT JOIN public.inventory_units u ON u.inventory_item_id = i.id
WHERE i.is_archived = false
GROUP BY i.id, i.name, i.total_quantity
HAVING i.total_quantity != COUNT(u.id);

-- 2. Verify all active lease quantities were successfully allocated physical sets
SELECT li.id, li.quantity, COUNT(liu.id) AS assigned
FROM public.lease_items li
JOIN public.leases l ON l.id = li.lease_id
LEFT JOIN public.lease_item_units liu ON liu.lease_item_id = li.id
WHERE l.status IN ('active', 'upcoming', 'reserved', 'partial_return')
GROUP BY li.id, li.quantity
HAVING li.quantity != COUNT(liu.id);

-- 3. Verify exactly 1-to-1 migration mapping of legacy sub_items to inventory_component_units
SELECT source_id, COUNT(*)
FROM public.migration_mapping_registry
WHERE source_table = 'sub_items' AND target_table = 'inventory_component_units'
GROUP BY source_id HAVING COUNT(*) > 1;

-- 4. Audit Unmapped Active Rentals and Zero Inventory Products
SELECT * FROM public.migration_manual_review_audit ORDER BY created_at DESC;
