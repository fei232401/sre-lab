from flask import Flask
import redis
import mysql.connector

app = Flask(__name__)

@app.route("/")
def home():
  return "06-stack API runnning"

@app.route("/redis")
def test_redis():
  try: 
    r = redis.Redis(host="redis",port=6379,
decode_responses=True)
    r.set("k","v")
    return r.get("k")
  except Exception as e:
    return f"Redis error: {e}"

@app.route("/mysql")
def test_mysql():
  try:
    conn = mysql.connector.connect(
      host="mysql",
      user="root",
      password="123456",
      database="srelab"
    )
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    return str(cursor.fetchone())
  except Exception as e:
    return f"MySQL error:{e}"

if __name__  == "__main__":
  app.run(host="0.0.0.0",port=5000)
