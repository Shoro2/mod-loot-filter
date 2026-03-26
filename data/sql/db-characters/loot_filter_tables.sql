--
-- mod-loot-filter: Character filter rules and settings
--

-- Filter rules per character
-- ruleGroup: 0 = standalone (OR), >0 = group ID (AND within group, OR between groups)
CREATE TABLE IF NOT EXISTS `character_loot_filter` (
    `characterId` INT UNSIGNED NOT NULL,
    `ruleId` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `ruleGroup` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=standalone, >0=AND group ID',
    `conditionType` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=quality,1=ilvl,2=sellprice,3=class,4=subclass,5=cursed,6=itemId,7=nameContains',
    `conditionOp` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=equals,1=greater,2=less',
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

-- Migration: add conditionOp column if upgrading from older version
-- Safe to run multiple times (IF NOT EXISTS equivalent via procedure)
DELIMITER //
DROP PROCEDURE IF EXISTS `loot_filter_migrate_conditionOp`//
CREATE PROCEDURE `loot_filter_migrate_conditionOp`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM `INFORMATION_SCHEMA`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE()
          AND `TABLE_NAME` = 'character_loot_filter'
          AND `COLUMN_NAME` = 'conditionOp'
    ) THEN
        ALTER TABLE `character_loot_filter`
            ADD COLUMN `conditionOp` TINYINT UNSIGNED NOT NULL DEFAULT 0
            COMMENT '0=equals,1=greater,2=less'
            AFTER `conditionType`;
        -- Migrate existing "iLvl below" (type 1) and "sell price below" (type 2)
        -- rules to use the "less than" operator so behavior is preserved
        UPDATE `character_loot_filter` SET `conditionOp` = 2
            WHERE `conditionType` IN (1, 2);
    END IF;
END//
DELIMITER ;
CALL `loot_filter_migrate_conditionOp`();
DROP PROCEDURE IF EXISTS `loot_filter_migrate_conditionOp`;

-- Per-character settings and statistics
CREATE TABLE IF NOT EXISTS `character_loot_filter_settings` (
    `characterId` INT UNSIGNED NOT NULL,
    `filterEnabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `totalSold` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Total copper earned',
    `totalDisenchanted` INT UNSIGNED NOT NULL DEFAULT 0,
    `totalDeleted` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`characterId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
