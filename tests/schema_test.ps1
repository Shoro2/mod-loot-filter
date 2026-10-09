# Applies data/sql/db-characters/loot_filter_tables.sql twice to a scratch
# schema, once fresh and once on top of the first version's tables, and
# checks the resulting columns. Run from the module root on the workbench.
# Touches only the scratch schema lf_schema_test, which it drops at the end.
param(
    [string]$Mysql = 'C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe',
    [string]$Login = '-uacore -pacore -h127.0.0.1 -P3306'
)
$ErrorActionPreference = 'Stop'
$schema = 'lf_schema_test'
$sqlFile = (Resolve-Path 'data\sql\db-characters\loot_filter_tables.sql').Path

function Invoke-Sql([string]$db, [string]$query) {
    $out = cmd /c "`"$Mysql`" $Login -N -B $db -e `"$query`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "mysql failed: $out" }
    # The leading comma keeps a one-row result an array.
    return ,@($out | Where-Object { $_ -notmatch 'Using a password' } | ForEach-Object { "$_".Trim() })
}

function Invoke-File([string]$db) {
    $out = cmd /c "`"$Mysql`" $Login $db < `"$sqlFile`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "applying the schema file failed: $out" }
}

function Get-Columns {
    Invoke-Sql $schema "SELECT CONCAT(TABLE_NAME,'.',COLUMN_NAME,':',COLUMN_TYPE,':',IFNULL(COLUMN_DEFAULT,'-')) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$schema' AND TABLE_NAME LIKE 'character_loot_filter_%' ORDER BY TABLE_NAME, ORDINAL_POSITION"
}

$expected = @(
    'character_loot_filter_condition.ruleId:int unsigned:-',
    'character_loot_filter_condition.slot:tinyint unsigned:-',
    'character_loot_filter_condition.type:tinyint unsigned:-',
    'character_loot_filter_condition.op:tinyint unsigned:0',
    'character_loot_filter_condition.value:int unsigned:0',
    'character_loot_filter_condition.value2:int unsigned:0',
    'character_loot_filter_condition.text:varchar(40):',
    'character_loot_filter_rule.ruleId:int unsigned:-',
    'character_loot_filter_rule.characterId:int unsigned:-',
    'character_loot_filter_rule.position:tinyint unsigned:-',
    'character_loot_filter_rule.action:tinyint unsigned:-',
    'character_loot_filter_rule.enabled:tinyint unsigned:1',
    'character_loot_filter_settings.characterId:int unsigned:-',
    'character_loot_filter_settings.filterEnabled:tinyint unsigned:1',
    'character_loot_filter_settings.chatMode:tinyint unsigned:1',
    'character_loot_filter_settings.totalSold:bigint unsigned:0',
    'character_loot_filter_settings.totalDisenchanted:int unsigned:0',
    'character_loot_filter_settings.totalDeleted:int unsigned:0',
    'character_loot_filter_settings.totalStored:int unsigned:0'
)

function Assert-Columns([string]$case) {
    $actual = Get-Columns
    $diff = Compare-Object $expected $actual
    if ($diff) {
        $diff | Format-Table | Out-String | Write-Host
        throw "$case : columns differ"
    }
    Write-Host "$case : columns as expected ($($actual.Count))"
}

try {
    # Case A: fresh schema, file applied twice.
    Invoke-Sql '' "DROP DATABASE IF EXISTS $schema; CREATE DATABASE $schema;" | Out-Null
    Invoke-File $schema
    Invoke-File $schema
    Assert-Columns 'fresh'
    $old = Invoke-Sql $schema "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$schema' AND TABLE_NAME='character_loot_filter'"
    if ($old[0] -ne '0') { throw 'fresh: the old table must not be created' }

    # Case B: the first version's tables, with one settings row.
    Invoke-Sql '' "DROP DATABASE IF EXISTS $schema; CREATE DATABASE $schema;" | Out-Null
    Invoke-Sql $schema "CREATE TABLE character_loot_filter_settings (characterId INT UNSIGNED NOT NULL, filterEnabled TINYINT UNSIGNED NOT NULL DEFAULT 1, totalSold INT UNSIGNED NOT NULL DEFAULT 0, totalDisenchanted INT UNSIGNED NOT NULL DEFAULT 0, totalDeleted INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (characterId)); INSERT INTO character_loot_filter_settings VALUES (7, 0, 4000000000, 3, 2); CREATE TABLE character_loot_filter (characterId INT UNSIGNED NOT NULL, ruleId INT UNSIGNED NOT NULL AUTO_INCREMENT, PRIMARY KEY (ruleId)); INSERT INTO character_loot_filter (characterId) VALUES (7);" | Out-Null
    Invoke-File $schema
    Invoke-File $schema
    Assert-Columns 'upgrade'
    $row = Invoke-Sql $schema "SELECT CONCAT_WS(',', filterEnabled, chatMode, totalSold, totalDisenchanted, totalDeleted, totalStored) FROM character_loot_filter_settings WHERE characterId = 7"
    if ($row[0] -ne '0,1,4000000000,3,2,0') { throw "upgrade: settings row changed: $row" }
    $legacy = Invoke-Sql $schema "SELECT COUNT(*) FROM character_loot_filter"
    if ($legacy[0] -ne '1') { throw 'upgrade: the old rule table must be left to the core' }
    Write-Host 'upgrade: settings row kept, old rule table untouched'
    Write-Host 'schema_test: passed'
}
finally {
    Invoke-Sql '' "DROP DATABASE IF EXISTS $schema;" | Out-Null
}
