<div align="center">

# zapret.installerd2

### Модульный установщик и панель управления [zapret](https://github.com/bol-van/zapret) / [zapret2](https://github.com/bol-van/zapret2)

</div>

Форк [Snowy-Fluffy/zapret.installer](https://github.com/Snowy-Fluffy/zapret.installer) с изоморфной архитектурой продуктов и автоматическим обнаружением модулей.

Поддерживает одновременную установку **zapret** (`nfqws`) и **zapret2** (`nfqws2`) с общей панелью управления.

## Возможности

* Автообнаружение продуктов — сканирование `products/*/product.env`
* Проверка конфигов перед применением
* Подстановка переменных при импорте: `%BIN%`, `%LISTS%`, `%LUA%`
* Единое меню управления для всех установленных продуктов
* Проверка здоровья системы: зависимости, бинарники, сервисы
* Модульная архитектура без правок основного кода для добавления новых продуктов

## Структура

```text
├── installer.sh          # Установщик: клонирует репозиторий, создаёт symlink
├── zapret-control.sh     # Точка входа панели управления
├── common/               # Общие модули: UI, сервисы, утилиты
└── products/
    ├── zapret/           # Продукт: zapret (nfqws)
    │   ├── product.env   # Метаданные продукта
    │   ├── init.sh       # Инициализация, health-check
    │   ├── install.sh    # Установка, обновление
    │   ├── uninstall.sh  # Удаление
    │   └── health.sh     # Проверка обновлений
    └── zapret2/          # Продукт: zapret2 (nfqws2)
        ├── product.env
        ├── init.sh
        ├── install.sh
        ├── uninstall.sh
        └── health.sh
```

## Установка

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/dirold2/zapret.installerd2/refs/heads/main/installer.sh)"
```

## Запуск панели управления

```bash
zapret
```

## Поддерживаемые системы

* Debian, Ubuntu, Mint
* Fedora
* Arch Linux, Artix Linux и производные
* Alt Linux
* Void Linux
* Gentoo Linux
* Redos Linux
* Oracle Linux
* OpenSUSE
* Alpine Linux
* OpenWrt

> [!IMPORTANT]
> Системы инициализации `runit`, `OpenRC` и `SysVinit` поддерживаются только частично.

## Добавление своего продукта

Создайте директорию `products/myproduct/` и добавьте в неё:

* `product.env` — переменные продукта (`PRODUCT_ID`, `PRODUCT_DIR`, `PRODUCT_SERVICE`, `PRODUCT_BIN_NAME`, ...)
* `init.sh` — функции инициализации и проверки
* `install.sh` — функции установки и обновления
* `uninstall.sh` — функция удаления
* `health.sh` — функции health-check и проверки обновлений

Продукт автоматически обнаружится при следующем запуске панели управления.

### Минимальный пример структуры

```text
products/myproduct/
├── product.env
├── init.sh
├── install.sh
├── uninstall.sh
└── health.sh
```

## Разработка

Архитектура проекта построена так, чтобы новые продукты добавлялись как отдельные модули, без изменений в ядре установщика. Общие функции, UI и сервисная логика вынесены в `common/`, а логика конкретного продукта — в `products/<name>/`.

## Баги и предложения

Сообщайте в [issues](https://github.com/Dirold2/zapret.installerd2/issues).
