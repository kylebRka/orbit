# Changelog

## 0.3.0

- Add audio/video trimming from the main window and the floating wheel: preview playback, real audio waveform/video frame strip, draggable range handles and precise timecodes.
- Save selected clips as MP4/MOV or M4A/MP3/WAV/FLAC according to the installed engine. Add silent video export and audio-only clip extraction.
- Add three menus with persistent shortcut hints: ⇧ Convert, ⌘ Tools, ⌃ Actions; Tab cycles menus and the center/top buttons support the mouse.
- Keep a native drag wheel open after releasing its shortcut until drop/cancel. Discard inspections for drags that already ended.
- Add AirDrop, Float, Copy, Move, Copy Path and Terminal actions; expose the same contextual tools/actions in the main window.
- Improve glass legibility and keep media tools available even when no alternative conversion format exists.
- Add safe range validation, cancellation/preview cleanup and regression coverage (36 tests).

### По-русски

- Обрезка аудио и видео из окна и круга: предпросмотр, звуковая волна/кадры, маркеры диапазона и точное время.
- Сохранение фрагмента в доступном формате, видео без звука и извлечение аудиофрагмента.
- Три меню с подсказками ⇧ / ⌘ / ⌃, переключение через Tab и кнопки в круге.
- Меню перетаскивания остаётся открытым после отпускания клавиши до броска или отмены.
- AirDrop, просмотр поверх окон, копирование файла/пути, безопасное перемещение и открытие папки в Terminal.
- Улучшена читаемость стекла, добавлены проверки диапазона, отмена и очистка временного предпросмотра. Всего 36 тестов.

## 0.2.0

- Keep Finder/desktop focus after conversion; no automatic main-window opening.
- Keep background failures in the menu bar instead of displaying a foreground alert.
- Add a macOS-managed launch-at-login switch and quiet login startup.
- Add persistent System / English / Russian language selection, including menus and tools.
- Clear stale file selections after failed inspections; accept only the inspected file in the wheel.
- Fix duplicate Tab handling, accessibility hit frames, and cleanup when quitting during conversion.
- Add app behavior regression tests.

## 0.1.0

- Contextual Finder conversion wheel with Shift and native drag-and-drop.
- Local image, PDF, audio and video conversion.
- System accent color, system appearance and Russian/English interface.
- Crop, rotate, JPEG compression, metadata and Preview integration.
- Gradient background editor with an optional corner logo and custom logo import.
- Safe output naming, media cancellation and session-only recent results.
- Swift package, app packaging script and macOS CI.
