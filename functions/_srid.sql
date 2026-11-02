CREATE OR REPLACE FUNCTION pgr._srid()
    RETURNS INTEGER
    LANGUAGE plpgsql
    STABLE
    PARALLEL SAFE
AS
$function$
    -- A database contains only countries of one region (checked by pgr.loine_install_country). The projection is stored in
    -- pgr.loine_installed.srid: Europe 3035, Africa 990001, North America 990002. Without entry (older installation): 3035.
    -- The functions transform input points (EPSG:4326) into metre coordinates of this projection and derive tile,
    -- cluster, grid cell and search radii from them.
DECLARE
    v_srid INTEGER;
BEGIN
    IF TO_REGCLASS('pgr.loine_installed') IS NOT NULL
        AND EXISTS (SELECT 1
                    FROM information_schema.columns
                    WHERE table_schema = 'pgr'
                      AND table_name = 'loine_installed'
                      AND column_name = 'srid') THEN
        EXECUTE 'SELECT MIN(srid) FROM pgr.loine_installed' INTO v_srid;
    END IF;
    RETURN COALESCE(v_srid, 3035);
END;
$function$;
