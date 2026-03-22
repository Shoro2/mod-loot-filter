--
-- mod-loot-filter: Character filter rules and settings
--

-- Filter rules per character
-- ruleGroup: 0 = standalone (OR), >0 = group ID (AND within group, OR between groups)
CREATE TABLE IF NOT EXISTS `character_loot_filter` (
    `characterId` INT UNSIGNED NOT NULL,
    `ruleId` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `ruleGroup` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=standalone, >0=AND group ID',
    `conditionType` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=quality,1=ilvl<,2=sellprice<,3=class,4=subclass,5=cursed,6=itemId,7=nameContains',
    `conditionValue` INT UNSIGNED NOT NULL DEFAULT 0,
    `conditionStr` VARCHAR(128) NOT NULL DEFAULT '',
    `action` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '0=keep,1=sell,2=disenchant,3=delete',
    `priority` TINYINT UNSIGNED NOT NULL DEFAULT 100 COMMENT 'Lower = checked first',
    `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`ruleId`),
    KEY `idx_character` (`characterId`),
    KEY `idx_char_priority` (`characterId`, `priority`),
    KEY `idx_char_group` (`characterId`, `ruleGroup`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-character settings and statistics
CREATE TABLE IF NOT EXISTS `character_loot_filter_settings` (
    `characterId` INT UNSIGNED NOT NULL,
    `filterEnabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `totalSold` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Total copper earned',
    `totalDisenchanted` INT UNSIGNED NOT NULL DEFAULT 0,
    `totalDeleted` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`characterId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
