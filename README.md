# Bootstrap для Ubuntu Desktop 26.04 LTS

Скрипт настраивает уже установленную **Ubuntu Desktop 26.04 LTS (Resolute), amd64**. Для запуска нужны интернет и учётная запись с доступом к `sudo`. GNOME и Files (Nautilus) остаются штатными.

## Первый запуск

Установите Ubuntu, войдите в GNOME и распакуйте архив. В терминале перейдите в распакованную папку. Запускайте скрипт под своим пользователем, чтобы VS Code и его расширения использовали ваш профиль.

```bash
cd ubuntu-bootstrap
bash bootstrap.sh --all --dry-run
bash bootstrap.sh --all
bash bootstrap.sh --all --check
```

На компьютере **без NVIDIA** вместо `--all` используйте `--all --skip driver,cuda,gpu`. Тот же список исключений используйте с `--check`.

При установке AmneziaVPN откроется окно официального установщика. Для установки позже используйте `--all --skip amnezia`, затем запустите `bash bootstrap.sh --only amnezia` в GNOME.

Для планирования оставьте примерно **30 ГБ свободного места после установки Ubuntu**. Грубая оценка для полного набора составляет 5–9 ГБ загрузок и 12–22 ГБ на диске. Основную долю занимает CUDA. ISO Ubuntu, снимки Timeshift, дополнительные Docker-образы и данные проектов считаются отдельно.

## Файлы в архиве

| Файл | Назначение |
| --- | --- |
| `bootstrap.sh` | Входная точка, выбор модулей, запуск и сводка |
| `modules/core.sh` | Списки пакетов Ubuntu, инвентаризация и проверка источников |
| `modules/gpu.sh` | Драйвер, переключение графики, CUDA, Docker и проверка GPU |
| `modules/apps.sh` | Приложения, Python-инструменты и расширения VS Code |
| `vscode-extensions.txt` | Список ID расширений, по одному на строку |
| `README.md` | Эта инструкция |

## Модули

| Модуль | Что входит |
| --- | --- |
| `desktop` | GNOME Tweaks, Extension Manager, Terminator и проверка штатных компонентов GNOME |
| `base` | Git, curl, wget, сертификаты, GnuPG, GCC/G++/Make, CMake, Ninja, Meson, pkgconf, Clang, jq, tree, ripgrep, fd-find, fzf, rsync, tmux, zip/unzip/7zip, ncdu, btop, fastfetch, OpenSSH Client, ShellCheck |
| `hardware` | lm-sensors, smartmontools, nvme-cli, pciutils, usbutils, lshw, fwupd, nvtop, GParted, Timeshift |
| `network` | bind9-dnsutils, traceroute, mtr-tiny, iperf3, nmap, UFW |
| `dev` | VS Code, отладчики, FFmpeg, Poppler |
| `vscode-extensions` | 28 расширений из `vscode-extensions.txt` через Visual Studio Marketplace |
| `python` | Python, venv, заголовки, pipx и пользовательские uv/uvx в `~/.local/bin` |
| `office` | LibreOffice, интеграция с GNOME, русский интерфейс и справка |
| `driver`, `cuda` | Драйвер NVIDIA из Ubuntu, CUDA 13.1 и проверка сборки через nvcc |
| `graphics` | Обнаружение нескольких GPU, запуск службы GNOME для выбора GPU и инструменты PRIME для связки NVIDIA с другой графикой |
| `docker`, `gpu` | Docker CE, CLI, containerd, Compose, Buildx, NVIDIA Container Toolkit и тест GPU в контейнере |
| `chrome`, `arduino` | Google Chrome и Arduino IDE 2 с ярлыком GNOME |
| `media` | Telegram, Spotify, VLC и OBS Studio |
| `happ`, `amnezia` | HAPP Proxy Utility и AmneziaVPN |

