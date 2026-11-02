CREATE OR REPLACE FUNCTION pgr._mode_category(
    p_mode TEXT,
    p_kind TEXT
)
    RETURNS INTEGER[]
    LANGUAGE plpgsql
    STABLE
    PARALLEL SAFE
AS
$function$
    -- The categories come from the respective network (HERE or OSM) and mean different things per source. They are stored
    -- in pgr.loine_mode_category (created by loine_install.sql). The source is taken from pgr.loine_installed (default: here).
    -- p_kind: buffer (buffer around start and end) | main (main network between start and end) |
    --         snap (categories to which start and end are snapped) | matrix (network of the cost matrix)
DECLARE
    v_source TEXT := 'here';
    v_cats   INTEGER[];
BEGIN
    IF TO_REGCLASS('pgr.loine_installed') IS NOT NULL THEN
        SELECT COALESCE(MIN(source), 'here') INTO v_source FROM pgr.loine_installed;
    END IF;

    SELECT CASE p_kind
               WHEN 'buffer' THEN buffer_cats
               WHEN 'main' THEN main_cats
               WHEN 'snap' THEN snap_cats
               WHEN 'matrix' THEN matrix_cats
               END
    INTO v_cats
    FROM pgr.loine_mode_category
    WHERE source = v_source
      AND mode = p_mode;

    RETURN v_cats;
END;
$function$;
