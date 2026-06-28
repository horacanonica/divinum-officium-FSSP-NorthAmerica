import os
import sqlite3
import secrets
import smtplib
import json
import urllib.request
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from contextlib import asynccontextmanager

import bcrypt
import jwt
from fastapi import FastAPI, Request, Form, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

SECRET_KEY = os.environ["SECRET_KEY"]
DB_PATH = "/app/data/auth.db"
WHITELIST_PATH = "/app/whitelist.txt"
TOKEN_EXPIRE_DAYS = 30
RESET_EXPIRE_HOURS = 1

NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "")
SMTP_HOST = os.environ.get("SMTP_HOST", "")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASS = os.environ.get("SMTP_PASS", "")
SMTP_FROM = os.environ.get("SMTP_FROM", "")
SITE_URL = os.environ.get("SITE_URL", "https://localhost")


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with get_db() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                email TEXT PRIMARY KEY,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS pending_requests (
                approve_token       TEXT PRIMARY KEY,
                reject_token        TEXT NOT NULL,
                email               TEXT NOT NULL,
                full_name           TEXT NOT NULL,
                apostolate_location TEXT NOT NULL,
                parish_email        TEXT NOT NULL,
                password_hash       TEXT NOT NULL,
                requested_at        TEXT NOT NULL
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS reset_tokens (
                token TEXT PRIMARY KEY,
                email TEXT NOT NULL,
                expires_at TEXT NOT NULL
            )
        """)


def get_user(email: str):
    with get_db() as db:
        return db.execute("SELECT * FROM users WHERE email = ?", (email.lower(),)).fetchone()


def load_whitelist() -> set:
    try:
        with open(WHITELIST_PATH) as f:
            return {
                line.strip().lower()
                for line in f
                if line.strip() and not line.startswith("#")
            }
    except FileNotFoundError:
        return set()


def create_user(email: str, pw_hash: str):
    with get_db() as db:
        db.execute(
            "INSERT OR IGNORE INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
            (email, pw_hash, datetime.utcnow().isoformat()),
        )


def create_user_from_pending(row):
    with get_db() as db:
        db.execute(
            "INSERT OR IGNORE INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
            (row["email"], row["password_hash"], datetime.utcnow().isoformat()),
        )
        db.execute("DELETE FROM pending_requests WHERE approve_token = ?", (row["approve_token"],))


def make_session_token(email: str) -> str:
    payload = {
        "email": email,
        "exp": datetime.utcnow() + timedelta(days=TOKEN_EXPIRE_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


def verify_session_token(token: str) -> "str | None":
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        return payload["email"]
    except Exception:
        return None


def set_session_cookie(response: Response, email: str):
    token = make_session_token(email)
    response.set_cookie(
        "session", token,
        httponly=True, secure=True, samesite="lax",
        max_age=TOKEN_EXPIRE_DAYS * 86400,
    )


def send_ntfy(approve_token: str, reject_token: str, email: str,
              full_name: str, apostolate_location: str, parish_email: str):
    if not NTFY_TOPIC:
        return
    approve_url = f"{SITE_URL}/auth/approve/{approve_token}"
    reject_url = f"{SITE_URL}/auth/reject/{reject_token}"
    payload = {
        "topic": NTFY_TOPIC,
        "title": f"Access Request: {full_name}",
        "message": (
            f"Location: {apostolate_location}\n"
            f"Login email: {email}\n"
            f"Parish email: {parish_email}"
        ),
        "priority": 3,
        "actions": [
            {"action": "view", "label": "Approve", "url": approve_url, "clear": True},
            {"action": "view", "label": "Reject",  "url": reject_url,  "clear": True},
        ],
    }
    req = urllib.request.Request(
        "https://ntfy.sh",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass  # notification failure is non-fatal


def send_email(to: str, subject: str, body: str):
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = to
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as s:
        s.starttls()
        s.login(SMTP_USER, SMTP_PASS)
        s.send_message(msg)


def _check_reset_token(token: str) -> "str | None":
    if not token:
        return None
    with get_db() as db:
        row = db.execute(
            "SELECT email, expires_at FROM reset_tokens WHERE token = ?", (token,)
        ).fetchone()
    if not row:
        return None
    if datetime.fromisoformat(row["expires_at"]) < datetime.utcnow():
        return None
    return row["email"]


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(lifespan=lifespan)
templates = Jinja2Templates(directory="/app/templates")


# ── Auth check (called by Caddy forward_auth) ─────────────────────────────────

@app.get("/auth/check")
async def auth_check(request: Request):
    token = request.cookies.get("session")
    email = verify_session_token(token) if token else None
    if not email:
        next_url = request.headers.get("X-Forwarded-Uri", "/")
        return Response(status_code=302, headers={"Location": f"/auth/login?next={next_url}"})
    return Response(status_code=200, headers={"X-Auth-Email": email})


# ── Login / Logout ─────────────────────────────────────────────────────────────

@app.get("/auth/login", response_class=HTMLResponse)
async def login_page(request: Request, next: str = "/", message: str = ""):
    return templates.TemplateResponse(
        "login.html", {"request": request, "next": next, "message": message, "error": None}
    )


@app.post("/auth/login")
async def login(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    next: str = Form("/"),
):
    user = get_user(email)
    if user and bcrypt.checkpw(password.encode(), user["password_hash"].encode()):
        response = RedirectResponse(url=next or "/", status_code=303)
        set_session_cookie(response, email.lower())
        return response
    return templates.TemplateResponse(
        "login.html",
        {"request": request, "next": next, "message": "", "error": "Invalid email or password."},
        status_code=401,
    )


@app.get("/auth/logout")
async def logout():
    response = RedirectResponse(url="/auth/login", status_code=303)
    response.delete_cookie("session")
    return response


# ── Request access ─────────────────────────────────────────────────────────────

@app.get("/auth/signup", response_class=HTMLResponse)
async def signup_page(request: Request):
    return templates.TemplateResponse("signup.html", {"request": request, "error": None})


@app.post("/auth/signup", response_class=HTMLResponse)
async def signup_check(request: Request, email: str = Form(...)):
    email = email.lower().strip()
    if get_user(email):
        return templates.TemplateResponse(
            "signup.html",
            {"request": request, "error": "An account with this email already exists."},
            status_code=409,
        )
    if email in load_whitelist():
        return templates.TemplateResponse(
            "signup_ordo_password.html", {"request": request, "email": email, "error": None}
        )
    return templates.TemplateResponse(
        "signup_request.html", {"request": request, "email": email, "error": None}
    )


@app.post("/auth/signup/ordo")
async def signup_ordo(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    confirm_password: str = Form(...),
):
    email = email.lower().strip()
    if password != confirm_password:
        return templates.TemplateResponse(
            "signup_ordo_password.html",
            {"request": request, "email": email, "error": "Passwords do not match."},
            status_code=400,
        )
    if len(password) < 8:
        return templates.TemplateResponse(
            "signup_ordo_password.html",
            {"request": request, "email": email, "error": "Password must be at least 8 characters."},
            status_code=400,
        )
    if get_user(email):
        return templates.TemplateResponse(
            "signup.html",
            {"request": request, "error": "An account with this email already exists."},
            status_code=409,
        )
    if email not in load_whitelist():
        return templates.TemplateResponse(
            "signup.html",
            {"request": request, "error": "This email is not listed in the Ordo Administratus."},
            status_code=403,
        )
    pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    create_user(email, pw_hash)
    return RedirectResponse(
        url="/auth/login?message=Account+created.+You+may+now+sign+in.", status_code=303
    )


@app.get("/auth/signup/request", response_class=HTMLResponse)
async def signup_request_page(request: Request):
    return templates.TemplateResponse(
        "signup_request.html", {"request": request, "email": "", "error": None}
    )


@app.post("/auth/signup/request")
async def signup_request(
    request: Request,
    email: str = Form(...),
    full_name: str = Form(...),
    apostolate_location: str = Form(...),
    parish_email: str = Form(...),
    password: str = Form(...),
    confirm_password: str = Form(...),
):
    email = email.lower().strip()
    parish_email = parish_email.lower().strip()

    if password != confirm_password:
        return templates.TemplateResponse(
            "signup_request.html",
            {"request": request, "email": email, "error": "Passwords do not match."},
            status_code=400,
        )
    if len(password) < 8:
        return templates.TemplateResponse(
            "signup_request.html",
            {"request": request, "email": email, "error": "Password must be at least 8 characters."},
            status_code=400,
        )
    if get_user(email):
        return templates.TemplateResponse(
            "signup_request.html",
            {"request": request, "email": email, "error": "An account with this login email already exists."},
            status_code=409,
        )
    with get_db() as db:
        existing = db.execute(
            "SELECT 1 FROM pending_requests WHERE email = ?", (email,)
        ).fetchone()
    if existing:
        return templates.TemplateResponse(
            "signup_request.html",
            {"request": request, "email": email, "error": "A request from this email is already pending review."},
            status_code=409,
        )

    pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    approve_token = secrets.token_urlsafe(32)
    reject_token = secrets.token_urlsafe(32)

    with get_db() as db:
        db.execute(
            """INSERT INTO pending_requests
               (approve_token, reject_token, email, full_name, apostolate_location,
                parish_email, password_hash, requested_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (approve_token, reject_token, email, full_name.strip(),
             apostolate_location.strip(), parish_email, pw_hash,
             datetime.utcnow().isoformat()),
        )

    send_ntfy(approve_token, reject_token, email, full_name.strip(),
              apostolate_location.strip(), parish_email)

    return templates.TemplateResponse("request_sent.html", {"request": request})


# ── Approve / Reject ───────────────────────────────────────────────────────────

@app.get("/auth/approve/{token}", response_class=HTMLResponse)
async def approve(request: Request, token: str):
    with get_db() as db:
        row = db.execute(
            "SELECT * FROM pending_requests WHERE approve_token = ?", (token,)
        ).fetchone()
    if not row:
        return templates.TemplateResponse(
            "approved.html",
            {"request": request, "already_done": True, "email": None},
        )
    create_user_from_pending(row)
    return templates.TemplateResponse(
        "approved.html",
        {"request": request, "already_done": False, "email": row["email"]},
    )


@app.get("/auth/reject/{token}", response_class=HTMLResponse)
async def reject(request: Request, token: str):
    with get_db() as db:
        row = db.execute(
            "SELECT email FROM pending_requests WHERE reject_token = ?", (token,)
        ).fetchone()
        if row:
            db.execute("DELETE FROM pending_requests WHERE reject_token = ?", (token,))
    return templates.TemplateResponse(
        "rejected.html",
        {"request": request, "found": row is not None},
    )


# ── Forgot / Reset password ────────────────────────────────────────────────────

@app.get("/auth/forgot-password", response_class=HTMLResponse)
async def forgot_password_page(request: Request):
    return templates.TemplateResponse(
        "forgot_password.html", {"request": request, "message": None, "error": None}
    )


@app.post("/auth/forgot-password")
async def forgot_password(request: Request, email: str = Form(...)):
    user = get_user(email)
    if user and SMTP_HOST:
        token = secrets.token_urlsafe(32)
        expires = (datetime.utcnow() + timedelta(hours=RESET_EXPIRE_HOURS)).isoformat()
        with get_db() as db:
            db.execute(
                "INSERT OR REPLACE INTO reset_tokens (token, email, expires_at) VALUES (?, ?, ?)",
                (token, email.lower(), expires),
            )
        reset_url = f"{SITE_URL}/auth/reset-password?token={token}"
        try:
            send_email(
                email,
                "Password Reset — Divinum Officium",
                f"Click the link below to reset your password (expires in 1 hour):\n\n{reset_url}\n\n"
                "If you did not request this, please ignore this email.",
            )
        except Exception:
            pass
    return templates.TemplateResponse(
        "forgot_password.html",
        {
            "request": request,
            "message": "If your email is registered, a reset link has been sent.",
            "error": None,
        },
    )


@app.get("/auth/reset-password", response_class=HTMLResponse)
async def reset_password_page(request: Request, token: str = ""):
    valid = _check_reset_token(token) is not None
    return templates.TemplateResponse(
        "reset_password.html",
        {"request": request, "token": token, "valid": valid, "error": None},
    )


@app.post("/auth/reset-password")
async def reset_password(
    request: Request,
    token: str = Form(...),
    password: str = Form(...),
    confirm_password: str = Form(...),
):
    email = _check_reset_token(token)
    if not email:
        return templates.TemplateResponse(
            "reset_password.html",
            {"request": request, "token": token, "valid": False, "error": None},
        )
    if password != confirm_password:
        return templates.TemplateResponse(
            "reset_password.html",
            {"request": request, "token": token, "valid": True, "error": "Passwords do not match."},
            status_code=400,
        )
    if len(password) < 8:
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request, "token": token, "valid": True,
                "error": "Password must be at least 8 characters.",
            },
            status_code=400,
        )
    pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    with get_db() as db:
        db.execute("UPDATE users SET password_hash = ? WHERE email = ?", (pw_hash, email))
        db.execute("DELETE FROM reset_tokens WHERE token = ?", (token,))
    return RedirectResponse(url="/auth/login?message=Password+updated+successfully", status_code=303)
