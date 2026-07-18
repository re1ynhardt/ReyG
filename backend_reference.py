"""
Harmony backend — single-file reference implementation (Flask + SQLite).

Matches the REST contract expected by lib/services/remote_api_service.dart
in the Flutter app. This is a STARTING POINT, not production-hardened:
passwords are hashed but there's no rate limiting, email verification, etc.

Run it:
    pip install flask flask-cors boto3 werkzeug
    python backend_reference.py
    # -> serves on http://0.0.0.0:8000

Then in the Flutter app (lib/main.dart) switch to:
    final ApiService api = RemoteApiService(baseUrl: 'http://<your-host>:8000');

Track/cover files are uploaded to Yandex Object Storage (S3-compatible).
Fill in the YANDEX_* environment variables below. If they're not set, the
server falls back to saving files locally under ./uploads and serving them
itself, so you can still test end-to-end without cloud credentials.
"""
import os
import sqlite3
import time
import uuid
from functools import wraps

from flask import Flask, g, jsonify, request, send_from_directory
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash
from werkzeug.utils import secure_filename

# --- Config -----------------------------------------------------------------
DB_PATH = os.environ.get("HARMONY_DB_PATH", "harmony.db")
UPLOAD_DIR = os.environ.get("HARMONY_UPLOAD_DIR", "uploads")
DEVELOPER_EMAILS = set(
    e.strip().lower() for e in os.environ.get("HARMONY_DEV_EMAILS", "dev@example.com").split(",")
)

YANDEX_BUCKET = os.environ.get("YANDEX_BUCKET")
YANDEX_KEY_ID = os.environ.get("YANDEX_KEY_ID")
YANDEX_SECRET = os.environ.get("YANDEX_SECRET")
YANDEX_ENDPOINT = os.environ.get("YANDEX_ENDPOINT", "https://storage.yandexcloud.net")

os.makedirs(UPLOAD_DIR, exist_ok=True)

app = Flask(__name__)
CORS(app)

_s3 = None
if YANDEX_BUCKET and YANDEX_KEY_ID and YANDEX_SECRET:
    import boto3

    _s3 = boto3.client(
        "s3",
        endpoint_url=YANDEX_ENDPOINT,
        aws_access_key_id=YANDEX_KEY_ID,
        aws_secret_access_key=YANDEX_SECRET,
    )


# --- DB helpers ---------------------------------------------------------------
def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    db = sqlite3.connect(DB_PATH)
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL,
            is_developer INTEGER NOT NULL DEFAULT 0,
            token TEXT
        );
        CREATE TABLE IF NOT EXISTS tracks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT,
            cover_url TEXT,
            audio_url TEXT NOT NULL,
            duration_seconds INTEGER DEFAULT 0,
            uploaded_locally INTEGER DEFAULT 0,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            name TEXT NOT NULL,
            cover_url TEXT
        );
        CREATE TABLE IF NOT EXISTS playlist_tracks (
            playlist_id TEXT NOT NULL,
            track_id TEXT NOT NULL,
            PRIMARY KEY (playlist_id, track_id)
        );
        CREATE TABLE IF NOT EXISTS favorites (
            user_id TEXT NOT NULL,
            track_id TEXT NOT NULL,
            PRIMARY KEY (user_id, track_id)
        );
        """
    )
    db.commit()
    db.close()


# --- Auth helpers ---------------------------------------------------------------
def current_user():
    auth = request.headers.get("Authorization", "")
    token = auth.replace("Bearer ", "").strip()
    if not token:
        return None
    row = get_db().execute("SELECT * FROM users WHERE token = ?", (token,)).fetchone()
    return row


def require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        user = current_user()
        if user is None:
            return jsonify({"error": "unauthorized"}), 401
        g.user = user
        return fn(*args, **kwargs)

    return wrapper


def user_to_json(row):
    return {
        "id": row["id"],
        "email": row["email"],
        "display_name": row["display_name"],
        "is_developer": bool(row["is_developer"]),
        "token": row["token"],
    }


def track_to_json(row):
    return {
        "id": row["id"],
        "title": row["title"],
        "artist": row["artist"],
        "album": row["album"],
        "cover_url": row["cover_url"],
        "audio_url": row["audio_url"],
        "duration_seconds": row["duration_seconds"],
        "uploaded_locally": bool(row["uploaded_locally"]),
    }


def playlist_to_json(db, row):
    track_ids = [
        r["track_id"]
        for r in db.execute(
            "SELECT track_id FROM playlist_tracks WHERE playlist_id = ?", (row["id"],)
        ).fetchall()
    ]
    return {"id": row["id"], "name": row["name"], "cover_url": row["cover_url"], "track_ids": track_ids}


# --- Auth routes ---------------------------------------------------------------
@app.post("/auth/register")
def register():
    data = request.get_json(force=True)
    email = data["email"].strip().lower()
    password = data["password"]
    display_name = data.get("display_name") or email.split("@")[0]

    db = get_db()
    if db.execute("SELECT 1 FROM users WHERE email = ?", (email,)).fetchone():
        return jsonify({"error": "An account with this email already exists"}), 400

    user_id = str(uuid.uuid4())
    token = str(uuid.uuid4())
    is_dev = 1 if email in DEVELOPER_EMAILS else 0
    db.execute(
        "INSERT INTO users (id, email, password_hash, display_name, is_developer, token) VALUES (?,?,?,?,?,?)",
        (user_id, email, generate_password_hash(password), display_name, is_dev, token),
    )
    db.commit()
    row = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return jsonify(user_to_json(row))


@app.post("/auth/login")
def login():
    data = request.get_json(force=True)
    email = data["email"].strip().lower()
    password = data["password"]

    db = get_db()
    row = db.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    if row is None or not check_password_hash(row["password_hash"], password):
        return jsonify({"error": "Invalid email or password"}), 400

    token = str(uuid.uuid4())
    db.execute("UPDATE users SET token = ? WHERE id = ?", (token, row["id"]))
    db.commit()
    row = db.execute("SELECT * FROM users WHERE id = ?", (row["id"],)).fetchone()
    return jsonify(user_to_json(row))


# --- Track routes ---------------------------------------------------------------
@app.get("/tracks")
@require_auth
def list_tracks():
    db = get_db()
    rows = db.execute("SELECT * FROM tracks ORDER BY created_at DESC").fetchall()
    return jsonify([track_to_json(r) for r in rows])


@app.get("/tracks/search")
@require_auth
def search_tracks():
    q = f"%{request.args.get('q', '')}%"
    db = get_db()
    rows = db.execute(
        "SELECT * FROM tracks WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?", (q, q, q)
    ).fetchall()
    return jsonify([track_to_json(r) for r in rows])


def _upload_to_storage(file_storage, subdir):
    """Uploads to Yandex Object Storage if configured, otherwise saves
    locally and returns a URL served by this same Flask app."""
    filename = f"{uuid.uuid4()}_{secure_filename(file_storage.filename)}"
    if _s3 is not None:
        key = f"{subdir}/{filename}"
        _s3.upload_fileobj(file_storage, YANDEX_BUCKET, key, ExtraArgs={"ACL": "public-read"})
        return f"{YANDEX_ENDPOINT}/{YANDEX_BUCKET}/{key}"
    else:
        local_dir = os.path.join(UPLOAD_DIR, subdir)
        os.makedirs(local_dir, exist_ok=True)
        path = os.path.join(local_dir, filename)
        file_storage.save(path)
        return f"/files/{subdir}/{filename}"


@app.post("/tracks/upload")
@require_auth
def upload_track():
    if not g.user["is_developer"]:
        return jsonify({"error": "Only developer accounts can upload tracks"}), 403

    title = request.form["title"]
    artist = request.form["artist"]
    album = request.form.get("album", "")
    audio_file = request.files["audio"]
    cover_file = request.files.get("cover")

    audio_url = _upload_to_storage(audio_file, "audio")
    cover_url = _upload_to_storage(cover_file, "covers") if cover_file else ""

    track_id = str(uuid.uuid4())
    db = get_db()
    db.execute(
        "INSERT INTO tracks (id, title, artist, album, cover_url, audio_url, duration_seconds, "
        "uploaded_locally, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
        (track_id, title, artist, album, cover_url, audio_url, 0, 1, int(time.time())),
    )
    db.commit()
    row = db.execute("SELECT * FROM tracks WHERE id = ?", (track_id,)).fetchone()
    return jsonify(track_to_json(row))


@app.get("/files/<subdir>/<filename>")
def serve_local_file(subdir, filename):
    """Only used when Yandex Storage credentials aren't configured."""
    return send_from_directory(os.path.join(UPLOAD_DIR, subdir), filename)


