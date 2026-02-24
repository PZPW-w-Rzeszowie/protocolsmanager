-- =================================================================
-- Plugin Fields – inicjalizacja tabel i konfiguracja
-- dla protocolsmanager (kontener "dodatkowepola")
--
-- Skrypt jest IDEMPOTENTNY – można go uruchamiać wielokrotnie.
-- Nie używa hardkodowanych ID profili.
-- =================================================================

-- ---------------------------------------------------------------
-- 0. Wyczyść istniejące wpisy Fields (czysty start)
-- ---------------------------------------------------------------

DELETE FROM `glpi_plugin_fields_profiles` WHERE 1;
DELETE FROM `glpi_plugin_fields_fields` WHERE 1;
DELETE FROM `glpi_plugin_fields_containers` WHERE 1;
DELETE FROM `glpi_profilerights` WHERE `name` = 'plugin_fields_containers';

-- ---------------------------------------------------------------
-- 1. Tabele bazowe pluginu Fields (jeśli nie istnieją)
-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_containers` (
  `id`            int unsigned NOT NULL AUTO_INCREMENT,
  `name`          varchar(255) DEFAULT NULL,
  `label`         varchar(255) DEFAULT NULL,
  `itemtypes`     longtext     DEFAULT NULL,
  `type`          varchar(255) NOT NULL DEFAULT 'tab',
  `subtype`       varchar(255) DEFAULT NULL,
  `entities_id`   int unsigned NOT NULL DEFAULT 0,
  `is_recursive`  tinyint      NOT NULL DEFAULT 0,
  `is_active`     tinyint      NOT NULL DEFAULT 0,
  `date_mod`      timestamp    NULL DEFAULT NULL,
  `date_creation` timestamp    NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `name`        (`name`),
  KEY `entities_id` (`entities_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_fields` (
  `id`                            int unsigned NOT NULL AUTO_INCREMENT,
  `name`                          varchar(255) DEFAULT NULL,
  `label`                         varchar(255) DEFAULT NULL,
  `type`                          varchar(255) NOT NULL DEFAULT 'text',
  `plugin_fields_containers_id`   int unsigned NOT NULL DEFAULT 0,
  `ranking`                       int          NOT NULL DEFAULT 0,
  `default_value`                 varchar(255) DEFAULT NULL,
  `is_active`                     tinyint      NOT NULL DEFAULT 1,
  `is_readonly`                   tinyint      NOT NULL DEFAULT 0,
  `mandatory`                     tinyint      NOT NULL DEFAULT 0,
  `allowed_values`                longtext     DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `plugin_fields_containers_id` (`plugin_fields_containers_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_profiles` (
  `id`                            int unsigned NOT NULL AUTO_INCREMENT,
  `profiles_id`                   int unsigned NOT NULL DEFAULT 0,
  `plugin_fields_containers_id`   int unsigned NOT NULL DEFAULT 0,
  `right`                         char(1)      DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`profiles_id`, `plugin_fields_containers_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------
-- 2. Wyczyść duplikaty kontenera "dodatkowepola" (zachowaj najstarszy)
-- ---------------------------------------------------------------

DELETE c2 FROM `glpi_plugin_fields_containers` c1
JOIN `glpi_plugin_fields_containers` c2
  ON c1.name = c2.name AND c1.id < c2.id
WHERE c1.name = 'dodatkowepola';

-- ---------------------------------------------------------------
-- 3. Wstaw kontener "dodatkowepola" jeśli nie istnieje
-- ---------------------------------------------------------------

INSERT INTO `glpi_plugin_fields_containers`
  (`name`, `label`, `itemtypes`, `type`, `entities_id`, `is_recursive`, `is_active`, `date_creation`, `date_mod`)
SELECT
  'dodatkowepola', 'Dodatkowe pola',
  '["Computer","Monitor","Printer","Peripheral","Phone"]',
  'tab', 0, 1, 1, NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM `glpi_plugin_fields_containers` WHERE `name` = 'dodatkowepola'
);

-- Upewnij się, że istniejący kontener ma właściwą konfigurację
UPDATE `glpi_plugin_fields_containers`
SET `is_active`    = 1,
    `itemtypes`    = '["Computer","Monitor","Printer","Peripheral","Phone"]',
    `is_recursive` = 1,
    `date_mod`     = NOW()
WHERE `name` = 'dodatkowepola';

-- Pobierz ID kontenera
SET @container_id = (
  SELECT `id` FROM `glpi_plugin_fields_containers`
  WHERE `name` = 'dodatkowepola' LIMIT 1
);

-- ---------------------------------------------------------------
-- 4. Pole "odpowiedzialnymaterialniefield" (jeśli nie istnieje)
-- ---------------------------------------------------------------

