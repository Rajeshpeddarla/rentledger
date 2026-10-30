-- RentLedger Production-Grade Physical Inventory Migration (05)
-- Execute in Supabase SQL Editor

BEGIN;

-- ============================================================================
-- 1. MIGRATION VERSION HISTORY, TRACKING REGISTRY & AUDIT LOG TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.migration_version_history (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'completed'
);

CREATE TABLE IF NOT EXISTS public.migration_mapping_registry (
    source_table TEXT NOT NULL,
    source_id TEXT NOT NULL,
    target_table TEXT NOT NULL,
    target_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_migration_mapping_registry PRIMARY KEY (source_table, source_id, target_table, target_id)
);

CREATE TABLE IF NOT EXISTS public.migration_manual_review_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    issue_reason TEXT NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. STORE ASSET CODE REGISTRY & CONCURRENCY-SAFE COUNTERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.store_asset_counters (
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    prefix TEXT NOT NULL,
    last_seq INT DEFAULT 0 CHECK (last_seq >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_store_asset_counters PRIMARY KEY (store_id, prefix)
);

CREATE TABLE IF NOT EXISTS public.store_asset_registry (
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    asset_code TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (asset_type IN ('physical_unit', 'component_unit')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_store_asset_registry PRIMARY KEY (store_id, asset_code)
);

CREATE OR REPLACE FUNCTION public.generate_store_asset_code(
    p_store_id UUID,
    p_prefix TEXT,
    p_asset_type TEXT
) RETURNS TEXT AS $$
DECLARE
    v_next_seq INT;
    v_code TEXT;
BEGIN
    -- Validates real store ownership matches authenticated user
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.stores WHERE id = p_store_id AND id = auth.uid()) THEN
            RAISE EXCEPTION 'UNAUTHORIZED_STORE_ACCESS' USING ERRCODE = '42501';
        END IF;
    END IF;

    INSERT INTO public.store_asset_counters (store_id, prefix, last_seq)
    VALUES (p_store_id, UPPER(p_prefix), 1)
    ON CONFLICT (store_id, prefix) DO UPDATE
    SET last_seq = store_asset_counters.last_seq + 1,
        updated_at = NOW()
    RETURNING last_seq INTO v_next_seq;

    v_code := UPPER(p_prefix) || '-' || LPAD(v_next_seq::TEXT, 4, '0');

    INSERT INTO public.store_asset_registry (store_id, asset_code, asset_type)
    VALUES (p_store_id, v_code, p_asset_type);

    RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.generate_store_asset_code(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_store_asset_code(UUID, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 3. REUSABLE COMPONENT DEFINITIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sub_item_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    component_name TEXT NOT NULL,
    default_quantity INT DEFAULT 1 CHECK (default_quantity >= 0),
    is_required BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sub_item_definitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage sub_item_definitions for their store" ON public.sub_item_definitions;
CREATE POLICY "Users can manage sub_item_definitions for their store" ON public.sub_item_definitions FOR ALL USING (auth.uid() = store_id) WITH CHECK (auth.uid() = store_id);

-- ============================================================================
-- 4. PHYSICAL INVENTORY UNITS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inventory_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    asset_code TEXT NOT NULL,
    status TEXT DEFAULT 'available' CHECK (status IN ('available', 'rented', 'maintenance', 'lost', 'awaiting_inspection', 'archived')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_unit_asset_code_per_store UNIQUE (store_id, asset_code)
);

ALTER TABLE public.inventory_units ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage inventory_units for their store" ON public.inventory_units;
CREATE POLICY "Users can manage inventory_units for their store" ON public.inventory_units FOR ALL USING (auth.uid() = store_id) WITH CHECK (auth.uid() = store_id);

-- ============================================================================
-- 5. PHYSICAL COMPONENT UNITS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inventory_component_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_unit_id UUID NOT NULL REFERENCES public.inventory_units(id) ON DELETE CASCADE,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
    component_definition_id UUID REFERENCES public.sub_item_definitions(id) ON DELETE SET NULL,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    component_name TEXT NOT NULL,
    asset_code TEXT NOT NULL,
    serial_number TEXT,
    status TEXT DEFAULT 'available' CHECK (status IN ('available', 'rented', 'maintenance', 'lost', 'archived')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_comp_asset_code_per_store UNIQUE (store_id, asset_code)
);

ALTER TABLE public.inventory_component_units ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage inventory_component_units for their store" ON public.inventory_component_units;
CREATE POLICY "Users can manage inventory_component_units for their store" ON public.inventory_component_units FOR ALL USING (auth.uid() = store_id) WITH CHECK (auth.uid() = store_id);

CREATE OR REPLACE FUNCTION public.fn_validate_component_unit_ownership()
RETURNS TRIGGER AS $$
DECLARE
    v_unit_store UUID;
    v_unit_item UUID;
BEGIN
    SELECT store_id, inventory_item_id INTO v_unit_store, v_unit_item
    FROM public.inventory_units WHERE id = NEW.inventory_unit_id;

    IF v_unit_store <> NEW.store_id OR v_unit_item <> NEW.inventory_item_id THEN
        RAISE EXCEPTION 'RELATIONSHIP_MISMATCH: Component unit store/product does not match parent physical unit' USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_component_unit_ownership ON public.inventory_component_units;
CREATE TRIGGER trg_validate_component_unit_ownership
BEFORE INSERT OR UPDATE ON public.inventory_component_units
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_component_unit_ownership();

-- ============================================================================
-- 6. PHYSICAL SET ASSIGNMENTS (LEASE ITEM UNITS)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.lease_item_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id UUID NOT NULL REFERENCES public.leases(id) ON DELETE CASCADE,
    lease_item_id TEXT NOT NULL REFERENCES public.lease_items(id) ON DELETE CASCADE,
    inventory_unit_id UUID NOT NULL REFERENCES public.inventory_units(id) ON DELETE RESTRICT,
    checkout_condition TEXT DEFAULT 'good',
    checkout_notes TEXT,
    checked_out_at TIMESTAMPTZ DEFAULT NOW(),
    return_condition TEXT,
    return_notes TEXT,
    returned_at TIMESTAMPTZ,
    inspection_status TEXT DEFAULT 'rented' CHECK (inspection_status IN ('rented', 'inspected_good', 'awaiting_inspection', 'maintenance', 'lost')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.lease_item_units ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage lease_item_units for their store" ON public.lease_item_units;
CREATE POLICY "Users can manage lease_item_units for their store" ON public.lease_item_units
    FOR ALL USING (auth.uid() IN (SELECT store_id FROM public.leases WHERE id = lease_id));

CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_unit_assignment ON public.lease_item_units (inventory_unit_id) WHERE (returned_at IS NULL AND inspection_status IN ('rented', 'awaiting_inspection'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_unit_per_lease_item ON public.lease_item_units (lease_item_id, inventory_unit_id);

-- ============================================================================
-- 7. ALTER LEASED SUB ITEMS
-- ============================================================================

ALTER TABLE public.leased_sub_items
ADD COLUMN IF NOT EXISTS lease_item_unit_id UUID REFERENCES public.lease_item_units(id) ON DELETE RESTRICT,
ADD COLUMN IF NOT EXISTS inventory_component_unit_id UUID REFERENCES public.inventory_component_units(id) ON DELETE RESTRICT,
ADD COLUMN IF NOT EXISTS is_excluded BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS checkout_condition TEXT DEFAULT 'good',
ADD COLUMN IF NOT EXISTS checkout_notes TEXT,
ADD COLUMN IF NOT EXISTS checked_out_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS return_condition TEXT DEFAULT 'good',
ADD COLUMN IF NOT EXISTS return_notes TEXT,
ADD COLUMN IF NOT EXISTS returned_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_component_assignment ON public.leased_sub_items (inventory_component_unit_id) WHERE (returned_at IS NULL AND is_excluded = FALSE AND condition_status IN ('rented', 'awaiting_inspection'));

-- ============================================================================
-- 8. DAMAGE & LOSS INCIDENTS & PAYMENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.damage_loss_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    lease_id UUID REFERENCES public.leases(id) ON DELETE RESTRICT,
    lease_item_id TEXT REFERENCES public.lease_items(id) ON DELETE SET NULL,
    inventory_unit_id UUID REFERENCES public.inventory_units(id) ON DELETE RESTRICT,
    inventory_component_unit_id UUID REFERENCES public.inventory_component_units(id) ON DELETE RESTRICT,
    incident_type TEXT NOT NULL CHECK (incident_type IN ('damaged', 'lost')),
    description TEXT,
    estimated_repair_cost NUMERIC DEFAULT 0.0 CHECK (estimated_repair_cost >= 0),
    actual_repair_cost NUMERIC DEFAULT 0.0 CHECK (actual_repair_cost >= 0),
    customer_charge NUMERIC DEFAULT 0.0 CHECK (customer_charge >= 0),
    customer_amount_paid NUMERIC DEFAULT 0.0 CHECK (customer_amount_paid >= 0),
    payment_status TEXT DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'partially_paid', 'fully_paid', 'overpaid')),
    repair_status TEXT DEFAULT 'reported' CHECK (repair_status IN ('reported', 'awaiting_repair', 'in_repair', 'repaired', 'replaced', 'written_off', 'resolved')),
    reported_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT check_exactly_one_asset_ref CHECK (
        (inventory_unit_id IS NOT NULL AND inventory_component_unit_id IS NULL) OR
        (inventory_unit_id IS NULL AND inventory_component_unit_id IS NOT NULL)
    )
);

ALTER TABLE public.damage_loss_incidents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage damage_loss_incidents for their store" ON public.damage_loss_incidents;
CREATE POLICY "Users can manage damage_loss_incidents for their store" ON public.damage_loss_incidents FOR ALL USING (auth.uid() = store_id) WITH CHECK (auth.uid() = store_id);

CREATE TABLE IF NOT EXISTS public.damage_loss_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID NOT NULL REFERENCES public.damage_loss_incidents(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    amount_paid NUMERIC NOT NULL CHECK (amount_paid > 0),
    payment_method TEXT DEFAULT 'cash',
    notes TEXT,
    paid_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.damage_loss_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage damage_loss_payments for their store" ON public.damage_loss_payments;
CREATE POLICY "Users can manage damage_loss_payments for their store" ON public.damage_loss_payments FOR ALL USING (auth.uid() = store_id) WITH CHECK (auth.uid() = store_id);

CREATE OR REPLACE FUNCTION public.fn_update_incident_totals(p_incident_id UUID) RETURNS VOID AS $$
DECLARE
    v_total_paid NUMERIC;
    v_charge NUMERIC;
    v_status TEXT;
BEGIN
    SELECT COALESCE(SUM(amount_paid), 0.0) INTO v_total_paid
    FROM public.damage_loss_payments WHERE incident_id = p_incident_id;

    SELECT customer_charge INTO v_charge
    FROM public.damage_loss_incidents WHERE id = p_incident_id;

    IF v_total_paid <= 0 THEN v_status := 'unpaid';
    ELSIF v_total_paid < v_charge THEN v_status := 'partially_paid';
    ELSIF v_total_paid = v_charge THEN v_status := 'fully_paid';
    ELSE v_status := 'overpaid'; END IF;

    UPDATE public.damage_loss_incidents
    SET customer_amount_paid = v_total_paid, payment_status = v_status, updated_at = NOW()
    WHERE id = p_incident_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.fn_sync_damage_incident_payments() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.incident_id != NEW.incident_id) THEN
        PERFORM public.fn_update_incident_totals(OLD.incident_id);
    END IF;
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.incident_id != NEW.incident_id) OR (TG_OP = 'UPDATE' AND OLD.amount_paid != NEW.amount_paid) THEN
        PERFORM public.fn_update_incident_totals(NEW.incident_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_incident_payments ON public.damage_loss_payments;
CREATE TRIGGER trg_sync_incident_payments AFTER INSERT OR UPDATE OR DELETE ON public.damage_loss_payments
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_damage_incident_payments();

CREATE OR REPLACE FUNCTION public.fn_sync_damage_incident_charge() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.customer_charge IS DISTINCT FROM OLD.customer_charge THEN
        PERFORM public.fn_update_incident_totals(NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_incident_charge ON public.damage_loss_incidents;
CREATE TRIGGER trg_sync_incident_charge AFTER UPDATE OF customer_charge ON public.damage_loss_incidents
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_damage_incident_charge();

-- ============================================================================
-- 9. IDEMPOTENT DATA MIGRATION WITH RELIABLE LEGACY MAPPING
-- ============================================================================

DO $$
DECLARE
    v_item_rec RECORD;
    v_sub_rec RECORD;
    v_lease_item_rec RECORD;
    v_unit_idx INT;
    v_unit_id UUID;
    v_def_id UUID;
    v_comp_id UUID;
    v_unit_assignment_id UUID;
    v_tag TEXT;
    v_unit_code TEXT;
    v_comp_code TEXT;
    v_initial_comp_status TEXT;
    v_assigned_qty INT;
    v_unit_arr UUID[];
BEGIN
    IF EXISTS (SELECT 1 FROM public.migration_version_history WHERE version = '05_physical_inventory') THEN
        RAISE NOTICE 'Migration 05_physical_inventory already completed. Skipping.';
        RETURN;
    END IF;

    -- A. Migrate Products and Definitions
    FOR v_item_rec IN SELECT * FROM public.inventory_items WHERE is_archived = FALSE LOOP
        IF COALESCE(v_item_rec.total_quantity, 0) <= 0 THEN
            INSERT INTO public.migration_manual_review_audit (store_id, entity_type, entity_id, issue_reason)
            VALUES (v_item_rec.store_id, 'zero_inventory_item', v_item_rec.id::text, 'Product total_quantity <= 0; zero physical set units generated.');
            CONTINUE;
        END IF;

        v_tag := COALESCE(NULLIF(TRIM(v_item_rec.sku), ''), 'AST');

        -- Create definitions grouped by lowercase name to find actual default quantities
        FOR v_sub_rec IN
            SELECT LOWER(TRIM(name)) as norm_name, MAX(name) as disp_name, COUNT(*) as cnt
            FROM public.sub_items WHERE parent_item_id = v_item_rec.id::text GROUP BY LOWER(TRIM(name))
        LOOP
            INSERT INTO public.sub_item_definitions (parent_item_id, store_id, component_name, default_quantity)
            VALUES (v_item_rec.id, v_item_rec.store_id, v_sub_rec.disp_name, CEIL(v_sub_rec.cnt::NUMERIC / v_item_rec.total_quantity))
            RETURNING id INTO v_def_id;

            INSERT INTO public.migration_mapping_registry (source_table, source_id, target_table, target_id)
            VALUES ('sub_items_def', v_item_rec.id::text || '_' || v_sub_rec.norm_name, 'sub_item_definitions', v_def_id::text);
        END LOOP;

        -- Create physical units
        v_unit_arr := '{}';
        FOR v_unit_idx IN 1..v_item_rec.total_quantity LOOP
            v_unit_code := public.generate_store_asset_code(v_item_rec.store_id, v_tag, 'physical_unit');

            INSERT INTO public.inventory_units (inventory_item_id, store_id, asset_code, status)
            VALUES (v_item_rec.id, v_item_rec.store_id, v_unit_code, 'available')
            RETURNING id INTO v_unit_id;

            v_unit_arr := array_append(v_unit_arr, v_unit_id);

            INSERT INTO public.migration_mapping_registry (source_table, source_id, target_table, target_id)
            VALUES ('inventory_items_unit', v_item_rec.id::text || '_' || v_unit_idx, 'inventory_units', v_unit_id::text);
        END LOOP;

        -- Distribute legacy physical components across the generated sets
        -- Use modulo arithmetic to spread the specific instances without duplicating serials
        v_unit_idx := 1;
        FOR v_sub_rec IN SELECT * FROM public.sub_items WHERE parent_item_id = v_item_rec.id::text ORDER BY created_at ASC LOOP
            v_unit_id := v_unit_arr[v_unit_idx];

            SELECT target_id::UUID INTO v_def_id FROM public.migration_mapping_registry
            WHERE source_table = 'sub_items_def' AND source_id = v_item_rec.id::text || '_' || LOWER(TRIM(v_sub_rec.name));

            v_comp_code := public.generate_store_asset_code(v_item_rec.store_id, UPPER(SUBSTRING(v_sub_rec.name FROM 1 FOR 3)), 'component_unit');

            v_initial_comp_status := COALESCE(NULLIF(TRIM(v_sub_rec.status), ''), 'available');
            IF v_initial_comp_status NOT IN ('available', 'rented', 'maintenance', 'lost', 'archived') THEN
                INSERT INTO public.migration_manual_review_audit (store_id, entity_type, entity_id, issue_reason)
                VALUES (v_item_rec.store_id, 'sub_item_status', v_sub_rec.id, 'Unknown legacy status defaulted to available');
                v_initial_comp_status := 'available';
            END IF;

            INSERT INTO public.inventory_component_units (inventory_unit_id, inventory_item_id, component_definition_id, store_id, component_name, asset_code, serial_number, status, notes)
            VALUES (v_unit_id, v_item_rec.id, v_def_id, v_item_rec.store_id, v_sub_rec.name, v_comp_code, v_sub_rec.serial_number, v_initial_comp_status, v_sub_rec.notes)
            RETURNING id INTO v_comp_id;

            INSERT INTO public.migration_mapping_registry (source_table, source_id, target_table, target_id)
            VALUES ('sub_items', v_sub_rec.id, 'inventory_component_units', v_comp_id::text);

            v_unit_idx := v_unit_idx + 1;
            IF v_unit_idx > array_length(v_unit_arr, 1) THEN
                v_unit_idx := 1;
            END IF;
        END LOOP;
    END LOOP;

    -- C. Migrate Active Lease Assignments
    FOR v_lease_item_rec IN
        SELECT li.id AS lease_item_id, li.lease_id, li.item_id, COALESCE(li.quantity, 1) AS qty, l.store_id, l.start_time, l.status AS lease_status
        FROM public.lease_items li
        JOIN public.leases l ON l.id = li.lease_id
        WHERE l.status IN ('active', 'upcoming', 'reserved', 'partial_return') AND COALESCE(li.quantity, 0) > 0
    LOOP
        v_assigned_qty := 0;

        -- First pass: Find sets explicitly targeted by legacy leased_sub_items components
        FOR v_sub_rec IN
            SELECT DISTINCT icu.inventory_unit_id
            FROM public.leased_sub_items lsi
            JOIN public.migration_mapping_registry map ON map.source_id = lsi.sub_item_id AND map.source_table = 'sub_items'
            JOIN public.inventory_component_units icu ON icu.id = map.target_id::uuid
            WHERE lsi.lease_item_id = v_lease_item_rec.lease_item_id
        LOOP
            IF v_assigned_qty < v_lease_item_rec.qty THEN
                IF EXISTS (SELECT 1 FROM public.inventory_units WHERE id = v_sub_rec.inventory_unit_id AND status = 'available') AND
                   NOT EXISTS (SELECT 1 FROM public.lease_item_units WHERE inventory_unit_id = v_sub_rec.inventory_unit_id AND returned_at IS NULL) THEN

                    UPDATE public.inventory_units SET status = 'rented' WHERE id = v_sub_rec.inventory_unit_id;

                    INSERT INTO public.lease_item_units (lease_id, lease_item_id, inventory_unit_id, checked_out_at, inspection_status)
                    VALUES (v_lease_item_rec.lease_id, v_lease_item_rec.lease_item_id, v_sub_rec.inventory_unit_id, v_lease_item_rec.start_time, 'rented')
                    RETURNING id INTO v_unit_assignment_id;

                    INSERT INTO public.migration_mapping_registry (source_table, source_id, target_table, target_id)
                    VALUES ('lease_items', v_lease_item_rec.lease_item_id || '_unit_' || (v_assigned_qty + 1), 'lease_item_units', v_unit_assignment_id::text);

                    -- Update specific leased_sub_items for this unit
                    UPDATE public.leased_sub_items lsi
                    SET lease_item_unit_id = v_unit_assignment_id,
                        inventory_component_unit_id = icu.id,
                        checked_out_at = COALESCE(lsi.checked_out_at, v_lease_item_rec.start_time)
                    FROM public.migration_mapping_registry map
                    JOIN public.inventory_component_units icu ON icu.id = map.target_id::uuid
                    WHERE map.source_table = 'sub_items' AND map.source_id = lsi.sub_item_id
                      AND lsi.lease_item_id = v_lease_item_rec.lease_item_id
                      AND icu.inventory_unit_id = v_sub_rec.inventory_unit_id;

                    v_assigned_qty := v_assigned_qty + 1;
                END IF;
            END IF;
        END LOOP;

        -- Second pass: Assign remaining required sets
        WHILE v_assigned_qty < v_lease_item_rec.qty LOOP
            SELECT id INTO v_unit_id FROM public.inventory_units
            WHERE inventory_item_id = v_lease_item_rec.item_id AND status = 'available'
              AND NOT EXISTS (SELECT 1 FROM public.lease_item_units WHERE inventory_unit_id = public.inventory_units.id AND returned_at IS NULL)
            LIMIT 1 FOR UPDATE;

            IF v_unit_id IS NOT NULL THEN
                UPDATE public.inventory_units SET status = 'rented' WHERE id = v_unit_id;

                INSERT INTO public.lease_item_units (lease_id, lease_item_id, inventory_unit_id, checked_out_at, inspection_status)
                VALUES (v_lease_item_rec.lease_id, v_lease_item_rec.lease_item_id, v_unit_id, v_lease_item_rec.start_time, 'rented')
                RETURNING id INTO v_unit_assignment_id;

                INSERT INTO public.migration_mapping_registry (source_table, source_id, target_table, target_id)
                VALUES ('lease_items', v_lease_item_rec.lease_item_id || '_unit_' || (v_assigned_qty + 1), 'lease_item_units', v_unit_assignment_id::text);

                v_assigned_qty := v_assigned_qty + 1;
            ELSE
                INSERT INTO public.migration_manual_review_audit (store_id, entity_type, entity_id, issue_reason)
                VALUES (v_lease_item_rec.store_id, 'active_lease_item', v_lease_item_rec.lease_item_id, 'Insufficient physical sets to assign active lease line item');
                EXIT; -- Abort allocating more for this line item, leave partially unassigned
            END IF;
        END LOOP;
    END LOOP;

    INSERT INTO public.migration_version_history (version) VALUES ('05_physical_inventory');
END $$;
COMMIT;
