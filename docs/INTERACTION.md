# Interaction & architecture / Управление и устройство

## Interaction model

Orbit is a local utility with a conventional main window and a non-activating floating panel. A Finder action has four states:

```text
Idle → Shift down in Finder → Read one selection → Inspect file → Show wheel
Show wheel → Pointer inside a sector → Highlight candidate
Show wheel → Shift up, no drag → Convert candidate or cancel
Show wheel → Native file drop → Consume the copy operation → Convert
Show wheel → Escape / center / outside / abandoned drag → Cancel
```

Outside Finder, the app reads a single local file URL from the active native drag pasteboard while Shift is held. It ignores unchanged/stale drag pasteboard contents and validates the dropped URL against the inspected file. Finder Automation is unnecessary for those drags. File promises and web links are not supported. The desktop is managed by Finder and uses the same selection gesture.

The anchor is captured on Shift down. Inspection is asynchronous; if Shift is released before it finishes, the result is discarded. Moving the pointer does not move the wheel. The wheel is clamped to the display's visible area. Sector zero is at twelve o'clock; the center and outside edge do not select a format. Only a native drop of the same file that was inspected is accepted during a Finder drag.

Formats, tools and file actions are separate pages of the same wheel. The permanent top strip shows ⇧ Convert / ⌘ Tools / ⌃ Actions. Newly pressed Command or Control switches an open wheel to tools/actions; Shift returns to formats. Tab or a center click cycles pages. A normal sector click invokes an item. The main window exposes the same catalog through a segmented control. The initial preview wheel is illustrative, not a second live conversion control.

For a selected Finder file, releasing Shift commits the highlighted item. A native drag may start a wheel using Shift, Command or Control; releasing that key leaves it open until the native drop or cancellation. A drag ending while inspection is pending invalidates the pending result. Menu modifiers are only observed during an open wheel or an active local-file drag, so ordinary Command/Control shortcuts elsewhere do not open menus.

## Structure

| File / directory | Responsibility |
|---|---|
| `Sources/OrbitCore/FileTypes.swift` | Format catalog, file descriptions, collision-free publication |
| `Sources/OrbitCore/RadialGeometry.swift` | Pointer → sector mapping |
| `Sources/OrbitCore/ConversionEngine.swift` | Content inspection, images, PDF, AVFoundation and FFmpeg arguments |
| `Sources/OrbitCore/CommandRunner.swift` | Direct subprocess arguments, cancellation, private temporary logs |
| `Sources/OrbitCore/MediaEditing.swift` | Timecode parsing, validated trim ranges and safe clip export |
| `Sources/Orbit/GestureController.swift` | Event observers, Finder gesture state, panel placement and drops |
| `Sources/Orbit/WheelView.swift` | Native drawing, hover, keyboard and drag destination |
| `Sources/Orbit/AppModel.swift` | UI state, async jobs and Finder selection |
| `Sources/Orbit/MainView.swift` | Main window, settings and recent results |
| `Sources/Orbit/ImageTools.swift` | Native image editor, background compositing and corner watermark |
| `Sources/Orbit/MediaTrimView.swift` | Media playback, bounded waveform decoding, frame strip and trim controls |
| `Sources/Orbit/FileActions.swift` | Shared menu catalog and native file actions |
| `scripts/` | Reproducible icon generation and application packaging |

On macOS 26+, `NSGlassEffectView` with the regular style supplies native Liquid Glass behind the ring, shortcut strip and hint, with enough material to keep text legible. macOS 15 falls back to `NSVisualEffectView`. Segments use translucent fills and subtle edge highlights; Reduce Transparency uses opaque fills.

No package dependencies. System frameworks include AppKit, SwiftUI, ImageIO, CoreGraphics, UniformTypeIdentifiers, PDFKit, AVFoundation/AVKit, QuickLookUI and ApplicationServices. FFmpeg is an optional external executable, invoked without a shell; filenames are passed as individual arguments. Remote input protocols are not enabled. No server runs in the background.

The app reads Finder's selection using a fixed AppleScript with no path interpolation. Accessibility permission enables observation of global key events. Orbit does not synthesize keystrokes, read the general clipboard or record the screen. Copy/Copy Path write to the clipboard only when selected. Finder selection gestures require Finder in the foreground and enabled integration; native local-file drags use their separate drag pasteboard. On-disk history is not maintained. Conversion completion updates the result and the menu-bar status without activating the app. Background failures stay in the menu bar until the user chooses to view them. Normal window operations still show errors in the current UI.

`SMAppService.mainApp` manages launch at login. Startup Apple Events identify login launches so the app leaves its main window closed. An explicit Settings language choice is persisted; System is the default.

Dynamic `NSColor.controlAccentColor` and SwiftUI accent styling follow the system accent, including color-change notifications for the wheel. System background/text colors follow the current appearance. The icon retains the app's blue/cyan identity. Animation is not required to use the interface. Standard controls and keyboard alternatives accompany the custom wheel.

Image operations create new pixel data and strip source metadata. PDF images export every page together into an independently named directory. Output publication fails rather than replacing a file another writer has just created. FFmpeg and native export errors surface in the UI; unfinished temporary outputs are removed during normal error/cancel handling.

Media trimming validates finite ordered start/end times against a fresh inspection of the source. FFmpeg seeks accurately while re-encoding; the native fallback uses `AVAssetExportSession.timeRange`. Silent native video uses a video-only composition. Clips publish through the same collision-safe output helper with a `-trimmed` suffix. The shared AppModel job tracks cancellation/quit and closes only the editor on success. Playback stops at the selected end. `AVAssetReader` decodes mono float PCM into 160 waveform peaks with bounded per-buffer storage. Video uses eight real thumbnails. Unsupported playback gets a temporary FFmpeg proxy, cancelled/removed on editor closure; the original, not the proxy, is exported.

