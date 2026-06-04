from flask import Flask
from flask_sqlalchemy import SQLAlchemy
import os, socket

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ['DATABASE_URI']
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)
hostname = socket.gethostname()

@app.route('/')
def index():
  return 'Hello, from sunny %s!\n' % hostname

@app.route('/db')
def dbtest():
  return 'Database Connected from %s!\n' % hostname

if __name__ == '__main__':
  app.run()