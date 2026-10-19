# Validation / Проверка

Date / Дата: 2026-10-19.
Environment / Среда: macOS 27.0.1, Apple Silicon, Swift 6.4, FFmpeg 9.0.2.

## 0.3.0 / Проверка обновления

- 36 automated tests, zero failures. New coverage: timecode/range boundaries, accurate FFmpeg arguments, actual video/audio trims, muted video, audio extraction, native AVFoundation export, collision protection, waveform decoding, temporary preview cleanup, contextual menu catalog, wheel accessibility and safe moves.
- Native UI: main-window Tools → Trim and wheel Tools → Trim both open the same video editor. Start/end handles, exact time fields, playback and export exercised with disposable generated media.
- UI-created silent video: 2.000–7.500 seconds → a 5.500-second MP4 with no audio stream; original remains 12 seconds with audio.
- UI-created audio: 2.600–9.000 seconds → a 6.400-second M4A; waveform decoded from the source.
- Floating Quick Look opens and closes correctly. All three wheel pages and their permanent key hints exposed through accessibility; regular Liquid Glass improves text contrast.
- Release build, ZIP packaging, Info.plist validation and bundle verification completed locally.

36 тестов проходят. Через интерфейс проверены вход в редактор из окна и круга, маркеры, поля времени, воспроизведение, сохранение видео 5,5 с без звука и аудио 6,4 с, настоящая волна, три страницы круга и просмотр поверх окон. Исходники не заменены.

## Previous baseline / Предыдущая проверка

Version / Версия: 0.2.0, 2026-10-18.

- 23 automated tests, zero failures; no media tests skipped.
- Native release build and ZIP packaging completed.
- Regression tests verify no main-window activation or alert on background completion/failure, stale selection cleanup, cancellation, local-file drop validation, language persistence and quiet-login event detection.
- Launch at login enabled through SMAppService on the installed app. English interface/menu switching verified in the native UI, then returned to System language.
- Application bundle signature verification and property-list validation passed.
- File picker → native wheel → image conversion → result displayed in the main window.
- Wheel navigation with Tab, arrows and Return; Escape cancellation.
- Native accessibility buttons exposed and activated successfully.
- Background editor preview, default Orbit logo at bottom right, position change, disabling the logo, and actual PNG saving.
- Both macOS privacy permissions enabled with user confirmation. Rebuilt ad-hoc apps can require removing and re-adding their Accessibility entry.

23 теста проходят без ошибок и пропусков. Сборка, архив, локальная подпись и Info.plist проверены. Через интерфейс проверены выбор изображения, круг, запуск конвертации из сектора, клавиатура, доступные кнопки, редактор фона, стандартный логотип, смена положения, отключение и сохранение PNG. Оба системных разрешения включены с подтверждением пользователя.

## Still manual / Требует ручной проверки

The computer-control interface cannot reliably hold a standalone Shift key during a native drag. A full physical Shift/Command/Control → move → release/drop flow is therefore **not verified** by the UI automation run. Test it with a physical keyboard and mouse in Finder, on the desktop, and with native local-file drags from other apps. Cross-app compatibility depends on the source supplying a real file URL.

Инструмент управления компьютером не позволяет надёжно удерживать отдельный Shift во время системного перетаскивания. Полная последовательность Shift/Command/Control → движение → отпускание/drop **не подтверждена** автоматической UI-проверкой. Её нужно проверить физической клавиатурой и мышью в Finder, на рабочем столе и в совместимых сторонних приложениях.

Also pending: actual AirDrop transmission to another device, Terminal integration and Copy/Copy Path clipboard behavior; manual accent/theme switching, multiple displays/Spaces, VoiceOver navigation, custom-logo import across image formats, and testing on macOS 15/26 and Intel. The native APIs and keyboard alternatives are implemented, but those environments were not available in this pass. CI status is available in the repository’s Actions tab.

Также не проверены реальная передача AirDrop, открытие Terminal и поведение буфера обмена Copy/Copy Path; смена системного акцента/темы, несколько дисплеев/Spaces, навигация VoiceOver, импорт собственных логотипов разных форматов, macOS 15/26 и Intel. Статус CI доступен во вкладке Actions репозитория.

A real logout/reboot was not performed; the macOS login-item service reports the installed app as enabled.
Выход из системы/перезагрузка не выполнялись; системная служба автозапуска показывает установленное приложение как включённое.
