from flask import Flask
import redis
import mysql.connector

app = Flask(__name__)

@app.route("/")
def home():

  return "API is running"

@app.route("/redis")
def test_redis():
  try:
    r = redis.Redis(host="redis", port=6379, decode_responses=True)
    r.set("key","hello")
    return r.get("key")
  except Exception as e:
    return f"Redis error: {str(e)}"

@app.route("/mysql")
def test_mysql():
  try:
    conn = mysql.connector.connect(
      host="mysql",
      user="root",
      password="123456",
      database="mysql"
    )
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    return str(result)
  except Exception as e:
    return f"MySQL error:{str(e)}"
if __name__ == "__main__":
   app.run(host="0.0.0.0",port=5000)