INSERT INTO `glpi_plugin_fields_fields`
  (`name`, `label`, `type`, `plugin_fields_containers_id`, `ranking`, `is_active`)
SELECT
  'odpowiedzialnymaterialniefield', 'Odpowiedzialny materialnie',
  'dropdown', @container_id, 1, 1
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM `glpi_plugin_fields_fields`
  WHERE `name` = 'odpowiedzialnymaterialniefield'
    AND `plugin_fields_containers_id` = @container_id
);

-- ---------------------------------------------------------------
-- 5. Uprawnienia w glpi_plugin_fields_profiles
--    Dynamicznie dla WSZYSTKICH profili (bez hardkodowanych ID):
--    - profil z config UPDATE (rights >= 2) → write
--    - pozostałe → read
-- ---------------------------------------------------------------

-- Napraw istniejące błędne wartości tekstowe → liczbowe
UPDATE `glpi_plugin_fields_profiles`
SET `right` = '4' WHERE `right` = 'w' AND `plugin_fields_containers_id` = @container_id;
UPDATE `glpi_plugin_fields_profiles`
SET `right` = '1' WHERE `right` = 'r' AND `plugin_fields_containers_id` = @container_id;

-- Write (CREATE=4) dla profili z prawem config (Super-Admin, Admin itp.)
INSERT IGNORE INTO `glpi_plugin_fields_profiles`
  (`profiles_id`, `plugin_fields_containers_id`, `right`)
SELECT pr.profiles_id, @container_id, '4'
FROM `glpi_profilerights` pr
WHERE pr.name = 'config' AND pr.rights >= 2;

-- Read (READ=1) dla wszystkich pozostałych profili
INSERT IGNORE INTO `glpi_plugin_fields_profiles`
  (`profiles_id`, `plugin_fields_containers_id`, `right`)
SELECT p.id, @container_id, '1'
FROM `glpi_profiles` p
WHERE NOT EXISTS (
  SELECT 1 FROM `glpi_plugin_fields_profiles` fp
  WHERE fp.profiles_id = p.id
    AND fp.plugin_fields_containers_id = @container_id
);

-- ---------------------------------------------------------------
-- 6. Uprawnienia w glpi_profilerights (system GLPI)
--    23 = READ|UPDATE|CREATE|DELETE|PURGE (pełne)
--    Dynamicznie — pełne dla profili z config-write, read dla reszty
-- ---------------------------------------------------------------

INSERT INTO `glpi_profilerights` (`profiles_id`, `name`, `rights`)
SELECT pr.profiles_id, 'plugin_fields_containers', 23
FROM `glpi_profilerights` pr
WHERE pr.name = 'config' AND pr.rights >= 2
ON DUPLICATE KEY UPDATE `rights` = 23;

INSERT INTO `glpi_profilerights` (`profiles_id`, `name`, `rights`)
SELECT p.id, 'plugin_fields_containers', 1
FROM `glpi_profiles` p
WHERE NOT EXISTS (
  SELECT 1 FROM `glpi_profilerights` prx
  WHERE prx.profiles_id = p.id
    AND prx.name = 'plugin_fields_containers'
)
ON DUPLICATE KEY UPDATE `rights` = `rights`;

-- ---------------------------------------------------------------
-- 7. Dynamiczne tabele danych (po jednej na itemtype)
--    Nazwa: glpi_plugin_fields_<itemtype>dodatkowepolas
--    Kolumna: users_id_odpowiedzialnymaterialniefield
-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_computerdodatkowepolas` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Computer',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `plugin_fields_containers_id`    (`plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_monitordodatkowepolas` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Monitor',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `plugin_fields_containers_id`    (`plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_printerdodatkowepolas` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Printer',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `plugin_fields_containers_id`    (`plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_peripheraldodatkowepolas` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Peripheral',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `plugin_fields_containers_id`    (`plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_phonedodatkowepolas` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Phone',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `plugin_fields_containers_id`    (`plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------
-- 8. Tabela dla stałej PLUGIN_PROTOCOLS_USER_COMPUTERS_TABLE
--    (kompatybilność wsteczna – getComputersAssignedToUser)
-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `glpi_plugin_fields_computerodpowiedzialnymaterialnies` (
  `id`                                      int unsigned NOT NULL AUTO_INCREMENT,
  `items_id`                                int unsigned NOT NULL DEFAULT 0,
  `itemtype`                                varchar(255) NOT NULL DEFAULT 'Computer',
  `plugin_fields_containers_id`             int unsigned NOT NULL DEFAULT 0,
  `users_id_odpowiedzialnymaterialniefield` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unicity` (`items_id`, `itemtype`, `plugin_fields_containers_id`),
  KEY `users_id_odpowiedzialnymaterialniefield` (`users_id_odpowiedzialnymaterialniefield`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
