--
-- mod-loot-filter: rules, their conditions and per-character settings
--
-- The AzerothCore updater re-applies this file whenever its bytes change,
-- so every statement here is idempotent. The old one-condition table
-- `character_loot_filter` is migrated by the core at startup and then
-- renamed to `character_loot_filter_legacy` (src/LootFilter.cpp).
--

CREATE TABLE IF NOT EXISTS `character_loot_filter_rule` (
    `ruleId` INT UNSIGNED NOT NULL COMMENT 'assigned by the core',
    `characterId` INT UNSIGNED NOT NULL,
    `position` TINYINT UNSIGNED NOT NULL COMMENT '1-based evaluation order',
    `action` TINYINT UNSIGNED NOT NULL COMMENT '0=keep,1=sell,2=disenchant,3=delete,4=store',
    `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`ruleId`),
    KEY `idx_char_position` (`characterId`, `position`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `character_loot_filter_condition` (
    `ruleId` INT UNSIGNED NOT NULL,
    `slot` TINYINT UNSIGNED NOT NULL COMMENT '0-3',
    `type` TINYINT UNSIGNED NOT NULL COMMENT '0=quality,1=item level,2=sell price,3=item type,5=cursed,6=item,7=name',
    `op` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=is,1=at least,2=at most',
    `value` INT UNSIGNED NOT NULL DEFAULT 0,
    `value2` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'item type: subclass, 255=any',
    `text` VARCHAR(40) NOT NULL DEFAULT '',
    PRIMARY KEY (`ruleId`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `character_loot_filter_settings` (
    `characterId` INT UNSIGNED NOT NULL,
    `filterEnabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `chatMode` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '0=every action,1=summary,2=none',
    `totalSold` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'copper',
    `totalDisenchanted` INT UNSIGNED NOT NULL DEFAULT 0,
    `totalDeleted` INT UNSIGNED NOT NULL DEFAULT 0,
    `totalStored` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`characterId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A settings table from the first version lacks chatMode and totalStored
-- and keeps totalSold as INT.
DELIMITER //
DROP PROCEDURE IF EXISTS `loot_filter_settings_upgrade`//
CREATE PROCEDURE `loot_filter_settings_upgrade`()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM `INFORMATION_SCHEMA`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE()
          AND `TABLE_NAME` = 'character_loot_filter_settings'
          AND `COLUMN_NAME` = 'chatMode'
    ) THEN
        ALTER TABLE `character_loot_filter_settings`
            ADD COLUMN `chatMode` TINYINT UNSIGNED NOT NULL DEFAULT 1
            COMMENT '0=every action,1=summary,2=none' AFTER `filterEnabled`;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM `INFORMATION_SCHEMA`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE()
          AND `TABLE_NAME` = 'character_loot_filter_settings'
          AND `COLUMN_NAME` = 'totalStored'
    ) THEN
        ALTER TABLE `character_loot_filter_settings`
            ADD COLUMN `totalStored` INT UNSIGNED NOT NULL DEFAULT 0
            AFTER `totalDeleted`;
    END IF;
    IF EXISTS (
        SELECT 1 FROM `INFORMATION_SCHEMA`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE()
          AND `TABLE_NAME` = 'character_loot_filter_settings'
          AND `COLUMN_NAME` = 'totalSold'
          AND `DATA_TYPE` <> 'bigint'
    ) THEN
        ALTER TABLE `character_loot_filter_settings`
            MODIFY COLUMN `totalSold` BIGINT UNSIGNED NOT NULL DEFAULT 0
            COMMENT 'copper';
    END IF;
END//
DELIMITER ;
CALL `loot_filter_settings_upgrade`();
DROP PROCEDURE IF EXISTS `loot_filter_settings_upgrade`;
