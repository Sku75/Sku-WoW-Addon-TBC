-- Seed map dataset number for this SkuMapper package.
--
-- STAMPED BY TOOLING — do not edit by hand. dev/mapper/skumap.py ("seed"
-- command) rewrites this file whenever a new numbered map dataset is
-- registered for packaging; SkuNav:LoadDefaultMapData records the value as
-- SkuOptions.db.global["SkuNav"].seedMapId at seeding time, and /sku save
-- writes it into the hand-in header as "basedOn".
--
-- 0 means "unknown seed" (an old package without a registered map number).
SKUMAPPER_SEED_MAPID = 1