```bash
bash bootstrap.sh --only office,python
bash bootstrap.sh --only vscode-extensions
bash bootstrap.sh --only docker,gpu --check
bash bootstrap.sh --all --skip arduino,happ,amnezia --dry-run
```

Списки в `--only` и `--skip` разделяются запятыми без пробелов. Выбранные модули идут в фиксированном порядке. При запуске `gpu` отдельно нужны уже установленный Docker CE и работоспособный драйвер для проверки. APT нужны штатные компоненты Ubuntu `main`, `restricted`, `universe` и `multiverse`.

Модуль `vscode-extensions` входит в `--all` и запускается после `dev`. Для отдельного запуска нужен установленный VS Code. Расширения ставятся для текущего пользователя, уже установленные пропускаются. Файл содержит ID, поэтому VS Code выбирает совместимые версии из Marketplace. Проверка выводит установленные версии в лог. В список входят Ruff, ShellCheck, markdownlint и Container Tools. Настройки редактора, горячие клавиши и сниппеты переносятся через экспорт профиля VS Code. ESP-IDF и TeX могут потребовать отдельной установки инструментов, которые используют расширения.

## Что происходит при запуске

- `--dry-run` печатает статический план. `--check` проверяет установленные пакеты и команды, компилирует временный CUDA-файл и запускает одноразовый тестовый контейнер из локального образа. Первый запуск модуля `gpu` скачивает образ `ubuntu:26.04`.
- Лог и сводка каждого запуска лежат в отдельном каталоге внутри `${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-bootstrap`. Инвентаризация включает ядро, диски, видеоадаптеры PCI и VRAM после загрузки драйвера. Коды выхода — 0 при успехе, 1 при ошибке модуля, 75 при ожидаемом ручном шаге или перезагрузке.
- Рабочий драйвер сохраняется. При новой установке ветку подбирает `ubuntu-drivers`. Если для того же оборудования доступен закрытый вариант рекомендованной ветки, скрипт выбирает его. На старой карте может потребоваться другая ветка CUDA или драйвера. Для установки и проверки Docker используется `sudo`.
- Ubuntu, Google, Docker и NVIDIA Container Toolkit используют подписанные индексы APT. Для сторонних APT-источников проверяется отпечаток ключа и выделяется отдельный keyring. Microsoft VS Code, Telegram и Spotify идут через подписанный Snap Store. VS Code использует режим classic.
- Arduino IDE, uv, Happ и AmneziaVPN скачиваются из официальных стабильных релизов GitHub. Скрипт требует SHA-256 из метаданных релиза и проверяет файл перед использованием. SHA-256 здесь подтверждает соответствие файла метаданным GitHub. В лог попадают точные ссылки и хеши. Ветка CUDA закреплена на 13.1, APT и Snap получают штатные обновления. Установка повторно использует имеющиеся приложения. Полного снимка версий для побайтового воспроизведения нет.
- Arduino IDE размещается под `/opt/ubuntu-bootstrap/arduino`. Фирменный помощник песочницы Electron получает владельца root и режим 4755. Если для загрузки прошивки нужен доступ к последовательному порту, выполните `sudo usermod -aG dialout "$USER"` и заново войдите в GNOME.
- Timeshift устанавливается, а место и расписание снимков выбираются в его интерфейсе. UFW устанавливается с текущим состоянием firewall. Для iperf3 задана установка без автоматического запуска сервера. VPN и прокси проверяются по установке и, для AmneziaVPN, состоянию службы. Для проверки подключения нужны ваши профили.

## Проверка и повторный запуск

В конце запуска скрипт печатает пути к `report.txt` и `install.log`. В сводке `OK` означает, что проверка модуля прошла, `FAILED` указывает на ошибку, `PENDING` — на отложенный шаг. При ошибке откройте лог, исправьте причину и повторите только нужные модули.