# --- Playlist routes ---------------------------------------------------------------
@app.get("/playlists")
@require_auth
def list_playlists():
    db = get_db()
    rows = db.execute("SELECT * FROM playlists WHERE owner_id = ?", (g.user["id"],)).fetchall()
    return jsonify([playlist_to_json(db, r) for r in rows])


@app.post("/playlists")
@require_auth
def create_playlist():
    data = request.get_json(force=True)
    playlist_id = str(uuid.uuid4())
    db = get_db()
    db.execute(
        "INSERT INTO playlists (id, owner_id, name, cover_url) VALUES (?,?,?,?)",
        (playlist_id, g.user["id"], data["name"], ""),
    )
    db.commit()
    row = db.execute("SELECT * FROM playlists WHERE id = ?", (playlist_id,)).fetchone()
    return jsonify(playlist_to_json(db, row))


@app.post("/playlists/<playlist_id>/tracks")
@require_auth
def add_track_to_playlist(playlist_id):
    data = request.get_json(force=True)
    db = get_db()
    db.execute(
        "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id) VALUES (?,?)",
        (playlist_id, data["track_id"]),
    )
    db.commit()
    return "", 204


@app.delete("/playlists/<playlist_id>/tracks/<track_id>")
@require_auth
def remove_track_from_playlist(playlist_id, track_id):
    db = get_db()
    db.execute(
        "DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?", (playlist_id, track_id)
    )
    db.commit()
    return "", 204


@app.delete("/playlists/<playlist_id>")
@require_auth
def delete_playlist(playlist_id):
    db = get_db()
    db.execute("DELETE FROM playlists WHERE id = ?", (playlist_id,))
    db.execute("DELETE FROM playlist_tracks WHERE playlist_id = ?", (playlist_id,))
    db.commit()
    return "", 204


# --- Favorites routes ---------------------------------------------------------------
@app.get("/favorites")
@require_auth
def list_favorites():
    db = get_db()
    rows = db.execute("SELECT track_id FROM favorites WHERE user_id = ?", (g.user["id"],)).fetchall()
    return jsonify([r["track_id"] for r in rows])


@app.put("/favorites/<track_id>")
@require_auth
def set_favorite(track_id):
    data = request.get_json(force=True)
    db = get_db()
    if data.get("favorite"):
        db.execute(
            "INSERT OR IGNORE INTO favorites (user_id, track_id) VALUES (?,?)", (g.user["id"], track_id)
        )
    else:
        db.execute(
            "DELETE FROM favorites WHERE user_id = ? AND track_id = ?", (g.user["id"], track_id)
        )
    db.commit()
    return "", 204


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8000, debug=True)
