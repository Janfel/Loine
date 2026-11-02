CREATE OR REPLACE FUNCTION pgr.loine_info(OUT version TEXT,
                                          OUT released DATE,
                                          OUT website TEXT,
                                          OUT contact TEXT,
                                          OUT license TEXT)
    LANGUAGE sql
    IMMUTABLE
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Version of the installed Loine software, website, contact and license.
    --              Version and release date are set with every release (same version as in the file VERSION).
SELECT '3.0.0',
       DATE '2026-11-02',
       'https://www.casageo.de/loine.html',
       'info@casageo.de',
       'AGPL-3.0-only or commercial license (casaGeo Data + Services GmbH)';
$function$;
