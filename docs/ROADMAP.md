# Roadmap / Планы развития

These are ideas, not features promised by the current build. Keep conversion one gesture away; add complexity only when it solves a clear workflow.

Это идеи развития, а не обещанные функции текущей сборки. Главная задача — конвертация одним жестом; усложнение должно решать понятную задачу.

| Idea / Идея | Why / Зачем |
|---|---|
| Batch conversion / Пакетная конвертация | A shared set of valid formats for all selected files, queue, cancel and per-file errors / Общие допустимые форматы, очередь, отмена и ошибки по файлам |
| Local OCR / Локальное распознавание текста | Scanned PDF and images to searchable PDF/TXT using Vision / Сканированные PDF и изображения в текст через Vision |
| Media presets / Пресеты медиа | Smaller video, resolution, frame rate, audio bitrate; show tradeoffs / Размер, разрешение, частота кадров и битрейт с понятным выбором качества |
| GIF/WebP and animation / Анимация и новые форматы | Preserve all frames and timing rather than silently flattening / Сохранить все кадры и длительности |
| Metadata controls / Управление метаданными | Explicitly preserve or remove fields, including GPS / Явное сохранение или удаление полей, включая GPS |
| True redaction / Необратимая редактура | Remove underlying PDF/image content instead of hiding it under a shape; verify extraction / Удалять содержимое, а не закрывать плашкой; проверять извлечение |
| Favorite formats / Избранные форматы | Most-used targets with a stable sector order / Частые форматы со стабильным расположением |
| Saved backgrounds / Пресеты фона | Reuse background and logo settings across sessions / Сохранять фон и настройки логотипа между запусками |
| Undo a result / Отмена результата | Move only the generated output to Trash, after checking its identity / Отправлять в корзину только созданный результат после проверки |
| Signed distribution / Подписанный релиз | Developer ID, notarization, a universal binary and an update channel / Developer ID, нотариализация, универсальная сборка и обновления |
| Login item / Запуск при входе | Explicit opt-in using ServiceManagement / Только по желанию пользователя через ServiceManagement |
| Finder Quick Action / Быстрое действие Finder | A conventional alternative to the global gesture / Привычная альтернатива глобальному жесту |

The current build intentionally avoids accounts, servers, automatic uploads and conversion of unrelated content types. Document conversion with layout fidelity requires a separate engine; renaming an extension is never a conversion.

Текущая сборка обходится без аккаунтов, серверов и автоматических загрузок. Конвертация офисных документов с сохранением вёрстки потребует отдельного движка. Простое переименование расширения не является конвертацией.
