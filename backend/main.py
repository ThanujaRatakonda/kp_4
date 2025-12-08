from fastapi import FastAPI
import psycopg2
import time
import os

app = FastAPI()

# Environment variables (from deployment)
DB_HOST = os.environ.get("DB_HOST", "database")
DB_NAME = os.environ.get("DB_NAME", "usersdb")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "admin")
DB_PORT = os.environ.get("DB_PORT", "5432")

def db_conn(retries=10, delay=2):
    """
    Connect to Postgres with retry logic.
    retries: number of attempts
    delay: seconds between attempts
    """
    for i in range(retries):
        try:
            conn = psycopg2.connect(
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                host=DB_HOST,
                port=DB_PORT
            )
            return conn
        except psycopg2.OperationalError:
            print(f"[{i+1}/{retries}] Database not ready, retrying in {delay}s...")
            time.sleep(delay)
    raise Exception("Could not connect to database after multiple retries")

@app.on_event("startup")
def create_table():
    conn = db_conn()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            name TEXT,
            email TEXT
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.post("/add")
def add_user(user: dict):
    conn = db_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO users (name, email) VALUES (%s, %s)", (user["name"], user["email"]))
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "User added!"}

@app.get("/users")
def get_users():
    conn = db_conn()
    cur = conn.cursor()
    cur.execute("SELECT name, email FROM users")
    users = cur.fetchall()
    cur.close()
    conn.close()
    return [{"name": u[0], "email": u[1]} for u in users]

@app.get("/hello")
def hello():
    return {"message": "Hello from Backend with retry logic!"}
