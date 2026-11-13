<div align="center">

# zapret.installerd2

### Модульный установщик и панель управления [zapret](https://github.com/bol-van/zapret) / [zapret2](https://github.com/bol-van/zapret2)

</div>

Форк [Snowy-Fluffy/zapret.installer](https://github.com/Snowy-Fluffy/zapret.installer) с изоморфной архитектурой продуктов и автоматическим обнаружением модулей.

Можно установить оба продукта, но одновременно запускать их или включать автозапуск обоих нельзя: они управляют сетевыми правилами.

## Возможности

- Автообнаружение продуктов — сканирование `products/*/product.env`
- Проверка конфигов перед применением
- Подстановка переменных при импорте: `%BIN%`, `%LISTS%`, `%LUA%`
- Единое меню управления для всех установленных продуктов
- Проверка здоровья системы: зависимости, бинарники, сервисы
- Модульная архитектура без правок основного кода для добавления новых продуктов

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

## Переход на zapret2

В панели выберите установку `zapret2`. В системе с systemd установщик запросит подтверждение остановки `zapret` и отключения его автозапуска. При ошибке переключения он попытается восстановить прежнее состояние службы. Старая установка не удаляется. После установки проверьте `systemctl status zapret2` и работу нужных сайтов; сам факт запуска не гарантирует обход блокировок. На других init-системах остановите старую службу и отключите её автозапуск вручную.

Linux-движок устанавливается из `bol-van/zapret2`. Встроенный `products/zapret2/default.conf` адаптирует отдельные стратегии Discord и YouTube из Windows-пресета `Default v5` репозитория [zapret2-youtube-discord](https://git3.zapret.moe/zapretdiscordyoutube/zapret2-youtube-discord/src/branch/main/presets); это не полный перенос пресета. Вместо отсутствующего в Linux-релизе `tls_clienthello_max_ru.bin` используется Google ClientHello, поэтому поведение отличается от оригинала. Сторонний репозиторий конфигов и GitHub-аккаунт не требуются.

При установке и обновлении zapret2 установщик скачивает закреплённую версию `zapret-multishake.lua` с зеркал `git3`, `git2`, `git4`–`git6`, затем `git` и `cwdnvtsqdc.zapret.moe`, проверяет SHA-256 и сохраняет отдельно от штатных Lua-файлов. Если ни одно зеркало не доступно или файл не прошёл проверку, установка или обновление прерывается. Для загрузки релизов zapret и blockcheckw при недоступности GitHub используется `cdn.gh-proxy.org`: сторонний сервис видит запросы и может изменять данные. Проверка SHA-256 Lua на эту загрузку релизов не распространяется. Встроенный профиль применяет `hostfakesplit_multi` к Discord Gateway; успешный запуск не гарантирует обход на конкретной сети. Обновление сохраняет существующий `/opt/zapret2/config` и не включает новую стратегию автоматически.

## Поддерживаемые системы

- Debian, Ubuntu, Mint
- Fedora
- Arch Linux, Artix Linux и производные
- Alt Linux
- Void Linux
- Gentoo Linux
- Redos Linux
- Oracle Linux
- OpenSUSE
- Alpine Linux
- OpenWrt

> [!IMPORTANT]
> Системы инициализации `runit`, `OpenRC` и `SysVinit` поддерживаются только частично.

## Добавление своего продукта

Создайте директорию `products/myproduct/` и добавьте в неё:

- `product.env` — переменные продукта (`PRODUCT_ID`, `PRODUCT_DIR`, `PRODUCT_SERVICE`, `PRODUCT_BIN_NAME`, ...)
- `init.sh` — функции инициализации и проверки
- `install.sh` — функции установки и обновления
- `uninstall.sh` — функция удаления
- `health.sh` — функции health-check и проверки обновлений

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
