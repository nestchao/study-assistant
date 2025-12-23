# backend/app.py
from flask import Flask, jsonify
from flask_cors import CORS
from services import init_all_services

# Initialize Services BEFORE importing blueprints that use them
init_all_services()

# Now import blueprints (they will import db/models from services.py internally)
from media_routes import media_bp
from study_hub_routes import study_hub_bp
from paper_solver_routes import paper_solver_bp
from code_converter_routes import code_converter_bp
from sync_service_routes import sync_service_bp

app = Flask(__name__)
CORS(app, expose_headers=["Content-Disposition"], allow_headers=["X-User-ID", "Content-Type"])

# Register Blueprints (No dependencies to pass!)
app.register_blueprint(media_bp)
app.register_blueprint(study_hub_bp)
app.register_blueprint(paper_solver_bp)
app.register_blueprint(code_converter_bp)
app.register_blueprint(sync_service_bp)

@app.route('/api/hello')
def hello():
    return jsonify({"message": "Hello from Python!"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)