File actions are explicit: AirDrop uses the system recipient interface; Float uses QuickLookUI at floating window level; Copy writes the file URL; Move asks for a directory and refuses collisions; Terminal receives a directory URL through NSWorkspace. Move intentionally relocates the original; conversion and editing never do.

## Manual checklist

Use disposable sample files and grant permissions yourself. Automated checks do not grant macOS privacy permissions.

- [ ] Choose a PNG in Orbit. Convert it to JPG; compare dimensions and reveal the result.
- [ ] Open the wheel. Navigate with arrows, Return, Tab and Escape.
- [ ] Enable both Finder permissions in Settings. Select one file in Finder, hold Shift, move and release over a sector.
- [ ] Start dragging a file, hold Shift and drop onto a sector. Confirm that the original file remains where it was.
- [ ] Release a drag in the center/outside. Confirm that no conversion starts. A drop outside Orbit follows Finder's normal behavior.
- [ ] Select several files or a folder. Confirm no conversion wheel appears.
- [ ] Drag a local file from a compatible non-Finder app while holding Shift. Reject web links and unresolved file promises.
- [ ] Try on a second display, near every edge, on the desktop and in another Space.
- [ ] Change the macOS accent color and appearance. Check the main window and open wheel.
- [ ] Crop an image, rotate it and try compression of an already small JPEG.
- [ ] Add a background: change color, padding, corners and shadow.
- [ ] Keep Orbit's logo at bottom right; turn it off; move it to the other corners; import a transparent custom logo. Confirm the saved PNG matches the preview.
- [ ] Convert a multi-page PDF to images and a text PDF to TXT; reject a scanned PDF with no text.
- [ ] Convert an audio/video file and cancel a longer media job. Confirm no output is published after cancellation.
- [ ] Open audio/video → Tools → Trim in the main window and in the wheel. Move handles, enter timecodes, scrub, play/pause and use start/end-at-playhead and Reset.
- [ ] Check audio waveform/video thumbnails, silent video, audio extraction and numbered clip output. Cancel export and close a proxy preview while preparing it.
- [ ] Switch ⇧ / ⌘ / ⌃ and Tab while the wheel is open; release the modifier during a native drag, then drop or cancel. Test a slow inspection after the drag ended.
- [ ] Test Float, Copy/Copy Path, Move with a disposable file (including a collision), Terminal and the AirDrop recipient dialog. Sending to another device requires the user's chosen recipient.
- [ ] Switch System / English / Russian; check both the main window and menu-bar commands. Enable Launch at login in Settings.
- [ ] Convert from Finder/desktop; confirm the active app does not change on completion or error.
- [ ] Close the main window, reopen from the menu bar, pause the gesture and quit.

## Модель взаимодействия

Shift в Finder фиксирует положение курсора и считывает один выбранный файл. После проверки содержимого появляется круг. Движение выбирает сектор; отпускание Shift запускает действие, если файл не перетаскивается. Во время перетаскивания нужен настоящий системный drop: Orbit принимает его как копирование, затем создаёт результат. Центр, область за кругом и Escape отменяют выбор. Если Shift отпущен до завершения проверки, меню не открывается.

Верхняя панель постоянно показывает ⇧ Форматы / ⌘ Инструменты / ⌃ Действия. Command и Control переключают открытый круг; Shift возвращает форматы. Tab и нажатие на центр переключают три меню. Стрелки и Enter работают в меню Orbit. При нативном перетаскивании можно открыть меню любой из трёх клавиш, затем отпустить клавишу: круг остаётся до броска или отмены. Обычные кнопки и выбор файла остаются доступными без интеграции Finder.

Обрезка аудио/видео открывает общий редактор из окна или круга. Предпросмотр, настоящая волна/кадры, маркеры и поля времени управляют диапазоном. Результат кодируется из оригинала, сохраняется с суффиксом `-trimmed` и не заменяет существующие файлы. Для несовместимого предпросмотра создаётся временная локальная копия; закрытие редактора останавливает её подготовку и удаляет её. Перемещение файла — отдельная явная команда, которая намеренно меняет расположение оригинала.

Проект состоит из ядра `OrbitCore` с форматами, геометрией, проверкой файлов и конвертацией и приложения `Orbit` с окнами, событиями и редактором. Внешних Swift-пакетов нет. FFmpeg запускается напрямую, без оболочки. Пути не вставляются в AppleScript; используется фиксированный запрос выделения Finder.

Системные цвета используются динамически. Сине-голубой значок сохраняет фирменный цвет, а выделения меняются вместе с акцентом macOS. Оригиналы сохраняются конвертацией и редактором Orbit. Разметка через «Просмотр» открывает оригинал во внешнем редакторе, где действуют его правила сохранения.

## Ручная проверка

Чек-лист выше включает проверку выбора и конвертации, стрелок/Enter/Tab/Escape, разрешений Finder, настоящего перетаскивания без перемещения оригинала, центра и внешней области, нескольких файлов, второго монитора и Spaces, системного цвета и темы, обрезки и сжатия, фона, всех углов логотипа, собственного прозрачного логотипа, PDF, отмены конвертации и строки меню. Разрешения macOS выдаёт пользователь; автоматические тесты их не выдают.
