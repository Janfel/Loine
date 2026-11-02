CREATE OR REPLACE FUNCTION pgr._net_level_cats()
    RETURNS INTEGER[]
    LANGUAGE sql
    STABLE
AS
$function$
    -- Categories of all car modes of the installed data source (from pgr._mode_category, without -1).
    -- Used by pgr.loine_build_net_level.
SELECT ARRAY(SELECT DISTINCT c
             FROM UNNEST(ARRAY ['car', 'card', 'caro', 'care', 'carl']) m,
                  UNNEST(pgr._mode_category(m, 'buffer')) c
             WHERE c > 0
             ORDER BY c);
$function$;
