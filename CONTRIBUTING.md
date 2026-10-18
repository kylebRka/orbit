# Contributing

Open `Package.swift` in Xcode or build with `./scripts/build.sh debug`. Run `swift test` before submitting changes. Install FFmpeg with Homebrew to run the real media tests.

Keep native platform behavior, contextual formats and preservation of original files. Add focused coverage for changes to format routing, filenames, media arguments and cancellation. Use system colors; do not introduce a fixed accent override. Keep Russian and English README files aligned.

Do not commit personal media, signing credentials, generated builds or user paths. Use synthetic fixtures in temporary directories and remove them after tests. UI changes should pass the manual checklist in `docs/INTERACTION.md`.

## По-русски

Откройте `Package.swift` в Xcode или выполните `./scripts/build.sh debug`. Перед отправкой изменений запустите `swift test`; FFmpeg нужен для настоящих медиатестов. Сохраняйте оригиналы, используйте системные цвета и синхронно обновляйте оба README. Не добавляйте личные файлы и ключи подписи. Изменения интерфейса проверяйте по `docs/INTERACTION.md`.