| Ситуация | Что сделать |
| --- | --- |
| После установки драйвера модуль ждёт перезагрузки | Перезагрузитесь. Если Ubuntu запросит регистрацию MOK, завершите её на экране загрузки. Выполните `bash bootstrap.sh --only driver,graphics,cuda,gpu`. |
| Скрипт не нашёл однозначно рекомендованный драйвер | Посмотрите вывод `ubuntu-drivers devices`. Установите совместимый драйвер средствами Ubuntu и проверьте `nvidia-smi`. |
| Образ для проверки GPU ещё отсутствует | Запустите `bash bootstrap.sh --only gpu`. Модуль скачает тестовый образ и проверит GPU внутри контейнера. |
| APT не находит пакет | Проверьте доступность сети и включение компонентов `main`, `restricted`, `universe`, `multiverse`. Повторите нужный модуль после исправления. |
| Пропущена AmneziaVPN | Из терминала GNOME запустите `bash bootstrap.sh --only amnezia` и завершите установку в окне приложения. |

## Встроенная и дискретная графика

`--all` запускает `graphics` после `driver`. Если PCI показывает две видеокарты или больше, модуль устанавливает и запускает `switcheroo-control`. Для связки NVIDIA с другой графикой он также устанавливает `nvidia-prime` и выводит текущий профиль. Переключение профиля остаётся ручным. После установки нового драйвера может понадобиться перезагрузка и `bash bootstrap.sh --only graphics --check`.

На гибридном ноутбуке с NVIDIA проверьте `prime-select query`. Для режима по запросу, если его поддерживает ноутбук, выполните `sudo prime-select on-demand` и перезагрузитесь. После входа в GNOME найдите в меню ярлыка приложения пункт запуска на дискретной видеокарте. В терминале `switcherooctl list` показывает доступные GPU, а `switcherooctl launch -g N программа` запускает приложение на GPU с номером N из списка.

На ПК с монитором, подключённым к NVIDIA, выбор GPU для приложения и подключение экрана управляются отдельно. При одной видеокарте модуль пропускает настройку переключения. Если NVIDIA отсутствует, запустите `bash bootstrap.sh --all --skip driver,cuda,gpu`. На ноутбуках с MUX режим Hybrid в UEFI или фирменной настройке должен оставлять обе карты видимыми для Ubuntu.

## Перед переустановкой

Сохраните проекты, SSH-ключи, профили VPN/прокси и нужные данные Docker отдельно от системного диска. В установщике Ubuntu подойдёт вариант с минимальным набором приложений. Скрипт запускается после установки ОС и управляет добавлением выбранных компонентов.

## Источники

- [Ubuntu Desktop и драйвер NVIDIA](https://ubuntu.com/desktop/docs/en/latest/how-to/graphics/install-nvidia-drivers/)
- [CUDA Toolkit 13.1 в Ubuntu](https://packages.ubuntu.com/resolute/cuda-toolkit-13-1)
- [Docker Engine](https://docs.docker.com/engine/install/ubuntu/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [Ключ Google для Linux](https://www.google.com/linuxrepositories/)
- [Arduino IDE](https://github.com/arduino/arduino-ide/releases)
- [uv](https://github.com/astral-sh/uv/releases)
- [Happ](https://github.com/Happ-proxy/happ-desktop)
- [AmneziaVPN на Linux](https://docs.amnezia.org/documentation/installing-app-on-linux/)
- [Профили NVIDIA PRIME в Ubuntu](https://ubuntu.com/docs/steam/howto/dedicated-gpu/)
- [Служба switcheroo-control в Ubuntu 26.04](https://packages.ubuntu.com/resolute/switcheroo-control)

## Проверено

Проверены синтаксис Bash, выбор модулей, повторная установка расширений на имитации VS Code CLI и ветки настройки графики на имитации нескольких конфигураций. Полный прогон на чистой Ubuntu с NVIDIA и проверка физических видеовыходов остаются за пределами этих проверок.
# ubuntu-bootstrap
