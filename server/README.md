# Сервер приложения

FastAPI-сервер отвечает за регистрацию пользователей, управление сессиями и выдачу обновлений контента.

## Подготовка

Из корневой папки проекта:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r .\server\requirements.txt
Copy-Item .\server\.env.example .\server\.env
```

Перед публикацией замените `AUTH_SECRET` в `server/.env` на длинную случайную строку.

## Запуск

```powershell
python .\server\server.py --host 0.0.0.0 --port 8000
```

Документация API: `http://127.0.0.1:8000/docs`.

## Эндпоинты

- `GET /api/health` — проверка доступности;
- `POST /api/auth/register` — регистрация;
- `POST /api/auth/login` — вход;
- `POST /api/auth/refresh` — ротация refresh-токена;
- `POST /api/auth/logout` — завершение сессии;
- `GET /api/auth/me` — текущий пользователь;
- `GET /api/content` — защищённое получение контента.

## Тесты

```powershell
cd .\server
..\.venv\Scripts\python.exe -m pytest -q
```
