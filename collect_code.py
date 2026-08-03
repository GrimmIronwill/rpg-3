#!/usr/bin/env python3
"""
Скрипт для рекурсивного сбора содержимого файлов с заданными расширениями
из одной или нескольких папок в один текстовый файл для отладки/ревью.

Примеры:
    python collect_code.py ./src -e .gd .cs .txt
    python collect_code.py ./addons/gd_database ./scripts ./src -e .gd .cs -o scripts_debug.txt --relpath
"""

import argparse
from pathlib import Path


def collect_files(
    entry_dirs: list[str],
    extensions: list[str],
    output_file: str = "debug.txt",
    separator_style: str = "filename",
) -> None:
    """
    Рекурсивно обходит entry_dirs, находит все файлы с указанными расширениями
    и записывает их содержимое в output_file.

    :param entry_dirs:      Список папок — точек входа для поиска.
    :param extensions:      Список расширений, каждое с точкой или без.
    :param output_file:     Имя выходного файла, создаётся рядом со скриптом.
    :param separator_style: "filename" — только имя файла,
                            "relpath"  — относительный путь от соответствующей entry_dir.
    """

    # Выходной файл — в директории, где лежит сам скрипт
    script_dir = Path(__file__).resolve().parent
    output_path = script_dir / output_file
    output_path = output_path.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Проверяем входные папки
    entry_paths: list[Path] = []

    for entry_dir in entry_dirs:
        entry_path = Path(entry_dir).resolve()

        if not entry_path.is_dir():
            print(f"[ОШИБКА] Директория не найдена: {entry_path}")
            continue

        entry_paths.append(entry_path)

    if not entry_paths:
        print("[ОШИБКА] Не найдено ни одной корректной директории для поиска.")
        return

    # Нормализуем расширения: каждое должно начинаться с точки
    norm_extensions = []

    for ext in extensions:
        ext = ext.strip()

        if not ext:
            continue

        if not ext.startswith("."):
            ext = f".{ext}"

        norm_extensions.append(ext)

    if not norm_extensions:
        print("[ОШИБКА] Не указано ни одного корректного расширения.")
        return

    # Собираем уникальные пути файлов.
    # dict нужен, чтобы запомнить, из какой entry_dir файл был найден.
    found_files_map: dict[Path, Path] = {}

    for entry_path in entry_paths:
        for ext in norm_extensions:
            for filepath in entry_path.rglob(f"*{ext}"):
                if not filepath.is_file():
                    continue

                filepath = filepath.resolve()

                # Не добавляем сам выходной файл, если он вдруг лежит внутри одной из папок поиска
                if filepath == output_path:
                    continue

                # Если папки поиска пересекаются, один и тот же файл не будет продублирован
                if filepath not in found_files_map:
                    found_files_map[filepath] = entry_path

    found_files = sorted(
        found_files_map.items(),
        key=lambda item: (str(item[1]).lower(), str(item[0]).lower()),
    )

    if not found_files:
        print(f"[ИНФО] Файлы с расширениями {norm_extensions} не найдены.")
        print("[ИНФО] Папки поиска:")
        for entry_path in entry_paths:
            print(f"       {entry_path}")
        return

    files_written = 0
    files_skipped = 0

    with open(output_path, "w", encoding="utf-8") as out:
        for i, (filepath, entry_path) in enumerate(found_files):
            # Заголовок-разделитель
            if separator_style == "relpath":
                relpath = filepath.relative_to(entry_path)

                # Если папок несколько — добавляем имя корневой папки,
                # чтобы было понятно, откуда файл.
                if len(entry_paths) > 1:
                    label = Path(entry_path.name) / relpath
                else:
                    label = relpath

                label = label.as_posix()
            else:
                label = filepath.name

            # Разделитель между файлами
            if i > 0:
                out.write("\n")

            out.write(f"{'=' * 60}\n")
            out.write(f"{label}\n")
            out.write(f"{'=' * 60}\n")

            try:
                content = filepath.read_text(encoding="utf-8")
                out.write(content)

                # Гарантируем перевод строки в конце файла
                if content and not content.endswith("\n"):
                    out.write("\n")

                files_written += 1

            except Exception as e:
                out.write(f"[ОШИБКА ЧТЕНИЯ: {e}]\n")
                files_skipped += 1

    print(f"[ГОТОВО] Собрано файлов: {files_written}, пропущено: {files_skipped}")
    print(f"         Результат: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Собирает содержимое файлов с заданными расширениями из одной или нескольких папок в один текстовый файл."
    )

    parser.add_argument(
        "entry_dirs",
        nargs="+",
        help="Одна или несколько папок для рекурсивного поиска.",
    )

    parser.add_argument(
        "-e",
        "--extension",
        nargs="+",
        default=[".gd"],
        help="Расширения файлов для поиска. По умолчанию: .gd. Можно перечислить несколько через пробел.",
    )

    parser.add_argument(
        "-o",
        "--output",
        default="debug.txt",
        help="Имя выходного файла. По умолчанию: debug.txt.",
    )

    parser.add_argument(
        "--relpath",
        action="store_true",
        help="Показывать относительный путь вместо имени файла в заголовках.",
    )

    args = parser.parse_args()

    collect_files(
        entry_dirs=args.entry_dirs,
        extensions=args.extension,
        output_file=args.output,
        separator_style="relpath" if args.relpath else "filename",
    )


if __name__ == "__main__":
    main()
