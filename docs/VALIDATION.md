# Validation / Проверка

Date / Дата: 2026-10-18.
Environment / Среда: macOS 27.0.1, Apple Silicon, Swift 6.4, FFmpeg 9.0.2.

## Completed / Выполнено

- 14 automated tests, zero failures; no media tests skipped.
- Native release build and ZIP packaging completed.
- Application bundle signature verification and property-list validation passed.
- File picker → native wheel → image conversion → result displayed in the main window.
- Wheel navigation with Tab, arrows and Return; Escape cancellation.
- Native accessibility buttons exposed and activated successfully.
- Background editor preview, default Orbit logo at bottom right, position change, disabling the logo, and actual PNG saving.
- Both macOS privacy permissions enabled with user confirmation. Rebuilt ad-hoc apps can require removing and re-adding their Accessibility entry.

14 тестов проходят без ошибок и пропусков. Сборка, архив, локальная подпись и Info.plist проверены. Через интерфейс проверены выбор изображения, круг, запуск конвертации из сектора, клавиатура, доступные кнопки, редактор фона, стандартный логотип, смена положения, отключение и сохранение PNG. Оба системных разрешения включены с подтверждением пользователя.

## Still manual / Требует ручной проверки

The computer-control interface cannot reliably hold a standalone Shift key during a native drag. A full physical Shift → move → release/drop flow is therefore **not verified** by the UI automation run. Test it with a physical keyboard and mouse in Finder, on the desktop, and with native local-file drags from other apps. Cross-app compatibility depends on the source supplying a real file URL.

Инструмент управления компьютером не позволяет надёжно удерживать отдельный Shift во время системного перетаскивания. Полная последовательность Shift → движение → отпускание/drop **не подтверждена** автоматической UI-проверкой. Её нужно проверить физической клавиатурой и мышью в Finder, на рабочем столе и в совместимых сторонних приложениях.

Also pending: manual accent/theme switching, multiple displays/Spaces, VoiceOver navigation, custom-logo import across image formats, and testing on macOS 15/26 and Intel. The native APIs and keyboard alternatives are implemented, but those environments were not available in this pass. GitHub CI has been configured locally and has not run on GitHub. Developer ID signing/notarization and public distribution are not performed.

Также не проверены вручную смена системного акцента/темы, несколько дисплеев/Spaces, навигация VoiceOver, импорт собственных логотипов разных форматов, macOS 15/26 и Intel. CI подготовлен, но на GitHub не запускался. Подпись Developer ID, нотариализация и публичный релиз не выполнялись.
