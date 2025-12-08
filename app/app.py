from flask import Flask, request, jsonify, abort
from uuid import uuid4
import os 
import requests

app = Flask(__name__)
items = {} 

#@app.route('/', methods=['GET'])
#def index():
#   az_name = os.environ.get('AVAILABILITY_ZONE', 'unknown_az')
#  return jsonify({"message": "Flask API running", "availability_zone": az_name})

@app.route("/zone", methods=['GET'])
def zone():
   az = requests.get("http://169.254.169.254/latest/meta-data/placement/availability-zone").text
   return f"Flask app Running in AZ: {az}"   

@app.route('/items', methods=['GET'])
def list_items():
   return jsonify(list(items.values()))

# ... (rest of the item functions remain unchanged) ...
@app.route('/items/<item_id>', methods=['GET'])
def get_item(item_id):
   item = items.get(item_id)
   if not item:
       abort(404, description="Item not found")
   return jsonify(item)

@app.route('/items', methods=['POST'])
def create_item():
   data = request.get_json(force=True)
   name = data.get('name')
   if not name:
       abort(400, description="Missing 'name' field")
   item_id = str(uuid4())
   item = {
       "id": item_id,
       "name": name,
       "description": data.get('description', "")
   }
   items[item_id] = item
   return jsonify(item), 201

@app.route('/items/<item_id>', methods=['PUT'])
def update_item(item_id):
   if item_id not in items:
       abort(404, description="Item not found")
   data = request.get_json(force=True)
   items[item_id]['name'] = data.get('name', items[item_id]['name'])
   items[item_id]['description'] = data.get('description', items[item_id]['description'])
   return jsonify(items[item_id])

@app.route('/items/<item_id>', methods=['DELETE'])
def delete_item(item_id):
   if item_id not in items:
       abort(404, description="Item not found")
   del items[item_id]
   return '', 204

if __name__ == '__main__':
   app.run(debug=True, host='0.0.0.0', port=5000)
